import AppKit
// AppKit owns the menu-bar lifecycle; every product view is native SwiftUI.
// No WindowGroup or Settings scene is created, so launch never opens an empty window.
@main @MainActor struct TalkFloatApp {
    static func main(){
        if let index=CommandLine.arguments.firstIndex(of:"--render-design"),CommandLine.arguments.count>index+1 {
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.prohibited)
            DesignReview.render(to:URL(fileURLWithPath:CommandLine.arguments[index+1]))
            return
        }
        // A second launch must not create another menu item or Keychain request.
        if let id=Bundle.main.bundleIdentifier,
           let running=NSRunningApplication.runningApplications(withBundleIdentifier:id)
            .first(where:{$0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated}){
            running.activate(options:[])
            DistributedNotificationCenter.default().postNotificationName(Notification.Name("app.saylori.show"),object:nil)
            return
        }
        let application=NSApplication.shared
        let delegate=AppDelegate()
        application.delegate=delegate
        application.setActivationPolicy(.accessory)
        application.run()
        withExtendedLifetime(delegate){}
    }
}
