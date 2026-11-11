import SwiftUI
import Translation
import Speech

struct LocalModelPreparation:ViewModifier {
    @ObservedObject var model:SessionModel
    func body(content:Content)->some View {
        if #available(macOS 26.4,*) {
            content.translationTask(model.preparingLocalModels ? TranslationSession.Configuration(source:Locale.Language(identifier:"en"),target:Locale.Language(identifier:"zh-Hans"),preferredStrategy:.lowLatency):nil){ session in
                let requestID=model.modelPreparationID
                do {
                    try await session.prepareTranslation()
                    try Task.checkCancellation()
                    let speech=SpeechTranscriber(locale:Locale(identifier:"en-US"),preset:.progressiveTranscription)
                    _ = try await AssetInventory.reserve(locale:Locale(identifier:"en-US"))
                    if let request=try await AssetInventory.assetInstallationRequest(supporting:[speech]){try await request.downloadAndInstall()}
                    try Task.checkCancellation()
                    guard model.modelPreparationID==requestID else{return}
                    model.localModelsReady=await FastPreview.available()
                    model.localModelNotice=model.localModelsReady ? "本地英语与中文模型已就绪":"语言模型尚未准备好，请重试。"
                }catch{guard model.modelPreparationID==requestID else{return};model.localModelNotice=error is CancellationError ? "已停止准备，稍后可继续。":"模型准备未完成："+error.localizedDescription}
                guard model.modelPreparationID==requestID else{return}
                model.preparingLocalModels=false
            }
        }else{content}
    }
}
