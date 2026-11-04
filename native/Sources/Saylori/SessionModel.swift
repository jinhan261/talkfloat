import AppKit
import SwiftUI
import SayloriCore
import Combine

@MainActor final class SessionModel: ObservableObject {
    enum Phase: String {case idle="准备好了",checking="正在检测声音",connecting="正在连接",live="正在翻译",paused="已暂停",stopping="正在收尾",failed="翻译已停止"}
    @Published var phase:Phase = .idle {didSet{TestDiagnostics.update(["phase":phase.rawValue]);TestDiagnostics.record("phase",["value":phase.rawValue])}}
    @Published var mode=TranslationMode(rawValue:UserDefaults.standard.string(forKey:"translationMode") ?? "local") ?? .local {
        didSet{savePreference(mode.rawValue,forKey:"translationMode")}
    }
    var canStart:Bool{!mode.requiresCredentials || configured}
    func setMode(_ value:TranslationMode){guard !active,!hasMeeting else{return};mode=value;notice="";localModelNotice=""}
    @Published var source=AudioSource.system {didSet{savePreference(source.id,forKey:"sourceID")}}
    @Published var sources:[AudioSource]=[.system,.chrome]
    @Published var captions=CaptionState()
    @Published var previewDrafts:[CaptionSegment]=[]
    @Published var localModelsReady=false
    @Published var preparingLocalModels=false
    @Published var localModelNotice=""
    private let previewGate=PreviewAudioGate()
    private let echoCanceller=ReferenceEchoCanceller()
    private var streamClocks:[String:Date]=[:]
    private var fastSystem:AnyObject?
    private var fastMicrophone:AnyObject?
    private var localTranslations:[UUID:CaptionSegment]=[:]
    var displayCaptions:[CaptionSegment]{
        let recent=captions.recentSegments(limit:64)
        let readable=mode == .local ? recent.map{CaptionPresentation.keepingReadableTranslation($0,previous:localTranslations[$0.id])}:recent
        return CaptionPresentation.live(cloud:readable,drafts:previewDrafts)
    }
    var displayCurrent:CaptionSegment?{displayCaptions.last}
    var displayContext:[CaptionSegment]{Array(displayCaptions.dropLast().suffix(24))}
    @Published var notice=""
    @Published var level:Float=0
    let access=CredentialSession()
    var configured:Bool{access.credentials.isValid}
    @Published var connectionChecking=false
    @Published var connectionResult=""
    private var credentialSubscription:AnyCancellable?
    @Published var previewing=false
    @Published var visible=true
    @Published var locked=false
    @Published var showingSettings=false
    @Published var captionStyle=CaptionStyle(rawValue:UserDefaults.standard.string(forKey:"captionStyle") ?? "glass") ?? .glass {
        didSet{savePreference(captionStyle.rawValue,forKey:"captionStyle");TestDiagnostics.update(["captionStyle":captionStyle.rawValue])}
    }
    @Published var backgroundOpacity=UserDefaults.standard.object(forKey:"backgroundOpacity") == nil ? 0.80:max(0.40,min(1,UserDefaults.standard.double(forKey:"backgroundOpacity"))) {
        didSet{savePreference(backgroundOpacity,forKey:"backgroundOpacity");TestDiagnostics.update(["backgroundOpacity":backgroundOpacity])}
    }
    @Published var showSource=UserDefaults.standard.object(forKey:"showSource") == nil ? true:UserDefaults.standard.bool(forKey:"showSource") {didSet{savePreference(showSource,forKey:"showSource")}}
    @Published var fontSize=UserDefaults.standard.double(forKey:"fontSize")==0 ? 30:UserDefaults.standard.double(forKey:"fontSize") {didSet{savePreference(fontSize,forKey:"fontSize")}}
    var onPreview:(()->Void)?;var onSettings:(()->Void)?;var onFailure:(()->Void)?; var onResetCaption:(()->Void)?; var onLive:(()->Void)?; var onVisibility:((Bool)->Void)?;var onLock:((Bool)->Void)?
    var credentials:Credentials{access.credentials}
    @Published var microphoneEnabled=UserDefaults.standard.bool(forKey:"microphoneEnabled") {
        didSet{savePreference(microphoneEnabled,forKey:"microphoneEnabled")}
    }
    @Published var microphoneReady=false
    @Published var microphoneNearField=UserDefaults.standard.object(forKey:"microphoneNearField") == nil ? true:UserDefaults.standard.bool(forKey:"microphoneNearField") {
        didSet{savePreference(microphoneNearField,forKey:"microphoneNearField");microphone?.nearSpeechGate.setEnabled(microphoneNearField)}
    }
    @Published var microphoneBusy=false
    @Published var microphoneThresholdDB=NearSpeechGate.boundedThreshold(UserDefaults.standard.object(forKey:"microphoneThresholdDB") as? Double ?? NearSpeechGate.defaultThresholdDB) {
        didSet{savePreference(microphoneThresholdDB,forKey:"microphoneThresholdDB");microphone?.nearSpeechGate.setThresholdDB(microphoneThresholdDB)}
    }
    @Published var microphoneRMSDB = -120.0
    @Published var microphonePassing=false
    var microphoneGateLabel:String {
        guard microphoneReady else{return "开始后显示实时音量"}
        if !microphoneNearField{return "过滤已关闭"}
        if microphonePassing{return microphoneRMSDB>=microphoneThresholdDB ? "正在通过":"保留起止"}
        return microphoneRMSDB>=microphoneThresholdDB ? "已过滤短促声":"低于门限 · 已过滤"
    }
    @Published var microphoneLevel:Float=0
    @Published var microphoneDevice=MicrophoneAudio.deviceName
    @Published var microphoneNotice=""
    @Published var microphoneProcessingMode:Int?
    var microphoneIsolationActive:Bool{microphoneReady && microphoneProcessingMode==2}
    var microphoneProcessingLabel:String {
        guard microphoneReady else{return "开始后可开启语音突显"}
        return microphoneProcessingMode==2 ? "语音突显已生效":(microphoneProcessingMode==1 ? "宽谱模式 · 会收录环境声":"语音突显未开启")
    }
    func showMicrophoneModes(){guard microphoneReady else{return};MicrophoneAudio.showMicrophoneModes()}
    private var microphone:MicrophoneRoute?
    private var microphoneGeneration=UUID()
    private var reconnects=0
    private var capture:SystemAudio?
    private var client:(any TranslationEngine)?
    private var sender:Task<Void,Error>?
    private var receiver:Task<Void,Never>?
    private var operation:Task<Void,Never>?
    private var generation=UUID()
    private var stoppingOperation:(id:UUID,task:Task<Void,Never>)?
    @Published var archiveURL:URL?
    @Published var archiveError=""
    @Published private(set) var hasMeeting=false
    let archiveStore=TranscriptStore()
    @Published private(set) var archiveDirectory=TranscriptStore.defaultDirectory
    @Published private(set) var archiveLocationError=""
    @Published private(set) var changingArchiveDirectory=false
    private var archiveScopedURL:URL?
    var canChangeArchiveDirectory:Bool{!active && (meeting==nil || meeting?.endedAt != nil)}
    private var meeting:MeetingRecord?
    private var saveTask:Task<Void,Never>?
    private var recovery:Task<Void,Never>?
    private var sleepObserver:NSObjectProtocol?
    private(set) var sentFrames=0
    private(set) var receivedEvents=0
    var resourcesReleased:Bool{capture==nil && client==nil && sender==nil && receiver==nil && microphone==nil}
    private let reviewOnly:Bool
    init(reviewOnly:Bool=false){
        self.reviewOnly=reviewOnly
        if reviewOnly{return}
        if let data=UserDefaults.standard.data(forKey:"archiveDirectoryBookmark") {
            do {
                var stale=false
                let url=try URL(resolvingBookmarkData:data,options:[.withSecurityScope,.withoutUI],relativeTo:nil,bookmarkDataIsStale:&stale)
                if url.startAccessingSecurityScopedResource(){archiveScopedURL=url}
                archiveDirectory=url
                if stale{savePreference(try url.bookmarkData(options:.withSecurityScope,includingResourceValuesForKeys:nil,relativeTo:nil),forKey:"archiveDirectoryBookmark")}
            }catch{archiveLocationError="存储位置不可用，请在设置 → 会议记录中重新选择文件夹。"}
        }
        if #available(macOS 26.4,*){Task{localModelsReady=await FastPreview.available()}}
        credentialSubscription=access.objectWillChange.sink{[weak self] in self?.objectWillChange.send()}
        if !CommandLine.arguments.contains("--ui-review"){Task{await access.load()}}
        if !UserDefaults.standard.bool(forKey:"continuityLayoutV1") {
            fontSize=30;showSource=true;savePreference(true,forKey:"continuityLayoutV1")
            UserDefaults.standard.removeObject(forKey:"captionSize")
        }
        source=sources.first(where:{$0.id==UserDefaults.standard.string(forKey:"sourceID")}) ?? .system
        refreshSources()
        recovery=Task{[weak self] in
            guard let self else{return}
            if archiveDirectory != TranscriptStore.defaultDirectory {
                do{try await archiveStore.changeDirectory(to:archiveDirectory)}
                catch{archiveLocationError="无法写入记录文件夹，请重新选择位置。"}
            }
            do{try await archiveStore.recoverInterrupted(legacyDirectory:TranscriptStore.defaultDirectory)}catch{archiveError="恢复记录失败，原始文字仍在本机保留："+error.localizedDescription}
        }
        sleepObserver=NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.willSleepNotification,object:nil,queue:.main){[weak self]_ in Task{@MainActor in await self?.stop(paused:true)}}
    }
    private func savePreference(_ value:Any?,forKey key:String){
        if !reviewOnly{UserDefaults.standard.set(value,forKey:key)}
    }
    var busy:Bool{phase == .checking || phase == .connecting || phase == .stopping || connectionChecking || changingArchiveDirectory}
    var active:Bool{phase == .live || busy}
    func refreshSources(){
        sources=[.system,.chrome]
        if !microphoneReady && !microphoneBusy{microphoneDevice=MicrophoneAudio.deviceName}
    }
    func applyCredentials(remember:Bool)async{
        guard !active else{return}
        let value=access.draft.trimmed
        guard value.isValid else{return}
        connectionChecking=true;connectionResult="正在检查连接…"
        defer{connectionChecking=false}
        access.useForSession(value)
        if remember{await access.persist(value)}
        connectionResult=await testConnection()
    }
    func start(){
        guard !active else{return}
        guard meeting?.endedAt == nil else{notice="请先重试保存上一次记录";return}
        guard archiveLocationError.isEmpty else{notice=archiveLocationError;return}
        guard canStart else{notice="请在设置中连接豆包同传";return}
        if mode == .local {
            guard #available(macOS 26.4,*) else{notice="本地模型模式需要 macOS 26.4 或更新版本；可手动切换豆包。";return}
            if !localModelsReady{notice="请先准备本地英语与中文模型";return}
        }
        previewing=false
        if meeting==nil { reconnects=0;streamClocks=[:];meeting=MeetingRecord(sourceName:source.name + "；麦克风按片段标注");meeting?.engine=mode;hasMeeting=true;captions=CaptionState();previewDrafts=[];localTranslations=[:];archiveError="";archiveURL=nil }
        savePreference(source.id,forKey:"sourceID")
        let token=UUID();generation=token;notice="";phase = .connecting;level=0;sentFrames=0;receivedEvents=0
        operation=Task{[weak self] in await self?.connect(token)}
    }
    private func makeEngine(origin:AudioOrigin)throws->any TranslationEngine {
        if mode == .doubao{return DoubaoEngine()}
        if #available(macOS 26.4,*){return AppleTranslationEngine(origin:origin)}
        throw SayError.message("本地模型模式需要 macOS 26.4 或更新版本；可手动切换豆包。")
    }
    private func connect(_ token:UUID) async {
        let audio=SystemAudio();capture=audio
        do{
            await recovery?.value
            guard token==generation,!Task.isCancelled else{return}
            guard archiveLocationError.isEmpty else{throw SayError.message(archiveLocationError)}
            let service=try makeEngine(origin:.system);client=service;captions.beginStream(service.sessionID)
            let preview=await makeFastPreview(sessionID:service.sessionID,origin:.system)
            guard token==generation,!Task.isCancelled else{if #available(macOS 26.4,*),let preview=preview as? FastPreview{await preview.stop()};return}
            fastSystem=preview
            audio.onLevel={[weak self] value in Task{@MainActor in guard self?.generation==token else{return};self?.level=value}}
            TestDiagnostics.record("capture-start",["source":source.id,"credentialMode":credentials.legacy ? "App ID / Token":"API Key","configured":configured])
            let selectedSource=source
            try await audio.start(source:selectedSource)
            TestDiagnostics.record("capture-started")
            guard token==generation,!Task.isCancelled else{audio.stop();return}
            // One stream throughout. Pre-authentication frames are discarded, never replayed.
            let relay=AudioRelay(service:service)
            let previewGate=self.previewGate
            let echoCanceller=self.echoCanceller
            sender=Task.detached{[weak self] in
                for try await frame in audio.frames {
                    try Task.checkCancellation()
                    if let stats=try await relay.forward(frame) {
                        previewGate.observeSystem(frame.data,now:stats.streamStartedUptime+stats.audioEndMS/1000)
                        echoCanceller.observeSystem(frame.data,end:stats.streamStartedUptime+stats.audioEndMS/1000)
                        if #available(macOS 26.4,*),let preview=preview as? FastPreview{preview.feed(frame.data)}
                        await self?.frameSent(stats,token:token)
                    }
                }
            }
            TestDiagnostics.record("connection-start")
            try await service.start(credentials)
            TestDiagnostics.record("connection-ready",["session":service.sessionID,"origin":"system","engine":mode.rawValue])
            guard token==generation,!Task.isCancelled else{audio.stop();await service.abort();return}
            await relay.enable()
            if var interruptions=meeting?.interruptions,let i=interruptions.lastIndex(where:{$0.origin == .system && $0.endedAt==nil}){
                interruptions[i].endedAt=Date();meeting?.interruptions=interruptions
                notice="已恢复翻译；连接中断已标在会议记录中。"
            }
            phase = .live;visible=true;onVisibility?(true);onLive?();if microphoneEnabled{beginMicrophone(token)}
            receiver=Task{[weak self] in
                do{for try await update in service.updates{
                    guard let self,self.generation==token else{return}
                    self.consume(update,sessionID:service.sessionID,origin:.system)
                }}catch{await self?.failed(error,token:token)}
            }
            let currentSender=sender
            do{try await currentSender?.value}catch{await failed(error,token:token)}
        }catch{await failed(error,token:token)}
    }
    private func failed(_ error:Error,token:UUID) async {
        guard generation==token,phase != .stopping else{return}
        let recoverable=mode == .doubao && SayError.canRetry(error) && reconnects<2
        generation=UUID();capture?.stop();capture=nil;sender?.cancel();receiver?.cancel();sender=nil;receiver=nil
        if #available(macOS 26.4,*),let preview=fastSystem as? FastPreview{await preview.stop()};fastSystem=nil
        previewDrafts.removeAll{$0.audioOrigin == .system}
        if let client{await client.abort()};client=nil;level=0
        var interruptions=meeting?.interruptions ?? []
        interruptions.append(MeetingInterruption(origin:.system,reason:error.localizedDescription));meeting?.interruptions=interruptions
        TestDiagnostics.record("failure",["message":error.localizedDescription,"recoverable":recoverable])
        if recoverable {
            reconnects+=1;phase = .connecting
            notice="系统声音连接中断，正在重连（\(reconnects)/2）。中断会标在记录中。"
            await saveRecord()
            let next=UUID();generation=next
            operation=Task{[weak self] in
                do{try await Task.sleep(for:.seconds(1))}catch{return}
                guard let self,self.generation==next else{return}
                await self.connect(next)
            }
        }else{
            await stopMicrophone();phase = .failed;notice=error.localizedDescription
            await saveRecord(ending:"连接中断")
            TestDiagnostics.update(["error":notice]);onFailure?()
        }
    }
    func stop(paused:Bool=false) async {
        // Quit or End during a pending Pause must wait for its server tail and archive.
        if let pending=stoppingOperation {
            await pending.task.value
            if stoppingOperation?.id==pending.id{stoppingOperation=nil}
            if !paused && phase == .paused{await stop(paused:false)}
            return
        }
        let id=UUID()
        let task=Task{await self.performStop(paused:paused)}
        stoppingOperation=(id,task)
        await task.value
        if stoppingOperation?.id==id{stoppingOperation=nil}
    }
    private func performStop(paused:Bool) async {
        if phase == .paused { if !paused { await saveRecord(ending:"已结束");phase = .idle;visible=false;onVisibility?(false) };return }
        guard phase == .live || phase == .connecting || phase == .checking else{return}
        let wasConnecting=phase == .connecting
        let micStop=Task{await self.stopMicrophone()}
        phase = .stopping;operation?.cancel();capture?.stop();capture=nil
        if wasConnecting {generation=UUID();sender?.cancel();if let client{await client.abort()}}
        // Give the short queued tail a bounded chance to send, then finalize the server session.
        let service=client
        let timeout=Task{try? await Task.sleep(for:.seconds(2));if !Task.isCancelled{await service?.abort()}}
        _ = try? await sender?.value;timeout.cancel()
        if let service {let ok=await service.finish();if !ok{notice="已停止收听；最后一句可能尚未定稿。"}}
        await receiver?.value
        if #available(macOS 26.4,*),let preview=fastSystem as? FastPreview{await preview.stop()};fastSystem=nil
        await micStop.value
        previewDrafts=[]
        generation=UUID();receiver?.cancel();sender=nil;receiver=nil;client=nil
        if paused{meeting?.pauses.append(Date())}
        await saveRecord(ending:paused ? nil:"已结束",paused:paused)
        phase=paused ? .paused:.idle;level=0
        if !paused{visible=false;onVisibility?(false)}
    }
    private func frameSent(_ stats:AudioSendStats,token:UUID){
        guard generation==token else{return};sentFrames += 1
        if let id=client?.sessionID{registerClock(stats,sessionID:id)}
        if sentFrames%125==0{TestDiagnostics.record("preview-gate",["suppressedPackets":previewGate.suppressedPackets,"playbackCorrelation":previewGate.latestCorrelation,"echoReductionDB":echoCanceller.reductionDB,"echoAlignment":echoCanceller.alignment])}
        TestDiagnostics.record("audio-send",["origin":"system","session":client?.sessionID ?? "","queueMS":stats.queueMS,"sendMS":stats.sendMS,"audioEndMS":stats.audioEndMS,"sendUptime":stats.sendUptime])
    }
    private func registerClock(_ stats:AudioSendStats,sessionID:String){
        guard streamClocks[sessionID]==nil else{return}
        let date=Date().addingTimeInterval(stats.streamStartedUptime-ProcessInfo.processInfo.systemUptime)
        streamClocks[sessionID]=date;captions.setStreamClock(sessionID,startedAt:date)
        TestDiagnostics.record("stream-clock",["session":sessionID,"epoch":date.timeIntervalSince1970])
    }
    private func weakPlaybackLeak(_ item:CaptionSegment)->Bool {
        guard item.audioOrigin == .microphone,let epoch=item.audioEpoch else{return false}
        let offset=ProcessInfo.processInfo.systemUptime-Date().timeIntervalSince1970
        let start=epoch+Double(item.startMS)/1000+offset
        let end=epoch+Double(max(item.startMS+240,item.endMS))/1000+offset
        return previewGate.isWeakPlaybackLeak(start:start,end:end)
    }
    private func playbackConfidence(_ item:CaptionSegment)->Double {
        guard item.audioOrigin == .microphone,let epoch=item.audioEpoch else{return 0}
        let offset=ProcessInfo.processInfo.systemUptime-Date().timeIntervalSince1970
        return previewGate.playbackConfidence(start:epoch+Double(item.startMS)/1000+offset,end:epoch+Double(item.endMS)/1000+offset)
    }
    func setMicrophone(_ enabled:Bool){
        guard !microphoneBusy else{return}
        microphoneEnabled=enabled;microphoneNotice=""
        if phase == .live {
            if enabled{beginMicrophone(generation)}else{Task{await self.stopMicrophone()}}
        }
    }
    private func beginMicrophone(_ token:UUID){
        guard microphone==nil else{return}
        let micToken=UUID();microphoneGeneration=micToken
        let echoCanceller=self.echoCanceller
        let service:any TranslationEngine
        do{service=try makeEngine(origin:.microphone)}catch{microphoneNotice=error.localizedDescription;return}
        let route=MicrophoneRoute(service:service,processAudio:{echoCanceller.process($0)})
        microphone=route;microphoneBusy=true;microphoneProcessingMode=nil
        route.nearSpeechGate.setEnabled(microphoneNearField)
        route.nearSpeechGate.setThresholdDB(microphoneThresholdDB)
        microphoneRMSDB = -120;microphonePassing=false
        route.onGate={[weak self] observation in
            guard let self,self.microphoneGeneration==micToken else{return}
            self.microphoneRMSDB=observation.rmsDB;self.microphonePassing=observation.isPassing
            TestDiagnostics.update(["microphoneRMSDB":observation.rmsDB,"microphoneThresholdDB":observation.thresholdDB,"microphonePassing":observation.isPassing])
        }
        captions.beginStream(route.service.sessionID,origin:.microphone)
        route.audio.onDiagnostics={values in Task{@MainActor in TestDiagnostics.record("microphone-format",values)}}
        route.audio.onProcessingMode={[weak self] mode in Task{@MainActor in
            guard let self,self.microphoneGeneration==micToken else{return}
            guard self.microphoneProcessingMode != mode else{return}
            self.microphoneProcessingMode=mode
            TestDiagnostics.record("microphone-processing",["mode":mode,"voiceIsolation":mode==2,"automaticGain":false])
            TestDiagnostics.update(["microphoneMode":mode,"voiceIsolation":mode==2])
        }}
        route.audio.onDevice={[weak self] name in Task{@MainActor in
            guard let self,self.microphoneGeneration==micToken else{return};self.microphoneDevice=name
            TestDiagnostics.record("microphone-device",["name":name])
        }}
        route.audio.onLevel={[weak self] value in Task{@MainActor in if self?.microphoneGeneration==micToken{self?.microphoneLevel=value}}}
        route.onReady={[weak self] in guard let self,self.microphoneGeneration==micToken else{return};self.microphoneBusy=false;self.microphoneReady=true}
        let microphoneSession=route.service.sessionID
        route.onSent={[weak self] stats in self?.registerClock(stats,sessionID:microphoneSession)}
        route.onUpdate={[weak self] update in
            guard let self,self.microphoneGeneration==micToken else{return}
            self.consume(update,sessionID:microphoneSession,origin:.microphone)
        }
        route.onFailure={[weak self] message in
            guard let self,self.microphoneGeneration==micToken else{return}
            var gaps=self.meeting?.interruptions ?? []
            gaps.append(MeetingInterruption(origin:.microphone,reason:message));self.meeting?.interruptions=gaps;self.scheduleSave()
            self.microphoneNotice=message;self.microphoneBusy=false;self.microphoneReady=false
            TestDiagnostics.record("microphone-failure",["message":message])
        }
        Task{
            let preview=await makeFastPreview(sessionID:microphoneSession,origin:.microphone)
            guard microphoneGeneration==micToken else{if #available(macOS 26.4,*),let preview=preview as? FastPreview{await preview.stop()};return}
            fastMicrophone=preview
            let gate=self.previewGate
            route.onAudio={data,stats in
                let filtered=gate.microphonePreview(data,now:stats.streamStartedUptime+stats.audioEndMS/1000)
                if #available(macOS 26.4,*),let preview=preview as? FastPreview{preview.feed(filtered)}
            }
            route.start(credentials)
        }
    }
    private func stopMicrophone() async {
        microphoneBusy=true
        if let route=microphone{await route.stop()}
        if #available(macOS 26.4,*),let preview=fastMicrophone as? FastPreview{await preview.stop()};fastMicrophone=nil
        previewDrafts.removeAll{$0.audioOrigin == .microphone}
        microphoneGeneration=UUID();microphone=nil;microphoneReady=false;microphoneLevel=0;microphoneBusy=false
    }
    private func consume(_ update:TranslationUpdate,sessionID:String,origin:AudioOrigin){
        receivedEvents += 1
        switch update {
        case .cloud(let event):
            TestDiagnostics.record("event",["origin":origin.rawValue,"session":sessionID,"type":event.type,"text":event.text,"status":event.status,"message":event.message,"startMS":event.start,"endMS":event.end,"receivedUptime":event.receivedAt,"displayLagMS":(ProcessInfo.processInfo.systemUptime-event.receivedAt)*1000])
            captions.apply(event,streamID:sessionID)
            if origin == .system,event.type==250{level=0}
        case .local(var item):
            item.audioEpoch=streamClocks[sessionID]?.timeIntervalSince1970
            item.weakPlaybackLeak=weakPlaybackLeak(item);item.playbackConfidence=playbackConfidence(item)
            captions.upsertLocal(item)
            if !item.translation.isEmpty,localTranslations[item.id]?.translationFinal != true || item.translationFinal {
                localTranslations[item.id]=item
                let visibleIDs=Set(captions.recentSegments(limit:64).map(\.id))
                localTranslations=localTranslations.filter{visibleIDs.contains($0.key)}
            }
            TestDiagnostics.record("caption-update",["id":item.id.uuidString,"session":sessionID,"origin":origin.rawValue,"startMS":item.startMS,"endMS":item.endMS,"source":item.source,"text":item.translation,"sourceFinal":item.sourceFinal,"translationFinal":item.translationFinal,"uptime":ProcessInfo.processInfo.systemUptime])
        }
        if origin == .microphone {
            captions.classifyMicrophone(sessionID,using:weakPlaybackLeak)
            captions.measurePlayback(sessionID,using:playbackConfidence)
        }
        tracePresentation();scheduleSave()
    }
    private func tracePresentation(){
        guard TestDiagnostics.directory != nil else{return}
        let visible=Array(displayCaptions.suffix(25))
        let mic=visible.filter{$0.audioOrigin == .microphone}.map{["source":$0.source,"preview":$0.provisional == true,"confidence":$0.playbackConfidence ?? 0] as [String:Any]}
        TestDiagnostics.record("presentation",["micCandidates":mic,"count":visible.count,"currentOrigin":visible.last?.audioOrigin.rawValue ?? "none"])
    }
    private func makeFastPreview(sessionID:String,origin:AudioOrigin) async -> AnyObject? {
        guard mode == .doubao,!CommandLine.arguments.contains("--no-cloud-preview") else{return nil}
        if #available(macOS 26.4,*){
            if !localModelsReady{localModelsReady=await FastPreview.available()}
            guard localModelsReady else{return nil}
            let preview=FastPreview(sessionID:sessionID,origin:origin)
            preview.onCaption={[weak self] item in
                guard let self else{return}
                var value=item
                value.audioEpoch=self.streamClocks[sessionID]?.timeIntervalSince1970
                value.weakPlaybackLeak=self.weakPlaybackLeak(value)
                value.playbackConfidence=self.playbackConfidence(value)
                if let i=self.previewDrafts.firstIndex(where:{$0.id==item.id}){
                    value.id=self.previewDrafts[i].id;value.receivedAt=self.previewDrafts[i].receivedAt;self.previewDrafts[i]=value
                }else{self.previewDrafts.append(value)}
                self.previewDrafts=CaptionPresentation.latestDrafts(self.previewDrafts)
                self.tracePresentation()
                if self.displayCurrent?.id==value.id {
                    TestDiagnostics.record("preview-display",["session":sessionID,"origin":origin.rawValue,"startMS":value.startMS,"endMS":value.endMS,"source":value.source,"text":value.translation,"uptime":ProcessInfo.processInfo.systemUptime])
                }
            }
            preview.onFailure={[weak self] message in self?.localModelNotice=message;TestDiagnostics.record("local-failure",["message":message,"origin":origin.rawValue])}
            do{try await preview.start();return preview}catch{localModelNotice="本机预览暂不可用；豆包翻译继续。";await preview.stop()}
        }
        return nil
    }
    func injectTransientFailureForTest() async {
        guard TestDiagnostics.directory != nil,CommandLine.arguments.contains("--recovery-test"),phase == .live else{return}
        TestDiagnostics.record("injected-transient-failure")
        await failed(SayError.service(55000001,"diagnostic recovery probe"),token:generation)
    }
    func retrySave() async {
        if meeting != nil{await saveRecord(ending:"已结束");return}
        do{try await archiveStore.recoverInterrupted();archiveError=""}
        catch{archiveError="恢复记录失败，原始文字仍在本机保留："+error.localizedDescription}
    }
    private func scheduleSave(){
        guard saveTask==nil,meeting != nil else{return}
        saveTask=Task{[weak self] in
            do{try await Task.sleep(for:.seconds(1))}catch{return}
            guard let self else{return};self.saveTask=nil
            await self.saveRecord()
        }
    }
    private func saveRecord(ending:String?=nil,paused:Bool=false) async {
        saveTask?.cancel();saveTask=nil
        guard var record=meeting else{return}
        record.revision += 1
        record.segments=captions.segments
        record.status=ending ?? (paused ? "已暂停":"进行中")
        if ending != nil {record.endedAt=Date();meeting=nil;hasMeeting=false}else{meeting=record}
        await recovery?.value
        do{
            if let url=try await archiveStore.save(record){archiveURL=url}
            archiveError=""
            if record.hasText {
                TestDiagnostics.archive(record)
                TestDiagnostics.update(["archivePath":archiveURL?.path ?? "","archiveSegments":record.segments.count,"archiveStatus":record.status])
            }
        }catch{
            // Keep the complete in-memory record so a subsequent End/Quit can retry.
            if ending != nil {meeting=record;hasMeeting=true}
            archiveError="文字尚未保存："+error.localizedDescription
        }
    }
    func finishForQuit() async -> Bool {await stop();if meeting != nil{await saveRecord(ending:"退出 App")};return meeting==nil}
    func openArchiveFolder(){
        do{
            if archiveDirectory == TranscriptStore.defaultDirectory{try FileManager.default.createDirectory(at:archiveDirectory,withIntermediateDirectories:true)}
            guard FileManager.default.fileExists(atPath:archiveDirectory.path) else{throw CocoaError(.fileNoSuchFile)}
            if !NSWorkspace.shared.open(archiveDirectory){throw CocoaError(.fileReadUnknown)}
        }catch{archiveLocationError="文件夹不可用，请在设置 → 会议记录中重新选择。";notice=archiveLocationError}
    }
    func setArchiveDirectory(_ url:URL) async {
        guard canChangeArchiveDirectory else{return}
        changingArchiveDirectory=true
        defer{changingArchiveDirectory=false}
        await recovery?.value
        let scoped=url.startAccessingSecurityScopedResource()
        do {
            let bookmark:Data?=url == TranscriptStore.defaultDirectory ? nil:try url.bookmarkData(options:.withSecurityScope,includingResourceValuesForKeys:nil,relativeTo:nil)
            if url == TranscriptStore.defaultDirectory{try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)}
            try await archiveStore.changeDirectory(to:url)
            archiveScopedURL?.stopAccessingSecurityScopedResource()
            archiveScopedURL=scoped ? url:nil
            archiveDirectory=url;archiveLocationError="";notice=""
            savePreference(bookmark,forKey:"archiveDirectoryBookmark")
            // A failed ended record may be retried into a newly selected folder.
            if meeting?.endedAt != nil{await retrySave()}
        }catch{
            if scoped{url.stopAccessingSecurityScopedResource()}
            archiveLocationError="无法使用所选文件夹："+error.localizedDescription
        }
    }
    func revealLatestArchive(){if let archiveURL{NSWorkspace.shared.activateFileViewerSelecting([archiveURL])}}
    func resetCaption(){visible=true;onResetCaption?()}
    func openSettings(){showingSettings=true;onSettings?()}
    func previewCaption(){guard !hasMeeting else{return};previewing=true;visible=true;onVisibility?(true);onPreview?()}
    func toggleCaption(){visible.toggle();onVisibility?(visible)}
    func toggleLock(){locked.toggle();onLock?(locked)}
    func testAudio() async -> String {
        guard !active && !hasMeeting else { return "请先结束当前会话" }
        let token=UUID(); generation=token; phase = .checking; level=0
        let audio=SystemAudio();capture=audio
        audio.onLevel={[weak self] value in Task{@MainActor in if self?.generation==token{self?.level=value}}}
        var bytes=0;var peak:Float=0
        do{
            let selectedSource=source
            try await Task.detached { try await audio.start(source:selectedSource) }.value
            guard token==generation else{audio.stop();return "检测已结束"}
            let deadline=Task{try? await Task.sleep(for:.seconds(8));audio.stop()}
            defer{deadline.cancel()}
            for try await frame in audio.frames{
                bytes+=frame.data.count
                frame.data.withUnsafeBytes{raw in
                    for i in stride(from:0,to:raw.count-1,by:2){
                        let sample=Int16(bitPattern:UInt16(raw[i]) | UInt16(raw[i+1])<<8)
                        peak=max(peak,abs(Float(sample)/32768))
                    }
                }
            }
            audio.stop();guard generation==token else{return "检测已结束"};capture=nil;phase = .idle;level=0
            let result=bytes>0 && peak>0.001 ? "已捕获\(source.name)，可以开始翻译。" : "未检测到声音。请播放一段英语后重试，并确认系统设置的“仅系统录音”已允许 TalkFloat；无需开启录屏。"
            if CommandLine.arguments.contains("--audio-check") {
                let report:[String:Any]=["bytes":bytes,"peak":peak,"seconds":Double(bytes)/32000,"result":result]
                if let data=try? JSONSerialization.data(withJSONObject:report,options:.prettyPrinted){try? data.write(to:URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent("saylori-audio-check.json"))}
            }
            return result
        }catch{audio.stop();guard generation==token else{return "检测已结束"};capture=nil;phase = .failed;notice=error.localizedDescription;return error.localizedDescription}
    }
    func testConnection() async ->String {
        let service=ASTClient()
        do{try await service.connect(credentials);_ = await service.finish();return "连接成功，可以开始翻译"}
        catch{return error.localizedDescription}
    }
}
