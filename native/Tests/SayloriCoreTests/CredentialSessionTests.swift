import XCTest
import Security
@testable import SayloriCore

private actor ReadGate {
    var count=0
    var interactiveFlags:[Bool]=[]
    private var completion:CheckedContinuation<Credentials?,Never>?
    private var started:CheckedContinuation<Void,Never>?
    func read(_ interactive:Bool)async->Credentials?{
        count += 1;interactiveFlags.append(interactive)
        return await withCheckedContinuation{completion=$0;started?.resume();started=nil}
    }
    func waitUntilStarted()async{
        if completion != nil{return}
        await withCheckedContinuation{started=$0}
    }
    func finish(_ value:Credentials?){completion?.resume(returning:value);completion=nil}
}

final class CredentialSessionTests:XCTestCase {
    @MainActor func testDeniedSilentReadLeavesDraftEditableAndSessionUsable()async{
        let state=CredentialSession(read:{interactive in
            XCTAssertFalse(interactive)
            throw Keychain.AccessError.status(errSecInteractionNotAllowed)
        },write:{_ in XCTFail("Session-only credentials must not be persisted")})
        await state.load()
        XCTAssertFalse(state.working)
        XCTAssertFalse(state.credentials.isValid)
        state.draft=Credentials(appID:"test-app",accessToken:"test-only-placeholder",legacy:true)
        state.useForSession(state.draft)
        XCTAssertTrue(state.credentials.isValid)
        XCTAssertFalse(state.stored)
    }
    @MainActor func testSingleFlightAndLateReadCannotReplaceNewSession()async{
        let gate=ReadGate()
        let state=CredentialSession(read:{await gate.read($0)})
        let pending=Task{await state.load(interactive:true)}
        await gate.waitUntilStarted()
        await state.load(interactive:true)
        let count=await gate.count
        XCTAssertEqual(count,1)
        state.draft=Credentials(apiKey:"new-test-value")
        state.useForSession(state.draft)
        await gate.finish(Credentials(apiKey:"old-test-value"))
        await pending.value
        XCTAssertEqual(state.credentials.apiKey,"new-test-value")
        XCTAssertEqual(state.draft.apiKey,"new-test-value")
        XCTAssertFalse(state.stored)
        XCTAssertFalse(state.working)
    }
    @MainActor func testBackgroundReadPreservesAnUnsubmittedEdit()async{
        let gate=ReadGate()
        let state=CredentialSession(read:{await gate.read($0)})
        let pending=Task{await state.load()}
        await gate.waitUntilStarted()
        state.draft=Credentials(appID:"edited-app",accessToken:"edited-test-value",legacy:true)
        await gate.finish(Credentials(apiKey:"saved-test-value"))
        await pending.value
        XCTAssertEqual(state.draft.appID,"edited-app")
        XCTAssertEqual(state.draft.accessToken,"edited-test-value")
        XCTAssertEqual(state.credentials.apiKey,"saved-test-value")
        XCTAssertTrue(state.stored)
    }
    @MainActor func testFailedSaveKeepsSessionAndReportsNotSaved()async{
        let state=CredentialSession(read:{_ in nil},write:{_ in throw Keychain.AccessError.status(errSecAuthFailed)})
        let value=Credentials(apiKey:"test-only-placeholder")
        state.useForSession(value)
        await state.persist(value)
        XCTAssertEqual(state.credentials.apiKey,value.apiKey)
        XCTAssertFalse(state.stored)
        XCTAssertFalse(state.working)
        XCTAssertTrue(state.message.contains("未保存"))
    }
}
