import Foundation
import SayloriCore

@MainActor final class MicrophoneRoute {
    let audio=MicrophoneAudio()
    let service:any TranslationEngine
    let nearSpeechGate=NearSpeechGate()
    private var sender:Task<Void,Error>?
    private var receiver:Task<Void,Never>?
    private var connection:Task<Void,Never>?
    private var ended=false
    private var connected=false
    private var finishing:Task<Void,Never>?
    var onUpdate:((TranslationUpdate)->Void)?
    var onReady:(()->Void)?
    var onFailure:((String)->Void)?
    var onSent:((AudioSendStats)->Void)?
    var onGate:((NearSpeechGate.Observation)->Void)?
    var onAudio:(@Sendable (Data,AudioSendStats)->Void)?
    private let processAudio:@Sendable (AudioPacket)->AudioPacket
    init(service:any TranslationEngine,processAudio:@escaping @Sendable (AudioPacket)->AudioPacket = {$0}){self.service=service;self.processAudio=processAudio}
    func start(_ credentials:Credentials){
        connection=Task{[self] in
            do{
                try await audio.start()
                guard !ended else{await audio.stop();return}
                let relay=AudioRelay(service:service)
                let audioObserver=onAudio
                let processor=processAudio
                sender=Task.detached{[weak self,audio=audio,gate=nearSpeechGate] in
                    var packets=MicrophonePacketProcessor(gate:gate,transform:processor)
                    var lastDiagnostics=0.0
                    var lastMeter=0.0
                    for try await packet in audio.frames{
                        try Task.checkCancellation()
                        guard let cleaned=packets.append(packet) else{continue}
                        if let stats=try await relay.forward(cleaned){audioObserver?(cleaned.data,stats);await self?.sent(stats)}
                        let now=ProcessInfo.processInfo.systemUptime
                        if now-lastMeter>=0.16{lastMeter=now;await self?.reportGate(gate.observation)}
                        if now-lastDiagnostics>=1{lastDiagnostics=now;let metrics=gate.diagnostics;await MainActor.run{TestDiagnostics.record("microphone-gate",metrics)}}
                    }
                    for cleaned in packets.finish() {
                        if let stats=try await relay.forward(cleaned){audioObserver?(cleaned.data,stats);await self?.sent(stats)}
                    }
                }
                try await service.start(credentials)
                guard !ended else{await service.abort();return}
                TestDiagnostics.record("connection-ready",["session":service.sessionID,"origin":"microphone"])
                await relay.enable();connected=true;onReady?()
                receiver=Task{
                    do{for try await update in service.updates{self.onUpdate?(update)}}
                    catch{await self.fail(error)}
                }
                do{try await sender?.value}catch{await fail(error)}
            }catch{await fail(error)}
        }
    }
    private func sent(_ s:AudioSendStats){
        guard !ended else{return};onSent?(s)
        TestDiagnostics.record("audio-send",["origin":"microphone","session":service.sessionID,"queueMS":s.queueMS,"sendMS":s.sendMS,"audioEndMS":s.audioEndMS,"sendUptime":s.sendUptime])
    }
    private func reportGate(_ observation:NearSpeechGate.Observation){guard !ended else{return};onGate?(observation)}
    private func fail(_ error:Error) async {
        guard !ended else{return};ended=true
        // Do not await the task which called fail().
        onFailure?(error.localizedDescription);await audio.stop();sender?.cancel();await service.abort()
    }
    func stop() async {
        if let finishing{await finishing.value;return}
        ended=true
        let task=Task{
            await audio.stop()
            let deadline=Task{try? await Task.sleep(for:.seconds(2));if !Task.isCancelled{await self.service.abort()}}
            _ = try? await sender?.value;deadline.cancel()
            let complete=await service.finish();await receiver?.value
            if connected,!complete{onFailure?("麦克风声音最后一句可能尚未定稿；已收到内容已保留。")}
            connected=false
            connection?.cancel();sender=nil;receiver=nil;connection=nil
        }
        finishing=task;await task.value
    }
}
