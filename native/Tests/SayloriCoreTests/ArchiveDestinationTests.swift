import XCTest
@testable import SayloriCore

final class ArchiveDestinationTests:XCTestCase {
    private func record(ended:Bool=false)->MeetingRecord {
        var r=MeetingRecord(sourceName:"System + mic")
        var s=CaptionSegment(sessionID:"s",startMS:0)
        s.source="We meet on Friday.";s.translation="我们周五见。";s.sourceFinal=true;s.translationFinal=true
        var m=s;m.id=UUID();m.sessionID="m";m.origin = .microphone;m.source="I will join.";m.translation="我会参加。"
        r.segments=[s,m];r.revision=2
        if ended{r.endedAt=Date();r.status="已结束"}
        return r
    }
    private func folders()throws->(URL,URL,URL) {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("talkfloat-archive-test-\(UUID())")
        let records=root.appendingPathComponent("Records")
        try FileManager.default.createDirectory(at:records,withIntermediateDirectories:true)
        addTeardownBlock{try? FileManager.default.removeItem(at:root)}
        return(root,records,root.appendingPathComponent("Recovery"))
    }
    func testOnlyMarkdownInSelectedFolderAndCheckpointRemovedAfterEnd()async throws{
        let (_,folder,recovery)=try folders();let store=TranscriptStore(directory:folder,recoveryDirectory:recovery)
        var r=record();let saved=try await store.save(r);let url=try XCTUnwrap(saved)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:folder.path),[url.lastPathComponent])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:recovery.path).count,1)
        r.revision += 1;r.endedAt=Date();r.status="已结束";_ = try await store.save(r)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:recovery.path).isEmpty)
        let md=try String(contentsOf:url,encoding:.utf8)
        for text in ["We meet on Friday.","我们周五见。","I will join.","我会参加。","麦克风声音"]{XCTAssertTrue(md.contains(text))}
    }
    func testRestartRecoversIntoOriginalFolderEvenAfterPreferenceChanges()async throws{
        let (root,folder,recovery)=try folders();let r=record()
        let saved=try await TranscriptStore(directory:folder,recoveryDirectory:recovery).save(r);let url=try XCTUnwrap(saved)
        let other=root.appendingPathComponent("Other");try FileManager.default.createDirectory(at:other,withIntermediateDirectories:true)
        try await TranscriptStore(directory:other,recoveryDirectory:recovery).recoverInterrupted()
        XCTAssertTrue(try String(contentsOf:url,encoding:.utf8).contains("已恢复"))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:other.path).isEmpty)
    }
    func testFailedFinalRetainsNewerCheckpointAndCanRetryAnotherFolder()async throws{
        let (root,folder,recovery)=try folders();let store=TranscriptStore(directory:folder,recoveryDirectory:recovery)
        let old=record();_ = try await store.save(old)
        try FileManager.default.removeItem(at:folder)
        var final=old;final.revision=3;final.endedAt=Date();final.status="已结束";final.segments[0].translation="我们星期五见。"
        do{_ = try await store.save(final);XCTFail("Missing folder must not be recreated")}catch{}
        _ = try await store.save(old)
        let cp=try PropertyListDecoder().decode(TranscriptStore.Checkpoint.self,from:Data(contentsOf:recovery.appendingPathComponent(final.id.uuidString+".plist")))
        XCTAssertEqual(cp.record.revision,3);XCTAssertNotNil(cp.record.endedAt)
        let other=root.appendingPathComponent("Other");try FileManager.default.createDirectory(at:other,withIntermediateDirectories:true)
        try await store.changeDirectory(to:other)
        let saved=try await store.save(final);let url=try XCTUnwrap(saved)
        XCTAssertEqual(url.deletingLastPathComponent().path,other.path)
        XCTAssertTrue(try String(contentsOf:url,encoding:.utf8).contains("我们星期五见。"))
        _ = try await store.save(old)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:recovery.path).isEmpty)
    }
    func testLegacyOwnedJSONIsBackedUpAndUnrelatedJSONUntouched()async throws{
        let (_,folder,recovery)=try folders();let r=record(ended:true)
        let formatter=DateFormatter();formatter.dateFormat="yyyyMMdd-HHmmss"
        let base=folder.appendingPathComponent("\(formatter.string(from:r.startedAt))-\(r.id.uuidString.prefix(8))")
        let encoder=JSONEncoder();encoder.dateEncodingStrategy = .iso8601
        let json=try encoder.encode(r);try json.write(to:base.appendingPathExtension("json"))
        try Data(r.markdown.utf8).write(to:base.appendingPathExtension("md"))
        let unrelated=folder.appendingPathComponent("unrelated.json");try json.write(to:unrelated)
        try await TranscriptStore(directory:folder,recoveryDirectory:recovery).recoverInterrupted(legacyDirectory:folder)
        XCTAssertTrue(FileManager.default.fileExists(atPath:unrelated.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath:base.appendingPathExtension("json").path))
        XCTAssertEqual(try Data(contentsOf:recovery.appendingPathComponent("Legacy").appendingPathComponent(base.lastPathComponent+".json")),json)
        XCTAssertEqual(try String(contentsOf:base.appendingPathExtension("md"),encoding:.utf8),r.markdown)
    }
}
