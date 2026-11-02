import AppKit
import SwiftUI
import Combine
import SayloriCore

@MainActor final class SubtitlePanel:NSPanel {
    override var canBecomeKey:Bool{true}
    override var canBecomeMain:Bool{false}
    var dragLocked=false
    private var dragOrigin:NSPoint?
    private var mouseOrigin=NSPoint.zero
    private var resizeOrigin:NSRect?
    private var resizeEdges:CaptionEdges=[]
    override func sendEvent(_ event:NSEvent){
        switch event.type {
        case .leftMouseDown:
            let point=event.locationInWindow
            let tools=NSRect(x:frame.width-144,y:frame.height-42,width:124,height:30)
            let edges=CaptionEdges.hit(point,size:frame.size)
            if !dragLocked,!edges.isEmpty {
                resizeOrigin=frame;resizeEdges=edges;mouseOrigin=convertPoint(toScreen:point);return
            }
            if !dragLocked,!tools.contains(point){
                dragOrigin=frame.origin;mouseOrigin=convertPoint(toScreen:point)
                return
            }
        case .leftMouseDragged:
            if let origin=resizeOrigin {
                let point=convertPoint(toScreen:event.locationInWindow)
                setFrame(resizeEdges.resizing(origin,delta:NSSize(width:point.x-mouseOrigin.x,height:point.y-mouseOrigin.y),minimum:minSize,maximum:maxSize),display:true)
                return
            }
            if let origin=dragOrigin {
                let point=convertPoint(toScreen:event.locationInWindow)
                setFrameOrigin(NSPoint(x:origin.x+point.x-mouseOrigin.x,y:origin.y+point.y-mouseOrigin.y))
                return
            }
        case .leftMouseUp:
            if resizeOrigin != nil {
                resizeOrigin=nil
                UserDefaults.standard.set(NSStringFromPoint(frame.origin),forKey:"captionOrigin")
                UserDefaults.standard.set(NSStringFromSize(frame.size),forKey:"captionSize")
                TestDiagnostics.record("edge-resize",["edges":resizeEdges.rawValue,"frame":NSStringFromRect(frame)])
                return
            }
            if let origin=dragOrigin {
                dragOrigin=nil
                UserDefaults.standard.set(NSStringFromPoint(frame.origin),forKey:"captionOrigin")
                TestDiagnostics.record("content-drag",["moved":origin != frame.origin,"frame":NSStringFromRect(frame)])
                return
            }
        default:break
        }
        // Scroll-wheel events still reach the SwiftUI scroll views. Toolbar clicks
        // and the resize grip keep their normal behavior.
        super.sendEvent(event)
    }
}

@MainActor final class AppDelegate:NSObject,NSApplicationDelegate,NSWindowDelegate {
    let model=SessionModel()
    private var status:NSStatusItem!
    private let popover=NSPopover()
    private var panel:NSPanel!
    private var subscriptions=Set<AnyCancellable>()
    private var terminating=false
    private var harness:Task<Void,Never>?
    func applicationDidFinishLaunching(_ notification:Notification){
        NSApp.setActivationPolicy(.accessory)
        if CommandLine.arguments.contains("--dark-appearance"){NSApp.appearance=NSAppearance(named:.darkAqua)}
        installMainMenu()
        status=NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        status.button?.image=NSImage(systemSymbolName:"bird.fill",accessibilityDescription:"Saylori 实时翻译")
        status.button?.target=self;status.button?.action=#selector(togglePopover)
        status.button?.toolTip="Saylori · 英语实时翻译"
        // UI inspection can pin this transient surface without changing ordinary launches.
        popover.behavior = CommandLine.arguments.contains("--pin-test-popover") ? .applicationDefined:.transient
        let appearanceOverride:ColorScheme?=CommandLine.arguments.contains("--dark-appearance") ? .dark:nil
        popover.contentViewController=NSHostingController(rootView:PanelView(model:model).preferredColorScheme(appearanceOverride))
        popover.contentSize=NSSize(width:Brand.width,height:400)
        panel=SubtitlePanel(contentRect:NSRect(x:0,y:0,width:720,height:340),styleMask:[.borderless,.nonactivatingPanel,.resizable],backing:.buffered,defer:false)
        panel.title="Saylori 字幕";panel.level = .floating;panel.isFloatingPanel=true
        panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]
        panel.isMovableByWindowBackground=true;panel.backgroundColor = .clear;panel.isOpaque=false;panel.hasShadow=true
        panel.minSize=NSSize(width:400,height:300);panel.maxSize=NSSize(width:1600,height:1100)
        panel.hidesOnDeactivate=false;panel.delegate=self
        panel.contentView=NSHostingView(rootView:CaptionView(model:model).preferredColorScheme(appearanceOverride))
        placePanel()
        model.onSettings={[weak self] in self?.showPopover()}
        model.onPreview={[weak self] in
            self?.popover.performClose(nil)
            if CommandLine.arguments.contains("--ui-review"){
                self?.panel.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
            }
        }
        model.onFailure={[weak self] in self?.showPopover()}
        model.onResetCaption={[weak self] in self?.resetPanel();self?.panel.orderFrontRegardless()}
        model.onLive={[weak self] in self?.popover.performClose(nil)}
        model.onVisibility={[weak self] show in if show{self?.clampPanel();self?.panel.orderFrontRegardless()}else{self?.panel.orderOut(nil)}}
        model.onLock={[weak self] locked in
            (self?.panel as? SubtitlePanel)?.dragLocked=locked
            self?.panel.isMovableByWindowBackground = !locked
            if locked{self?.panel.styleMask.remove(.resizable)}else{self?.panel.styleMask.insert(.resizable)}
        }
        model.$phase.sink{[weak self]phase in
            self?.status.button?.contentTintColor=phase == .live ? NSColor.controlAccentColor:nil
            self?.status.button?.toolTip="Saylori · \(phase.rawValue)"
        }.store(in:&subscriptions)
        model.$showSource.dropFirst().sink{[weak self]show in
            guard let self,show,self.panel.frame.height<168 else{return}
            var frame=self.panel.frame;frame.origin.y-=168-frame.height;frame.size.height=168
            self.panel.setFrame(frame,display:true);self.clampPanel()
        }.store(in:&subscriptions)
        NotificationCenter.default.addObserver(self,selector:#selector(screenChanged),name:NSApplication.didChangeScreenParametersNotification,object:nil)
        DistributedNotificationCenter.default().addObserver(self,selector:#selector(showExistingInstance),name:Notification.Name("app.saylori.show"),object:nil)
        DispatchQueue.main.asyncAfter(deadline:.now()+0.5){
            self.showPopover()
            if CommandLine.arguments.contains("--ui-review"){self.harness=Task{await self.runVisualReview()}}
            else if CommandLine.arguments.contains("--meeting-test"){self.harness=Task{await self.runMeetingTest()}}
            else if TestDiagnostics.directory != nil{self.harness=Task{await self.runSelfTest()}}
            else if CommandLine.arguments.contains("--audio-check"){Task{self.model.notice=await self.model.testAudio()}}
            else if CommandLine.arguments.contains("--preview-caption"){self.model.previewCaption()}
        }
    }
    private func installMainMenu(){
        let menu=NSMenu()
        let appItem=NSMenuItem();menu.addItem(appItem)
        let appMenu=NSMenu(title:"Saylori");appItem.submenu=appMenu
        appMenu.addItem(withTitle:"退出 Saylori",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        let editItem=NSMenuItem();menu.addItem(editItem)
        let edit=NSMenu(title:"编辑");editItem.submenu=edit
        for (title,selector,key) in [("撤销","undo:","z"),("剪切","cut:","x"),("复制","copy:","c"),("粘贴","paste:","v"),("全选","selectAll:","a")]{
            edit.addItem(withTitle:title,action:NSSelectorFromString(selector),keyEquivalent:key)
        }
        NSApp.mainMenu=menu
    }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool)->Bool{showPopover();return false}
    private func showPopover(){
        guard !popover.isShown,let button=status.button else{return}
        model.refreshSources();NSApp.activate(ignoringOtherApps:true)
        popover.show(relativeTo:button.bounds,of:button,preferredEdge:.minY)
        popover.contentViewController?.view.window?.makeKey()
    }
    @objc func togglePopover(){if popover.isShown{popover.performClose(nil)}else{showPopover()}}
    @objc private func showExistingInstance(){showPopover()}
    private func resetPanel(){
        let screen=status.button?.window?.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        panel.setFrameOrigin(NSPoint(x:screen.midX-panel.frame.width/2,y:screen.minY+72))
    }
    private func placePanel(){
        let screen=NSScreen.main?.visibleFrame ?? NSRect(x:0,y:0,width:1440,height:900)
        if let size=UserDefaults.standard.string(forKey:"captionSize"){
            let saved=NSSizeFromString(size)
            if saved.width>=380 && saved.height>=112{panel.setContentSize(NSSize(width:max(400,min(1600,saved.width)),height:max(300,min(1100,saved.height))))}
        }
        if let point=UserDefaults.standard.string(forKey:"captionOrigin"){panel.setFrameOrigin(NSPointFromString(point))}
        else{panel.setFrameOrigin(NSPoint(x:screen.midX-panel.frame.width/2,y:screen.minY+72))};clampPanel()
    }
    private func clampPanel(){
        let frame=panel.frame
        let screen=NSScreen.screens.first{$0.visibleFrame.intersects(frame)}?.visibleFrame ?? NSScreen.main!.visibleFrame
        var adjusted=frame;adjusted.size.width=min(frame.width,screen.width);adjusted.size.height=min(frame.height,screen.height)
        adjusted.origin.x=max(screen.minX,min(frame.minX,screen.maxX-adjusted.width))
        adjusted.origin.y=max(screen.minY,min(frame.minY,screen.maxY-adjusted.height));panel.setFrame(adjusted,display:true)
    }
    @objc private func screenChanged(){clampPanel()}
    func windowDidMove(_ notification:Notification){
        UserDefaults.standard.set(NSStringFromPoint(panel.frame.origin),forKey:"captionOrigin")
        TestDiagnostics.record("position",["frame":NSStringFromRect(panel.frame),"locked":model.locked])
    }
    func windowDidResize(_ notification:Notification){UserDefaults.standard.set(NSStringFromSize(panel.frame.size),forKey:"captionSize")}
    private func runVisualReview() async {
        // A labelled style preview only: no Keychain read, microphone, capture or API calls.
        if let window=popover.contentViewController?.view.window{TestDiagnostics.snapshot(window,"menu-panel")}
        model.showingSettings=true
        try? await Task.sleep(for:.milliseconds(250))
        if let window=popover.contentViewController?.view.window{TestDiagnostics.snapshot(window,"menu-settings")}
        model.showingSettings=false
        let savedStyle=model.captionStyle,savedOpacity=model.backgroundOpacity,savedSource=model.showSource,savedFont=model.fontSize
        let savedFrame=panel.frame
        model.previewCaption();resetPanel();popover.performClose(nil)
        panel.setContentSize(NSSize(width:720,height:340));model.fontSize=24;model.showSource=false
        for style in CaptionStyle.allCases {
            model.captionStyle=style
            for opacity in [0.45,0.80,1.0] {
                model.backgroundOpacity=opacity
                try? await Task.sleep(for:.milliseconds(250))
                TestDiagnostics.snapshot(panel,"\(style.rawValue)-\(Int(opacity*100))")
            }
        }
        model.captionStyle = .dark;model.backgroundOpacity=0.85;model.fontSize=30;model.showSource=true
        panel.setContentSize(NSSize(width:400,height:300))
        try? await Task.sleep(for:.milliseconds(250))
        TestDiagnostics.snapshot(panel,"narrow-bilingual")
        model.captionStyle=savedStyle;model.backgroundOpacity=savedOpacity;model.showSource=savedSource;model.fontSize=savedFont
        panel.setContentSize(NSSize(width:720,height:340));resetPanel()
        // Keep pointer-driven review on the primary display; normal placement is unchanged.
        if let screen=NSScreen.screens.first?.visibleFrame{panel.setFrameOrigin(NSPoint(x:screen.midX-300,y:screen.minY+100))}
        panel.setFrame(savedFrame,display:true)
        TestDiagnostics.update(["stage":"visual-ready","captionStyle":model.captionStyle.rawValue,"backgroundOpacity":model.backgroundOpacity,"visible":panel.isVisible])
        showPopover()
    }
    private func runMeetingTest() async {
        guard let directory=TestDiagnostics.directory else{return}
        TestDiagnostics.update(["stage":"credential-wait"])
        for _ in 0..<300{if !model.access.working{break};try? await Task.sleep(for:.milliseconds(200))}
        guard model.configured else{TestDiagnostics.update(["stage":"failed","error":"Credentials unavailable"]);return}
        let oldMic=model.microphoneEnabled
        let oldSource=model.source,savedFrame=panel.frame
        model.source = .chrome
        model.microphoneEnabled=CommandLine.arguments.contains("--with-microphone")
        TestDiagnostics.update(["stage":"armed"])
        for _ in 0..<1800{
            if FileManager.default.fileExists(atPath:directory.appendingPathComponent("start").path){break}
            try? await Task.sleep(for:.milliseconds(200))
        }
        guard FileManager.default.fileExists(atPath:directory.appendingPathComponent("start").path) else{
            model.microphoneEnabled=oldMic;model.source=oldSource
            TestDiagnostics.update(["stage":"cancelled","error":"No start marker; no capture was started"]);return
        }
        resetPanel();model.start()
        guard await waitForLive() else{return}
        TestDiagnostics.update(["stage":"listening","startedUptime":ProcessInfo.processInfo.systemUptime])
        let started=Date();var minute = -1;var injected=false;var lastShown=""
        while Date().timeIntervalSince(started)<900 {
            if model.phase != .live && model.phase != .connecting{break}
            let elapsed=Date().timeIntervalSince(started)
            if let item=model.displayCurrent {
                let key=item.id.uuidString+item.source+item.translation
                if key != lastShown{lastShown=key;TestDiagnostics.record("caption-visible",["origin":item.audioOrigin.rawValue,"source":item.source,"text":item.translation,"preview":item.provisional == true])}
            }
            if CommandLine.arguments.contains("--recovery-test"){
                if elapsed>30{break}
                if elapsed>7 && !injected{injected=true;await model.injectTransientFailureForTest()}
            }
            TestDiagnostics.update(["elapsed":elapsed,"sentFrames":model.sentFrames,"segments":model.captions.segments.count,"microphoneReady":model.microphoneReady,"microphoneNotice":model.microphoneNotice,"micLevel":model.microphoneLevel,"systemLevel":model.level])
            if Int(elapsed/60)>minute{minute=Int(elapsed/60);TestDiagnostics.snapshot(panel,"minute-\(minute)")}
            if FileManager.default.fileExists(atPath:directory.appendingPathComponent("finish").path){break}
            if FileManager.default.fileExists(atPath:directory.appendingPathComponent("microphone-on").path),!model.microphoneEnabled{model.setMicrophone(true)}
            try? await Task.sleep(for:.seconds(1))
        }
        try? await Task.sleep(for:.seconds(5))
        TestDiagnostics.snapshot(panel,"final-caption")
        await model.stop(paused:true)
        TestDiagnostics.update(["paused":model.phase == .paused,"pauseResourcesReleased":model.resourcesReleased])
        await model.stop()
        model.microphoneEnabled=oldMic
        model.source=oldSource;UserDefaults.standard.set(oldSource.id,forKey:"sourceID")
        panel.setFrame(savedFrame,display:true)
        UserDefaults.standard.set(NSStringFromPoint(savedFrame.origin),forKey:"captionOrigin")
        UserDefaults.standard.set(NSStringFromSize(savedFrame.size),forKey:"captionSize")
        TestDiagnostics.update(["stage":"completed","elapsed":Date().timeIntervalSince(started),"resourcesReleased":model.resourcesReleased,"segments":model.captions.segments.count,"microphoneReady":model.microphoneReady,"microphoneSegments":model.captions.segments.filter{$0.audioOrigin == .microphone}.count])
        showPopover()
        try? await Task.sleep(for:.milliseconds(250))
        if let window=popover.contentViewController?.view.window{TestDiagnostics.snapshot(window,"menu-panel")}
    }
    private func runSelfTest() async {
        TestDiagnostics.update(["stage":"credential-wait"])
        for _ in 0..<900{
            if !model.access.working{break}
            try? await Task.sleep(for:.milliseconds(200))
        }
        guard model.configured else{TestDiagnostics.update(["stage":"failed","error":"Credentials unavailable"]);return}
        TestDiagnostics.update(["stage":"starting","configured":model.configured,"credentialMode":model.credentials.legacy ? "App ID / Token":"API Key"])
        model.source = CommandLine.arguments.contains("--chrome-test") ? .chrome:.system
        resetPanel()
        model.start()
        guard await waitForLive() else{return}
        TestDiagnostics.snapshot(panel,"01-listening")
        TestDiagnostics.update(["stage":"listening"])
        await collectSample(marker:"first-finished",prefix:"02")
        guard model.phase == .live else{return}
        TestDiagnostics.update(["firstSentFrames":model.sentFrames,"firstEvents":model.receivedEvents,"firstTranslation":model.captions.translation])
        await model.stop(paused:true)
        TestDiagnostics.snapshot(panel,"03-paused")
        TestDiagnostics.update(["paused":model.phase == .paused,"pauseResourcesReleased":model.resourcesReleased])
        model.start()
        guard await waitForLive() else{return}
        model.toggleCaption()
        TestDiagnostics.update(["hideKeepsLive":model.phase == .live && !panel.isVisible])
        model.toggleCaption()
        TestDiagnostics.update(["showRestoresPanel":panel.isVisible,"stage":"resumed"])
        await collectSample(marker:"second-finished",prefix:"04")
        guard model.phase == .live else{return}
        TestDiagnostics.update(["secondSentFrames":model.sentFrames,"secondEvents":model.receivedEvents,"secondTranslation":model.captions.translation])
        model.toggleCaption();model.resetCaption()
        TestDiagnostics.update(["resetRestoresVisibility":model.visible && panel.isVisible])
        let originalFrame=panel.frame,originalFont=model.fontSize,originalSource=model.showSource
        panel.setContentSize(NSSize(width:400,height:300));model.fontSize=30;model.showSource=true
        try? await Task.sleep(for:.milliseconds(300))
        TestDiagnostics.snapshot(panel,"05-narrow-large-bilingual")
        panel.setFrame(originalFrame,display:true);model.fontSize=originalFont;model.showSource=originalSource
        async let pausing:Void=model.stop(paused:true)
        try? await Task.sleep(for:.milliseconds(20))
        let quitFlush=await model.finishForQuit()
        await pausing
        TestDiagnostics.update(["concurrentPauseAndQuitFlush":quitFlush && model.phase == .idle && !model.hasMeeting])
        TestDiagnostics.update(["stopped":model.phase == .idle,"stopResourcesReleased":model.resourcesReleased,"panelHiddenAfterStop":!panel.isVisible,"archiveContainsBothRuns":model.captions.segments.filter{$0.translationFinal}.count>=8,"archiveExists":model.archiveURL.map{FileManager.default.fileExists(atPath:$0.path)} ?? false])
        model.start()
        try? await Task.sleep(for:.milliseconds(50))
        await model.stop()
        try? await Task.sleep(for:.milliseconds(500))
        TestDiagnostics.update(["cancelResourcesReleased":model.resourcesReleased,"cancelled":model.phase == .idle,"stage":"completed"])
        showPopover()
    }
    private func waitForLive() async->Bool{
        for _ in 0..<150{
            if model.phase == .live{return true}
            if model.phase == .failed{TestDiagnostics.update(["stage":"failed","error":model.notice]);showPopover();return false}
            try? await Task.sleep(for:.milliseconds(200))
        }
        TestDiagnostics.update(["stage":"timeout","error":model.notice]);await model.stop();return false
    }
    private func collectSample(marker:String,prefix:String) async {
        guard let directory=TestDiagnostics.directory else{return}
        var snapshotCount=0;var last="";var markerSeen:Date?
        for _ in 0..<225{
            if model.phase != .live{TestDiagnostics.update(["stage":"failed","error":model.notice]);return}
            if model.captions.isFinal,!model.captions.translation.isEmpty,model.captions.translation != last{
                last=model.captions.translation;snapshotCount+=1
                TestDiagnostics.snapshot(panel,"\(prefix)-sentence-\(snapshotCount)")
            }
            if markerSeen==nil,FileManager.default.fileExists(atPath:directory.appendingPathComponent(marker).path){markerSeen=Date()}
            if let markerSeen,Date().timeIntervalSince(markerSeen)>6{break}
            try? await Task.sleep(for:.milliseconds(200))
        }
        guard markerSeen != nil,snapshotCount>0,model.sentFrames>0 else{
            TestDiagnostics.update(["stage":"failed","error":"Fixture did not complete or produced no final translation"])
            await model.stop();return
        }
        TestDiagnostics.snapshot(panel,"\(prefix)-final")
    }
    func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply {
        guard !terminating else{return .terminateNow};terminating=true
        Task{let saved=await model.finishForQuit();if !saved{terminating=false;showPopover()};NSApp.reply(toApplicationShouldTerminate:saved)};return .terminateLater
    }
}
