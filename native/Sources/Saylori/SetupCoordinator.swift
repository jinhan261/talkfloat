import AppKit
import AVFoundation
import Combine
import SayloriCore

@MainActor final class SetupCoordinator: ObservableObject {
    @Published var step=0{didSet{if oldValue != step && !working{result=""}}}
    @Published private(set) var working=false
    @Published private(set) var result=""
    @Published private(set) var microphoneAuthorized=false
    @Published private(set) var microphoneDenied=false
    @Published private(set) var samplePassed=false
    private var task:Task<Void,Never>?
    private var player:Process?
    private var ownsSession=false
    let model:SessionModel
    let runningFromReadOnlyVolume=(try? Bundle.main.bundleURL.resourceValues(forKeys:[.volumeIsReadOnlyKey]).volumeIsReadOnly) == true
    var onClose:(()->Void)?
    init(model:SessionModel){self.model=model;refreshMicrophone()}
    func refreshMicrophone(){
        let status=AVCaptureDevice.authorizationStatus(for:.audio)
        microphoneAuthorized=status == .authorized
        microphoneDenied=status == .denied || status == .restricted
    }
    func requestMicrophone(){
        guard !working else{return}
        Task{
            _ = await AVCaptureDevice.requestAccess(for:.audio)
            refreshMicrophone()
        }
    }
    func checkSystemSound(){
        guard !working,!model.active,!model.hasMeeting,!runningFromReadOnlyVolume else{return}
        let previousSource=model.source;model.source = .system
        working=true;model.setupInProgress=true;ownsSession=true;result="请播放一段声音。检测只在本机进行，不上传音频。"
        task=Task{
            result=await model.testAudio()
            model.source=previousSource
            ownsSession=false;working=false;model.setupInProgress=false;task=nil
        }
    }
    func prepareModels(){
        guard !model.preparingLocalModels,!model.active,!working else{return}
        model.modelPreparationID=UUID()
        model.preparingLocalModels=true
        model.localModelNotice="正在准备英语识别和中文翻译资源…"
    }
    func runSample(){
        guard !working,!model.active,!model.hasMeeting,model.canStart,!runningFromReadOnlyVolume else{return}
        guard model.mode != .local || model.localModelsReady else{result="请先准备本地语言资源。";step=0;return}
        guard let sample=Bundle.main.url(forResource:"EnglishSample",withExtension:"aiff") else{result="示例音频缺失，请重新安装 TalkFloat。";return}
        let previousSource=model.source,previousMic=model.microphoneEnabled
        working=true;model.setupInProgress=true;ownsSession=true;samplePassed=false
        result="正在连接。随后会播放一段约 20 秒的英语。"
        // The fixed sample tests system sound; the microphone is an independent,
        // explicit opt-in. An afplay child process makes the same HAL path as a player.
        model.source = .system;model.microphoneEnabled=false
        task=Task{
            defer{
                if let player,self.player?.isRunning == true{player.terminate()};self.player=nil
                if !model.hasMeeting {model.source=previousSource;model.microphoneEnabled=previousMic}
                working=false;model.setupInProgress=false;ownsSession=false;task=nil
            }
            do{
                model.start()
                for _ in 0..<150 {
                    try Task.checkCancellation()
                    if model.phase == .live{break}
                    if model.phase == .failed{throw SayError.message(model.notice)}
                    try await Task.sleep(for:.milliseconds(200))
                }
                guard model.phase == .live else{throw SayError.message("翻译未能启动，请检查声音和模型状态。")}
                let process=Process();process.executableURL=URL(fileURLWithPath:"/usr/bin/afplay");process.arguments=[sample.path]
                process.standardOutput=FileHandle.nullDevice;process.standardError=FileHandle.nullDevice
                player=process;try process.run();result="正在播放示例。请观察悬浮字幕中的英文与中文。"
                while process.isRunning{try await Task.sleep(for:.milliseconds(200))}
                guard process.terminationStatus==0 else{throw SayError.message("示例播放失败，请检查声音输出设备。")}
                // Give final recognition/translation time to finish, then use the
                // normal stop path to flush final text and write Markdown.
                try await Task.sleep(for:.seconds(5))
                await model.stop()
                samplePassed = SampleCoverage.isComplete(model.captions.segments) && model.archiveURL != nil && model.archiveError.isEmpty && !model.hasMeeting
                result=samplePassed ? "已收到中英字幕，并保存示例记录。可打开记录核对日期和金额。":"测试尚未完成：请检查播放器音量、译文和记录保存状态后重试。"
            }catch{
                await model.stop()
                result=error is CancellationError ? "测试已停止；已产生的文字按正常流程保存。":error.localizedDescription
            }
        }
    }
    func cancel(){
        task?.cancel()
        if player?.isRunning == true{player?.terminate()}
        if ownsSession{Task{await model.stop()}}
    }
    func cancelPreparation(){model.modelPreparationID=UUID();model.preparingLocalModels=false;model.localModelNotice="已停止准备，稍后可继续。"}
    func finish(){
        guard !working,!model.preparingLocalModels else{return}
        UserDefaults.standard.set(true,forKey:"setupSeenV1")
        onClose?()
    }
}

enum PermissionLinks {
    static func systemAudio(){open("Privacy_ScreenCapture")}
    static func microphone(){open("Privacy_Microphone")}
    private static func open(_ anchor:String){NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?"+anchor)!)}
}
