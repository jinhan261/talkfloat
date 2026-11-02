import Foundation
import SayloriCore

enum TranslationUpdate:Sendable {
    case cloud(ASTEvent)
    case local(CaptionSegment)
}

protocol TranslationEngine:AudioSending {
    var sessionID:String{get}
    var updates:AsyncThrowingStream<TranslationUpdate,Error>{get}
    func start(_ credentials:Credentials) async throws
    func finish() async ->Bool
    func abort() async
}

actor DoubaoEngine:TranslationEngine {
    nonisolated let sessionID:String
    nonisolated let updates:AsyncThrowingStream<TranslationUpdate,Error>
    private let continuation:AsyncThrowingStream<TranslationUpdate,Error>.Continuation
    private let client=ASTClient()
    private var bridge:Task<Void,Never>?
    init(){
        sessionID=client.sessionID
        let pair=AsyncThrowingStream<TranslationUpdate,Error>.makeStream(bufferingPolicy:.bufferingOldest(200))
        updates=pair.stream;continuation=pair.continuation
    }
    func start(_ credentials:Credentials) async throws {
        await MainActor.run{TestDiagnostics.record("cloud-connection",["session":sessionID])}
        try await client.connect(credentials)
        bridge=Task{
            do{for try await event in client.events {
                if case .dropped=continuation.yield(.cloud(event)){throw SayError.message("字幕接收积压，已停止收听。")}
            };continuation.finish()}catch{continuation.finish(throwing:error)}
        }
    }
    func send(_ audio:Data) async throws{try await client.send(audio)}
    func finish() async ->Bool {let ok=await client.finish();await bridge?.value;return ok}
    func abort() async {await client.abort();bridge?.cancel();bridge=nil;continuation.finish()}
}

@available(macOS 26.4,*)
@MainActor final class AppleTranslationEngine:TranslationEngine {
    nonisolated let sessionID=UUID().uuidString
    nonisolated let updates:AsyncThrowingStream<TranslationUpdate,Error>
    private let continuation:AsyncThrowingStream<TranslationUpdate,Error>.Continuation
    private let origin:AudioOrigin
    private var pipeline:FastPreview?
    private var failure:String?
    init(origin:AudioOrigin){
        self.origin=origin
        let pair=AsyncThrowingStream<TranslationUpdate,Error>.makeStream(bufferingPolicy:.bufferingOldest(200))
        updates=pair.stream;continuation=pair.continuation
    }
    func start(_ credentials:Credentials) async throws {
        guard await FastPreview.available() else{throw SayError.message("请先准备本地英语与中文模型；本地模式不会调用豆包。")}
        let pipeline=FastPreview(sessionID:sessionID,origin:origin,complete:true);self.pipeline=pipeline
        pipeline.onCaption={[weak self] item in
            guard let self else{return}
            if case .dropped=self.continuation.yield(.local(item)){self.fail("本地字幕接收积压，已停止该路收听。")}
        }
        pipeline.onFailure={[weak self] message in self?.fail(message)}
        try await pipeline.start()
        TestDiagnostics.record("local-engine-ready",["session":sessionID,"origin":origin.rawValue])
    }
    private func fail(_ message:String){
        guard failure==nil else{return};failure=message
        continuation.finish(throwing:SayError.message(message))
    }
    func send(_ audio:Data) async throws {
        if let failure{throw SayError.message(failure)}
        guard let pipeline else{throw SayError.message("本地翻译尚未准备好")}
        guard pipeline.feed(audio) else{throw SayError.message("本地识别音频积压，已停止该路收听。")}
    }
    func finish() async ->Bool {
        let ok=await pipeline?.finish() ?? false
        pipeline=nil;continuation.finish();return ok && failure==nil
    }
    func abort() async {await pipeline?.stop();pipeline=nil;continuation.finish()}
}
