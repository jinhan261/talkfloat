import AppKit
import SwiftUI
import SayloriCore

/// Reproducible native component exports. Never orders a window on screen, starts
/// audio/network work, reads Keychain, or modifies the user's preferences.
@MainActor enum DesignReview {
    static func render(to directory:URL) {
        try? FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        renderLongCaptions(to:directory)
        renderCaptionFocus(to:directory)
        let model=SessionModel(reviewOnly:true)
        model.access.useForSession(Credentials(apiKey:"design-example-not-a-real-key"))
        model.source = .chrome;model.microphoneEnabled=true
        model.microphoneDevice="MacBook Pro 麦克风";model.localModelsReady=true
        model.captionStyle = .dark;model.backgroundOpacity=1;model.showSource=true;model.fontSize=30
        for (name,scheme) in [("light",ColorScheme.light),("dark",ColorScheme.dark)] {
            NSApp.appearance=NSAppearance(named:scheme == .dark ? .darkAqua:.aqua)
            export(HStack(spacing:24){
                VStack(spacing:6){MenuBarActivityPreview(live:false).frame(width:34,height:24);Text("未开始").font(.system(size:11)).foregroundStyle(.secondary)}
                VStack(spacing:6){MenuBarActivityPreview(live:true).frame(width:34,height:24);Text("翻译中").font(.system(size:11)).foregroundStyle(.secondary)}
            }.padding(16).background(Brand.surface),name:"\(name)-menu-status",scheme:scheme,directory:directory)
            model.microphoneReady=false;model.microphonePassing=false
            model.phase = .idle;model.showingSettings=false
            model.mode = .local
            export(PanelView(model:model),name:"\(name)-menu",scheme:scheme,directory:directory)
            export(MicrophoneSection(model:model,expanded:true).modifier(CardSurface()).padding(Brand.inset).frame(width:Brand.width).background(Brand.surface),name:"\(name)-microphone-expanded",scheme:scheme,directory:directory)
            model.mode = .doubao
            export(PanelView(model:model),name:"\(name)-menu-doubao",scheme:scheme,directory:directory)
            model.mode = .local
            export(SourcePicker(model:model).sourceList.padding(.top,8).background(Brand.card),name:"\(name)-sources",scheme:scheme,directory:directory)
            model.showingSettings=true
            export(SettingsView(model:model,setup:SetupCoordinator(model:model),updates:AppUpdater(model:model,enabled:false)).frame(width:640,height:560),name:"\(name)-settings",scheme:scheme,directory:directory)
            let setup=SetupCoordinator(model:model)
            for step in 0..<3 { setup.step=step;export(SetupView(setup:setup,model:model),name:"\(name)-setup-\(step)",scheme:scheme,directory:directory) }
            model.access.draft.legacy=true;model.access.draft.appID="1234567890";model.access.draft.accessToken="design-example-not-a-real-token"
            export(ConnectionSettings(model:model,access:model.access).padding(Brand.inset).frame(width:Brand.width).background(Brand.surface),name:"\(name)-connection",scheme:scheme,directory:directory)
            export(ArchiveSettings(model:model).padding(Brand.inset).frame(width:Brand.width).background(Brand.surface),name:"\(name)-archive",scheme:scheme,directory:directory)
            export(ArchiveLocationRow(directory:URL(fileURLWithPath:"/Volumes/Shared/International projects/2026/Research and product development/Quarterly meetings and bilingual transcripts",isDirectory:true)){}.padding(Brand.inset).frame(width:Brand.width).background(Brand.surface),name:"\(name)-archive-long-path",scheme:scheme,directory:directory)
            model.showingSettings=false;model.phase = .live;model.microphoneReady=true
            model.microphoneProcessingMode=2;model.microphoneRMSDB = -42;model.microphonePassing=false
            export(PanelView(model:model),name:"\(name)-live",scheme:scheme,directory:directory)
            model.microphoneRMSDB = -22;model.microphonePassing=true
            export(PanelView(model:model),name:"\(name)-microphone-passing",scheme:scheme,directory:directory)
            export(MicrophoneSection(model:model,expanded:true).modifier(CardSurface()).padding(Brand.inset).frame(width:Brand.width).background(Brand.surface),name:"\(name)-microphone-expanded-live",scheme:scheme,directory:directory)
            model.phase = .failed;model.notice="本地语音识别已停止，请重新开始。"
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
    /// Exercise the production caption view with final bilingual turns, including
    /// word wrapping at the minimum window size and the largest user font.
    static func renderLongCaptions(to directory:URL) {
        try? FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let model = SessionModel(reviewOnly:true)
        model.mode = .local
        model.phase = .live
        model.showSource = true
        model.captionStyle = .dark
        model.backgroundOpacity = 1
        var item = CaptionSegment(sessionID:"example",startMS:0)
        item.source = "Choose one task and write down the first step."
        item.translation = "选一项任务，写下第一步。"
        item.sourceFinal = true
        item.translationFinal = true
        model.consume(.local(item),sessionID:item.sessionID,origin:.system)
        item.id = UUID()
        item.startMS = 3000
        item.source = "When the timer goes off, write down what you learned so you can pick up where you left off tomorrow morning."
        item.translation = "计时结束后，记下你学到的东西，这样明天早上就能接着做。"
        model.consume(.local(item),sessionID:item.sessionID,origin:.system)
        for (width,height,font) in [(720,340,30),(400,300,30),(400,300,38),(400,520,38)] {
            model.fontSize = CGFloat(font)
            export(CaptionView(model:model).frame(width:CGFloat(width),height:CGFloat(height)),
                   name:"long-\(width)x\(height)-\(font)",scheme:.dark,directory:directory)
        }
    }
    private static func renderCaptionFocus(to directory: URL) {
        // Replay both channels through the normal event handler at minute 60.
        // The later-arriving microphone turn lies inside the system speech.
        let model = SessionModel(reviewOnly:true)
        model.mode = .local
        model.phase = .live
        model.captionStyle = .dark
        model.backgroundOpacity = 1
        model.showSource = true
        model.fontSize = 30
        var system = CaptionSegment(sessionID:"remote",startMS:3_600_000)
        system.audioEpoch = Date().timeIntervalSince1970 - 3605
        system.endMS = 3_605_000
        system.source = "Can we move the meeting to Friday?"
        var mic = CaptionSegment(sessionID:"mic",startMS:3_602_000)
        mic.audioEpoch = system.audioEpoch
        mic.endMS = 3_604_000
        mic.origin = .microphone
        mic.source = "I have one question."
        mic.translation = "我有一个问题。"
        mic.translationFinal = true
        model.consume(.local(system),sessionID:system.sessionID,origin:.system)
        model.consume(.local(mic),sessionID:mic.sessionID,origin:.microphone)
        export(CaptionView(model:model).frame(width:640,height:360),name:"focus-system-english",scheme:.dark,directory:directory)
        system.translation = "我们可以把会议改到周五吗？"
        system.translationFinal = true
        model.consume(.local(system),sessionID:system.sessionID,origin:.system)
        export(CaptionView(model:model).frame(width:640,height:360),name:"focus-system-chinese",scheme:.dark,directory:directory)
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

private struct MenuBarActivityPreview:NSViewRepresentable {
    let live:Bool
    func makeNSView(context:Context)->NSButton {
        let button=NSButton(frame:NSRect(x:0,y:0,width:34,height:24))
        button.image=TalkFloatArtwork.menuImage();button.imagePosition = .imageOnly
        button.isBordered=false
        let badge=MenuBarActivityBadge(frame:button.bounds)
        badge.autoresizingMask=[.width,.height];badge.isHidden = !live
        button.addSubview(badge)
        return button
    }
    func updateNSView(_ button:NSButton,context:Context){}
}
