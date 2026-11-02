import AppKit
import SayloriCore

/// Explicitly launched integration/visual checks. Ordinary application launches
/// do not construct this runner or start capture through it.
@MainActor final class AppTestHarness {
    private let model:SessionModel
    private let panel:NSPanel
    private let popover:NSPopover
    private let showPopover:()->Void
    private let resetPanel:()->Void
    init(model:SessionModel,panel:NSPanel,popover:NSPopover,showPopover:@escaping ()->Void,resetPanel:@escaping ()->Void){
        self.model=model;self.panel=panel;self.popover=popover
        self.showPopover=showPopover;self.resetPanel=resetPanel
    }
    private func restore(source:AudioSource,microphone:Bool,frame:NSRect){
        model.source=source;model.microphoneEnabled=microphone
        UserDefaults.standard.set(source.id,forKey:"sourceID")
        panel.setFrame(frame,display:true)
        UserDefaults.standard.set(NSStringFromPoint(frame.origin),forKey:"captionOrigin")
        UserDefaults.standard.set(NSStringFromSize(frame.size),forKey:"captionSize")
    }
    func runVisualReview() async {
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
    private func prepareEngine() async -> Bool {
        if let i=CommandLine.arguments.firstIndex(of:"--engine"),CommandLine.arguments.count>i+1,
           let value=TranslationMode(rawValue:CommandLine.arguments[i+1]){model.setMode(value)}
        for _ in 0..<300 {
            if model.mode == .local ? model.localModelsReady:!model.access.working{break}
            try? await Task.sleep(for:.milliseconds(200))
        }
        guard model.canStart,model.mode != .local || model.localModelsReady else{
            TestDiagnostics.update(["stage":"failed","error":model.mode == .local ? "Local models unavailable":"Credentials unavailable"]);return false
        }
        TestDiagnostics.update(["engine":model.mode.rawValue]);return true
    }
    func runMeetingTest() async {
        guard let directory=TestDiagnostics.directory else{return}
        TestDiagnostics.update(["stage":"credential-wait"])
        let oldMode=model.mode;defer{model.setMode(oldMode)}
        guard await prepareEngine() else{return}
        let oldMic=model.microphoneEnabled
        let oldSource=model.source,savedFrame=panel.frame
        defer{restore(source:oldSource,microphone:oldMic,frame:savedFrame)}
        model.source = CommandLine.arguments.contains("--system-test") ? .system:.chrome
        model.microphoneEnabled=CommandLine.arguments.contains("--with-microphone")
        TestDiagnostics.update(["stage":"armed"])
        for _ in 0..<1800{
            if FileManager.default.fileExists(atPath:directory.appendingPathComponent("start").path){break}
            try? await Task.sleep(for:.milliseconds(200))
        }
        guard FileManager.default.fileExists(atPath:directory.appendingPathComponent("start").path) else{
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
        TestDiagnostics.update(["stage":"completed","elapsed":Date().timeIntervalSince(started),"resourcesReleased":model.resourcesReleased,"segments":model.captions.segments.count,"microphoneReady":model.microphoneReady,"microphoneSegments":model.captions.segments.filter{$0.audioOrigin == .microphone}.count])
        showPopover()
        try? await Task.sleep(for:.milliseconds(250))
        if let window=popover.contentViewController?.view.window{TestDiagnostics.snapshot(window,"menu-panel")}
    }
    func runSelfTest() async {
        TestDiagnostics.update(["stage":"credential-wait"])
        let oldMode=model.mode;defer{model.setMode(oldMode)}
        guard await prepareEngine() else{return}
        TestDiagnostics.update(["stage":"starting","configured":model.configured,"credentialMode":model.credentials.legacy ? "App ID / Token":"API Key"])
        let oldSource=model.source,oldMic=model.microphoneEnabled,savedFrame=panel.frame
        defer{restore(source:oldSource,microphone:oldMic,frame:savedFrame)}
        model.microphoneEnabled=CommandLine.arguments.contains("--with-microphone")
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
        TestDiagnostics.update(["stopped":model.phase == .idle,"stopResourcesReleased":model.resourcesReleased,"panelHiddenAfterStop":!panel.isVisible,"archiveContainsBothRuns":Set(model.captions.segments.filter{$0.translationFinal}.map(\.sessionID)).count>=2,"archiveExists":model.archiveURL.map{FileManager.default.fileExists(atPath:$0.path)} ?? false])
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
}
