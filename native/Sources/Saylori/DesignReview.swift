import AppKit
import SwiftUI
import SayloriCore

/// Reproducible native component exports. Never orders a window on screen, starts
/// audio/network work, reads Keychain, or modifies the user's preferences.
@MainActor enum DesignReview {
    static func render(to directory:URL) {
        try? FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let model=SessionModel(reviewOnly:true)
        model.access.useForSession(Credentials(apiKey:"design-example-not-a-real-key"))
        model.source = .chrome;model.microphoneEnabled=true
        model.microphoneDevice="MacBook Pro 麦克风";model.localModelsReady=true
        model.captionStyle = .dark;model.backgroundOpacity=1;model.showSource=true;model.fontSize=30
        for (name,scheme) in [("light",ColorScheme.light),("dark",ColorScheme.dark)] {
            NSApp.appearance=NSAppearance(named:scheme == .dark ? .darkAqua:.aqua)
            model.microphoneReady=false;model.microphonePassing=false
            model.phase = .idle;model.showingSettings=false
            export(PanelView(model:model),name:"\(name)-menu",scheme:scheme,directory:directory)
            export(SourcePicker(model:model).sourceList.padding(.top,8).background(Brand.card),name:"\(name)-sources",scheme:scheme,directory:directory)
            model.showingSettings=true
            export(PanelView(model:model),name:"\(name)-settings",scheme:scheme,directory:directory)
            model.access.draft.legacy=true;model.access.draft.appID="1234567890";model.access.draft.accessToken="design-example-not-a-real-token"
            export(ConnectionSettings(model:model,access:model.access).padding(Brand.inset).frame(width:Brand.width).background(Brand.surface),name:"\(name)-connection",scheme:scheme,directory:directory)
            model.showingSettings=false;model.phase = .live;model.microphoneReady=true
            model.microphoneProcessingMode=2;model.microphoneRMSDB = -42;model.microphonePassing=false
            export(PanelView(model:model),name:"\(name)-live",scheme:scheme,directory:directory)
            model.microphoneRMSDB = -22;model.microphonePassing=true
            export(PanelView(model:model),name:"\(name)-microphone-passing",scheme:scheme,directory:directory)
            model.phase = .failed;model.notice="无法连接翻译服务，请检查网络后重试。"
            export(PanelView(model:model),name:"\(name)-error",scheme:scheme,directory:directory)
            model.notice="";model.phase = .paused
            export(PanelView(model:model),name:"\(name)-paused",scheme:scheme,directory:directory)
        }
        model.phase = .idle;model.previewing=true
        for style in [CaptionStyle.light,.dark] {
            model.captionStyle=style
            export(CaptionView(model:model).frame(width:720,height:340),name:"\(style.rawValue)-caption",scheme:style == .light ? .light:.dark,directory:directory)
            export(CaptionView(model:model).frame(width:400,height:300),name:"\(style.rawValue)-narrow",scheme:style == .light ? .light:.dark,directory:directory)
        }
    }
    private static func export<V:View>(_ root:V,name:String,scheme:ColorScheme,directory:URL) {
        let host=NSHostingView(rootView:root.environment(\.colorScheme,scheme).environment(\.controlActiveState,.key))
        host.appearance=NSAppearance(named:scheme == .dark ? .darkAqua:.aqua)
        let size=host.fittingSize
        let window=NSWindow(contentRect:NSRect(origin:.zero,size:size),styleMask:.borderless,backing:.buffered,defer:false)
        window.backgroundColor=scheme == .dark ? NSColor(white:0.12,alpha:1):NSColor(white:0.97,alpha:1)
        window.contentView=host;host.frame=NSRect(origin:.zero,size:size)
        RunLoop.main.run(until:Date().addingTimeInterval(0.15))
        host.layoutSubtreeIfNeeded()
        guard let rep=host.bitmapImageRepForCachingDisplay(in:host.bounds) else{return}
        host.cacheDisplay(in:host.bounds,to:rep)
        if let data=rep.representation(using:.png,properties:[:]){try? data.write(to:directory.appendingPathComponent(name+".png"))}
        print("Rendered \(name): \(Int(size.width))×\(Int(size.height)) pt")
        window.contentView=nil
    }
}
