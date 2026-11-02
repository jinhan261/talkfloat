import AppKit
import SwiftUI
import Combine
import SayloriCore

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
        DispatchQueue.main.asyncAfter(deadline:.now()+0.5){[self] in
            self.showPopover()
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
    func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply {
        guard !terminating else{return .terminateNow};terminating=true
        Task{let saved=await model.finishForQuit();if !saved{terminating=false;showPopover()};NSApp.reply(toApplicationShouldTerminate:saved)};return .terminateLater
    }
}
