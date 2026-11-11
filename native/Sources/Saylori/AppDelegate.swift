import AppKit
import SwiftUI
import Combine
import SayloriCore

@MainActor final class AppDelegate:NSObject,NSApplicationDelegate,NSWindowDelegate {
    let model=SessionModel()
    private var status:NSStatusItem!
    private let activityBadge=MenuBarActivityBadge(frame:.zero)
    private let popover=NSPopover()
    private var panel:NSPanel!
    private var subscriptions=Set<AnyCancellable>()
    private var terminating=false
    private var harness:Task<Void,Never>?
    private lazy var setup=SetupCoordinator(model:model)
    private lazy var updates=AppUpdater(model:model,enabled:TestDiagnostics.directory == nil && !CommandLine.arguments.contains("--ui-review"))
    private var settingsWindow:NSWindow?
    private var setupWindow:NSWindow?
    func applicationDidFinishLaunching(_ notification:Notification){
        NSApp.setActivationPolicy(.accessory)
        if CommandLine.arguments.contains("--dark-appearance"){NSApp.appearance=NSAppearance(named:.darkAqua)}
        installMainMenu()
        status=NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        status.button?.image=TalkFloatArtwork.menuImage()
        if let button=status.button {
            activityBadge.frame=button.bounds;activityBadge.autoresizingMask=[.width,.height]
            activityBadge.isHidden=true;activityBadge.setAccessibilityElement(false)
            button.addSubview(activityBadge)
        }
        status.button?.target=self;status.button?.action=#selector(togglePopover)
        status.button?.toolTip="TalkFloat · 英语实时翻译"
        // UI inspection can pin this transient surface without changing ordinary launches.
        popover.behavior = CommandLine.arguments.contains("--pin-test-popover") ? .applicationDefined:.transient
        let appearanceOverride:ColorScheme?=CommandLine.arguments.contains("--dark-appearance") ? .dark:nil
        let menuHost=NSHostingController(rootView:MenuPopoverContent(model:model,maximumHeight:max(320,(status.button?.window?.screen?.visibleFrame.height ?? 800)-80)).preferredColorScheme(appearanceOverride))
        menuHost.sizingOptions = [.preferredContentSize]
        popover.contentViewController=menuHost
        panel=SubtitlePanel(contentRect:NSRect(x:0,y:0,width:720,height:340),styleMask:[.borderless,.nonactivatingPanel,.resizable],backing:.buffered,defer:false)
        panel.title="TalkFloat 字幕";panel.level = .floating;panel.isFloatingPanel=true
        panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]
        panel.isMovableByWindowBackground=true;panel.backgroundColor = .clear;panel.isOpaque=false;panel.hasShadow=true
        panel.minSize=NSSize(width:400,height:300);panel.maxSize=NSSize(width:1600,height:1100)
        panel.hidesOnDeactivate=false;panel.delegate=self
        panel.contentView=NSHostingView(rootView:CaptionView(model:model).preferredColorScheme(appearanceOverride))
        placePanel()
        model.onSettings={[weak self] in self?.showSettings()}
        model.onSetup={[weak self] in self?.showSetup()}
        model.onCheckUpdates={[weak self] in self?.model.settingsSection = .about;self?.showSettings();self?.updates.check()}
        setup.onClose={[weak self] in self?.setupWindow?.close();self?.showPopover()}
        _ = updates
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
            self?.status.button?.contentTintColor=nil // Let macOS adapt the template in every phase.
            self?.activityBadge.isHidden=phase != .live
            self?.status.button?.toolTip="TalkFloat · \(phase.rawValue)"
            self?.status.button?.setAccessibilityValue(phase.rawValue)
            TestDiagnostics.update(["statusIconUsesSystemTint":self?.status.button?.contentTintColor == nil,"statusIconIsTemplate":self?.status.button?.image?.isTemplate == true,"statusActivityVisible":self?.activityBadge.isHidden == false])
            TestDiagnostics.record("menu-status",["phase":phase.rawValue,"badgeVisible":self?.activityBadge.isHidden == false])
        }.store(in:&subscriptions)
        model.$showSource.dropFirst().sink{[weak self]show in
            guard let self,show,self.panel.frame.height<168 else{return}
            var frame=self.panel.frame;frame.origin.y-=168-frame.height;frame.size.height=168
            self.panel.setFrame(frame,display:true);self.clampPanel()
        }.store(in:&subscriptions)
        NotificationCenter.default.addObserver(self,selector:#selector(screenChanged),name:NSApplication.didChangeScreenParametersNotification,object:nil)
        DistributedNotificationCenter.default().addObserver(self,selector:#selector(showExistingInstance),name:Notification.Name("app.saylori.show"),object:nil)
        DispatchQueue.main.asyncAfter(deadline:.now()+0.5){[self] in
            if !UserDefaults.standard.bool(forKey:"setupSeenV1"),TestDiagnostics.directory == nil,!CommandLine.arguments.contains("--audio-check"),!CommandLine.arguments.contains("--preview-caption") {
                self.showSetup()
            }else{self.showPopover()}
            if CommandLine.arguments.contains("--ui-review") || TestDiagnostics.directory != nil {
                let runner=AppTestHarness(model:self.model,panel:self.panel,popover:self.popover,
                    showPopover:{[weak self] in self?.showPopover()},resetPanel:{[weak self] in self?.resetPanel()})
                self.harness=Task{
                    if CommandLine.arguments.contains("--ui-review"){await runner.runVisualReview()}
                    else if CommandLine.arguments.contains("--meeting-test"){await runner.runMeetingTest()}
                    else{await runner.runSelfTest()}
                }
            }
            else if CommandLine.arguments.contains("--audio-check"){Task{self.model.notice=await self.model.testAudio()}}
            else if CommandLine.arguments.contains("--preview-caption"){self.model.previewCaption()}
        }
    }
    private func installMainMenu(){
        let menu=NSMenu()
        let appItem=NSMenuItem();menu.addItem(appItem)
        let appMenu=NSMenu(title:"TalkFloat");appItem.submenu=appMenu
        appMenu.addItem(withTitle:"关于 TalkFloat",action:#selector(NSApplication.orderFrontStandardAboutPanel(_:)),keyEquivalent:"")
        let settingsItem=appMenu.addItem(withTitle:"设置…",action:#selector(openSettingsWindow),keyEquivalent:",");settingsItem.target=self
        let setupItem=appMenu.addItem(withTitle:"首次设置与声音测试…",action:#selector(openSetupWindow),keyEquivalent:"");setupItem.target=self
        let updateItem=appMenu.addItem(withTitle:"检查更新…",action:#selector(checkForUpdates),keyEquivalent:"");updateItem.target=self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle:"退出 TalkFloat",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        let editItem=NSMenuItem();menu.addItem(editItem)
        let edit=NSMenu(title:"编辑");editItem.submenu=edit
        for (title,selector,key) in [("撤销","undo:","z"),("剪切","cut:","x"),("复制","copy:","c"),("粘贴","paste:","v"),("全选","selectAll:","a")]{
            edit.addItem(withTitle:title,action:NSSelectorFromString(selector),keyEquivalent:key)
        }
        NSApp.mainMenu=menu
    }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool)->Bool{showPopover();return false}
    @objc private func openSettingsWindow(){model.settingsSection = .general;showSettings()}
    @objc private func openSetupWindow(){showSetup()}
    @objc private func checkForUpdates(){model.settingsSection = .about;showSettings();updates.check()}
    private func showSettings(){
        popover.performClose(nil)
        if settingsWindow==nil{
            let window=NSWindow(contentRect:NSRect(x:0,y:0,width:640,height:560),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
            window.title="TalkFloat 设置";window.isReleasedWhenClosed=false
            window.contentView=NSHostingView(rootView:SettingsView(model:model,setup:setup,updates:updates))
            window.minSize=NSSize(width:620,height:550);window.setFrameAutosaveName("TalkFloatSettings");window.center();settingsWindow=window
        }
        settingsWindow?.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
    }
    private func showSetup(){
        guard !model.active,!model.hasMeeting,!updates.installing else{showPopover();return}
        popover.performClose(nil)
        if setupWindow==nil{
            let window=NSWindow(contentRect:NSRect(x:0,y:0,width:500,height:552),styleMask:[.titled,.closable],backing:.buffered,defer:false)
            window.title="开始使用 TalkFloat";window.isReleasedWhenClosed=false;window.delegate=self
            window.contentView=NSHostingView(rootView:SetupView(setup:setup,model:model));window.center();setupWindow=window
        }
        setupWindow?.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
    }
    func windowShouldClose(_ sender:NSWindow)->Bool{
        if sender===setupWindow,model.preparingLocalModels{return false}
        return true
    }
    func windowWillClose(_ notification:Notification){
        if notification.object as? NSWindow === setupWindow{setup.cancel();UserDefaults.standard.set(true,forKey:"setupSeenV1")}
    }
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
        guard notification.object as? NSWindow === panel else{return}
        UserDefaults.standard.set(NSStringFromPoint(panel.frame.origin),forKey:"captionOrigin")
        TestDiagnostics.record("position",["frame":NSStringFromRect(panel.frame),"locked":model.locked])
    }
    func windowDidResize(_ notification:Notification){guard notification.object as? NSWindow === panel else{return};UserDefaults.standard.set(NSStringFromSize(panel.frame.size),forKey:"captionSize")}
    func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply {
        guard !terminating else{return .terminateNow};terminating=true
        setup.cancel();updates.shutdown()
        Task{let saved=await model.finishForQuit();if !saved{terminating=false;updates.resumeAfterCancelledQuit();showPopover()};NSApp.reply(toApplicationShouldTerminate:saved)};return .terminateLater
    }
}
