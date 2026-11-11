import AppKit
import Combine
import Sparkle

/// Sparkle owns signature validation and installation. The app owns when it is
/// safe to interrupt the user; a paused meeting still counts as unfinished work.
@MainActor final class AppUpdater:NSObject,ObservableObject,SPUUpdaterDelegate,@preconcurrency SPUStandardUserDriverDelegate {
    @Published private(set) var message="可手动检查新版本"
    @Published private(set) var availableVersion:String?{didSet{model.updateAvailable=availableVersion != nil}}
    @Published private(set) var checking=false
    @Published private(set) var installing=false{didSet{model.updateInstallationInProgress=installing}}
    @Published var automaticallyChecks=UserDefaults.standard.bool(forKey:"checkUpdatesAutomatically") {
        didSet{UserDefaults.standard.set(automaticallyChecks,forKey:"checkUpdatesAutomatically");schedule()}
    }
    private var controller:SPUStandardUpdaterController?
    private var timer:Task<Void,Never>?
    private var observation:AnyCancellable?
    private var pendingInstall:(()->Void)?
    private let model:SessionModel
    private let enabled:Bool
    init(model:SessionModel,enabled:Bool=true){
        self.model=model;self.enabled=enabled
        super.init()
        guard enabled else{return}
        controller=SPUStandardUpdaterController(startingUpdater:false,updaterDelegate:self,userDriverDelegate:self)
        controller?.updater.automaticallyChecksForUpdates=false
        controller?.updater.automaticallyDownloadsUpdates=false
        controller?.updater.sendsSystemProfile=false
        do{try controller?.updater.start()}catch{message="更新服务未能启动，请从 GitHub 下载。"}
        observation=model.objectWillChange.sink{[weak self] in
            // Published emits before the new value is assigned.
            Task{@MainActor in self?.resumeDeferredInstall()}
        }
        schedule()
    }
    var mayCheck:Bool{enabled && model.safeToUpdate && !checking && !installing}
    func check(){
        guard enabled else{return}
        guard model.safeToUpdate else{message="结束并保存当前会话后即可更新。";return}
        if let install=pendingInstall{pendingInstall=nil;installing=true;install();return}
        checking=true;message="正在检查更新…"
        controller?.checkForUpdates(nil)
    }
    private func schedule(){
        timer?.cancel();timer=nil
        guard enabled,automaticallyChecks else{return}
        timer=Task{[weak self] in
            do{
                try await Task.sleep(for:.seconds(60))
                while !Task.isCancelled{
                    guard let self else{return}
                    if model.safeToUpdate,!checking,!installing,controller?.updater.sessionInProgress == false{
                        controller?.updater.checkForUpdatesInBackground()
                    }
                    try await Task.sleep(for:.seconds(6*60*60))
                }
            }catch{}
        }
    }
    private func resumeDeferredInstall(){
        guard pendingInstall != nil,model.safeToUpdate else{return}
        // Do not restart automatically when a meeting ends. The user explicitly
        // resumes from Check for Updates / About after their record is saved.
        message="更新已准备好，点击检查更新以安装并重启。"
    }
    func updater(_ updater:SPUUpdater,mayPerform updateCheck:SPUUpdateCheck)throws{
        guard model.safeToUpdate else{
            throw NSError(domain:"TalkFloat.Update",code:1,userInfo:[NSLocalizedDescriptionKey:"请先结束并保存当前会话，再检查更新。"])
        }
    }
    func updater(_ updater:SPUUpdater,shouldPostponeRelaunchForUpdate item:SUAppcastItem,untilInvokingBlock installHandler:@escaping ()->Void)->Bool{
        if !model.safeToUpdate{
            pendingInstall=installHandler;installing=false;message="更新已准备好，等待当前会话保存。";return true
        }
        installing=true;return false
    }
    func updaterShouldRelaunchApplication(_ updater:SPUUpdater)->Bool{model.safeToUpdate}
    func updater(_ updater:SPUUpdater,didFindValidUpdate item:SUAppcastItem){availableVersion=item.displayVersionString;message="有新版本 \(item.displayVersionString)"}
    func updaterDidNotFindUpdate(_ updater:SPUUpdater){availableVersion=nil;message="已是当前更新通道的最新版本";checking=false}
    func updater(_ updater:SPUUpdater,didAbortWithError error:Error){
        checking=false;installing=false
        if (error as NSError).code != SUError.noUpdateError.rawValue{message="检查或安装未完成，请重试。也可从 GitHub 下载。"}
    }
    func updater(_ updater:SPUUpdater,didFinishUpdateCycleFor updateCheck:SPUUpdateCheck,error:Error?){checking=false}
    var supportsGentleScheduledUpdateReminders:Bool{true}
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update:SUAppcastItem,andInImmediateFocus immediateFocus:Bool)->Bool{false}
    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate:Bool,forUpdate update:SUAppcastItem,state:SPUUserUpdateState){
        availableVersion=update.displayVersionString;message="有新版本 \(update.displayVersionString)，可在空闲时安装。";checking=false
    }
    func standardUserDriverWillFinishUpdateSession(){checking=false;installing=false}
    func shutdown(){timer?.cancel()}
    func resumeAfterCancelledQuit(){schedule()}
}
