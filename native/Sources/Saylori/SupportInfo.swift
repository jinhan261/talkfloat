import AppKit
import AVFoundation

@MainActor enum SupportInfo {
    static func copy(model:SessionModel){
        let bundle=Bundle.main
        let lines=[
            "TalkFloat diagnostics (no audio, transcript, credentials or file paths)",
            "Version: \(bundle.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "unknown") (\(bundle.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "unknown"))",
            "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Engine: \(model.mode.rawValue)","State: \(model.phase.rawValue)",
            "Source: \(model.source.id)","Local assets ready: \(model.localModelsReady)",
            "System audio check: \(model.audioProbe?.outcome.rawValue ?? "not checked")",
            "System signal observed: \(model.systemSignalObserved)",
            "Microphone authorization: \(AVCaptureDevice.authorizationStatus(for:.audio).rawValue)",
            "Microphone enabled: \(model.microphoneEnabled)","Microphone ready: \(model.microphoneReady)",
            "Unsaved record: \(!model.archiveError.isEmpty)","Archive destination available: \(model.archiveLocationError.isEmpty)",
            "Capture resources released: \(model.resourcesReleased)"
        ]
        NSPasteboard.general.clearContents();NSPasteboard.general.setString(lines.joined(separator:"\n"),forType:.string)
    }
}

struct RecoveryAdvice {
    let title:String
    let detail:String
    enum Action{case setup,connection,archive,retry}
    let action:Action
    static func forMessage(_ message:String)->Self{
        if message.contains("保存") || message.contains("文件夹") || message.contains("存储位置"){
            return .init(title:"会议记录需要处理",detail:"文字会保留供重试，请检查存储位置。",action:.archive)
        }
        if message.contains("模型") || message.contains("语言资源"){
            return .init(title:"本地模型尚未就绪",detail:"打开首次设置，准备英语与中文资源。",action:.setup)
        }
        if message.contains("权限") || message.contains("授权") || message.contains("采音") || message.contains("音频") || message.contains("音源"){
            return .init(title:"需要检查声音输入",detail:"检测系统声音，或查看仅系统录音权限。",action:.setup)
        }
        if message.contains("凭据") || message.contains("Token") || message.contains("API") || message.contains("401") || message.contains("403"){
            return .init(title:"翻译连接需要处理",detail:"检查豆包凭据与服务状态后重试。",action:.connection)
        }
        return .init(title:"翻译暂时停止",detail:"可重新开始；详细原因保留在下方。",action:.retry)
    }
}
