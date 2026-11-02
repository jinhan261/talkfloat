import SwiftUI
import Translation
import Speech

struct LocalModelPreparation:ViewModifier {
    @ObservedObject var model:SessionModel
    func body(content:Content)->some View {
        if #available(macOS 26.4,*) {
            content.translationTask(model.preparingLocalModels ? TranslationSession.Configuration(source:Locale.Language(identifier:"en"),target:Locale.Language(identifier:"zh-Hans"),preferredStrategy:.lowLatency):nil){ session in
                do {
                    try await session.prepareTranslation()
                    let speech=SpeechTranscriber(locale:Locale(identifier:"en-US"),preset:.progressiveTranscription)
                    _ = try await AssetInventory.reserve(locale:Locale(identifier:"en-US"))
                    if let request=try await AssetInventory.assetInstallationRequest(supporting:[speech]){try await request.downloadAndInstall()}
                    model.localModelsReady=await FastPreview.available()
                    model.localModelNotice=model.localModelsReady ? "本地英语与中文模型已就绪":"语言模型尚未准备好，请重试。"
                }catch{model.localModelNotice="模型准备未完成："+error.localizedDescription}
                model.preparingLocalModels=false
            }
        }else{content}
    }
}
