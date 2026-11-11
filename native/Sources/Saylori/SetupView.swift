import SwiftUI
import SayloriCore

struct SetupView:View {
    @ObservedObject var setup:SetupCoordinator
    @ObservedObject var model:SessionModel
    private let titles=["选择翻译方式","连接你的声音","试一下实时字幕"]
    var body:some View {
        VStack(alignment:.leading,spacing:0){
            HStack(spacing:12){
                TalkFloatMark().fill(.primary).frame(width:32,height:28)
                VStack(alignment:.leading,spacing:4){
                    Text("欢迎使用 TalkFloat").font(.system(size:21,weight:.semibold))
                    Text("听英语，看中文。字幕就在你正在用的 App 旁边。")
                        .font(.system(size:12)).foregroundStyle(.secondary)
                }
            }.padding(.bottom,26)
            if setup.runningFromReadOnlyVolume{
                Label("请先把 TalkFloat 拖入 Applications，再从那里打开。",systemImage:"externaldrive")
                    .font(.system(size:12,weight:.medium)).foregroundStyle(Brand.accent).padding(.bottom,16)
            }
            HStack(spacing:18){ForEach(0..<3){index in
                Button{setup.step=index}label:{
                    HStack(spacing:7){
                        Text("\(index+1)").font(.system(size:11,weight:.semibold)).frame(width:22,height:22)
                            .background(setup.step==index ? Brand.accent.opacity(0.12):Brand.rowFill,in:Circle())
                        Text(["模型","声音","试用"][index]).font(.system(size:12,weight:setup.step==index ? .semibold:.regular))
                    }.foregroundStyle(setup.step==index ? Brand.accent:Color.secondary)
                }.buttonStyle(.plain).disabled(setup.working || model.preparingLocalModels)
                if index<2{Image(systemName:"chevron.right").font(.system(size:9)).foregroundStyle(.tertiary)}
            }}.padding(.bottom,22)
            Divider()
            ScrollView{
                VStack(alignment:.leading,spacing:18){
                    Text(titles[setup.step]).font(.system(size:17,weight:.semibold))
                    if setup.step==0{engine}else if setup.step==1{sound}else{sample}
                }.frame(maxWidth:.infinity,alignment:.leading).padding(.vertical,22).padding(.horizontal,1)
            }.scrollIndicators(.automatic)
            Divider().padding(.bottom,16)
            HStack{
                Button("稍后设置"){setup.finish()}.buttonStyle(.plain).foregroundStyle(.secondary)
                    .disabled(setup.working || model.preparingLocalModels)
                Spacer()
                if setup.working{Button("停止测试"){setup.cancel()}}
                else if setup.step>0{Button("上一步"){setup.step-=1}.disabled(model.preparingLocalModels)}
                Button(setup.step==2 ? "完成":"继续"){
                    if setup.step<2{setup.step+=1}else{setup.finish()}
                }.buttonStyle(.borderedProminent).disabled(setup.working || model.preparingLocalModels).keyboardShortcut(.defaultAction)
            }
        }.padding(28).frame(width:500,height:552).background(Brand.surface).tint(Brand.accent)
            .modifier(LocalModelPreparation(model:model))
            .onAppear{setup.refreshMicrophone()}
            .onReceive(NotificationCenter.default.publisher(for:NSApplication.didBecomeActiveNotification)){_ in setup.refreshMicrophone()}
    }
    private var engine:some View {
        VStack(alignment:.leading,spacing:16){
            ChoiceStrip(title:"翻译模式",options:[(TranslationMode.local,"Apple 本地模型"),(.doubao,"豆包云端")],selection:Binding(get:{model.mode},set:{model.setMode($0)}))
                .disabled(model.active || model.hasMeeting || model.preparingLocalModels)
            if model.mode == .local{
                Text("英语识别与中文翻译都在这台 Mac 上完成，没有 API 费用。首次使用可能需要下载语言资源。")
                    .font(.system(size:13)).foregroundStyle(.secondary).lineSpacing(4)
                if #available(macOS 26.4,*){
                    ReadinessRow(icon:model.localModelsReady ? "checkmark.circle.fill":"arrow.down.circle",title:model.localModelsReady ? "语言资源已就绪":"准备英语与中文",detail:model.localModelsReady ? "可以离线使用":"下载由 macOS 管理，需要网络连接",ready:model.localModelsReady)
                    if !model.localModelsReady{
                        Button(model.preparingLocalModels ? "正在准备…":"准备语言资源"){setup.prepareModels()}
                            .disabled(model.preparingLocalModels || model.active)
                        if model.preparingLocalModels{Button("稍后继续下载"){setup.cancelPreparation()}.buttonStyle(.link)}
                    }
                    if !model.localModelNotice.isEmpty{Text(model.localModelNotice).font(.system(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)}
                }else{
                    Label("本地模型需要 macOS 26.4 或更新版本。你可以选择豆包云端。",systemImage:"info.circle").font(.system(size:12)).foregroundStyle(.secondary)
                }
            }else{
                Text("使用你自己的豆包服务，按服务用量计费。开始翻译后，所选音频会发送到火山引擎。")
                    .font(.system(size:13)).foregroundStyle(.secondary).lineSpacing(4)
                ReadinessRow(icon:"cloud",title:model.configured ? "豆包凭据已配置":"需要配置豆包连接",detail:"不会自动从本地模式切换到付费服务",ready:model.configured)
                Button("打开服务连接设置…"){model.openSettings(section:.connection)}
            }
        }
    }
    private var sound:some View {
        VStack(alignment:.leading,spacing:16){
            Text("只收听声音，不录制屏幕。点击检测时才会请求系统录音权限。")
                .font(.system(size:13)).foregroundStyle(.secondary).lineSpacing(4)
            ReadinessRow(icon:"speaker.wave.2",title:"系统声音",detail:model.systemAudioSummary,ready:model.systemSignalObserved)
            HStack{
                Button(setup.working ? "正在检测…":"检测系统声音"){setup.checkSystemSound()}.disabled(setup.working || model.active || model.hasMeeting || setup.runningFromReadOnlyVolume)
                Button("打开系统设置…"){PermissionLinks.systemAudio()}.buttonStyle(.link)
            }
            Text("在“录屏与系统录音”页面下方的“仅系统录音”中允许 TalkFloat。无需打开录屏开关。")
                .font(.system(size:11.5)).foregroundStyle(.secondary).lineSpacing(3)
            Divider()
            ReadinessRow(icon:"mic",title:"麦克风声音 · 可选",detail:setup.microphoneAuthorized ? "已授权，日常使用时可在菜单栏开启":"只有需要翻译麦克风发言时才需授权",ready:setup.microphoneAuthorized)
            if !setup.microphoneAuthorized{
                Button(setup.microphoneDenied ? "打开麦克风设置…":"允许麦克风…"){
                    if setup.microphoneDenied{PermissionLinks.microphone()}else{setup.requestMicrophone()}
                }
            }
            if !setup.result.isEmpty && (model.audioProbe == nil || setup.working){Text(setup.result).font(.system(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)}
        }
    }
    private var sample:some View {
        VStack(alignment:.leading,spacing:16){
            Text("播放一段英语，实际检查声音采集、实时翻译和 Markdown 存档。测试期间只收听系统声音。")
                .font(.system(size:13)).foregroundStyle(.secondary).lineSpacing(4)
            VStack(alignment:.leading,spacing:8){
                Text("The meeting starts on Tuesday at ten in the morning.").font(.system(size:14,weight:.medium))
                Text("示例包含日期、金额和截止时间。请核对字幕与存档，而不只看是否出现文字。")
                    .font(.system(size:12)).foregroundStyle(.secondary).lineSpacing(3)
            }.padding(16).frame(maxWidth:.infinity,alignment:.leading).modifier(CardSurface())
            Button(setup.working ? "测试进行中…":"播放英语并测试翻译"){setup.runSample()}
                .buttonStyle(.borderedProminent).disabled(setup.working || model.active || model.hasMeeting || !model.canStart || setup.runningFromReadOnlyVolume || (model.mode == .local && !model.localModelsReady))
            if model.mode == .doubao{Text("这次测试会使用你的豆包额度。") .font(.system(size:11.5)).foregroundStyle(.secondary)}
            if !setup.result.isEmpty{
                Label(setup.result,systemImage:setup.samplePassed ? "checkmark.circle":"info.circle")
                    .font(.system(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }
            if setup.samplePassed{Button("查看示例记录"){model.revealLatestArchive()}.buttonStyle(.link)}
            Text("以后点击右上角 TalkFloat 图标即可开始。首次设置可从“更多”中重新打开。")
                .font(.system(size:12)).foregroundStyle(.secondary).lineSpacing(3)
        }
    }
}

struct ReadinessRow:View {
    let icon:String
    let title:String
    let detail:String
    var ready=false
    var body:some View{
        HStack(alignment:.top,spacing:12){
            Image(systemName:icon).font(.system(size:17)).foregroundStyle(ready ? Brand.accent:Color.secondary).frame(width:24,height:24)
            VStack(alignment:.leading,spacing:5){
                Text(title).font(.system(size:13,weight:.medium))
                Text(detail).font(.system(size:12)).foregroundStyle(.secondary).lineSpacing(3).fixedSize(horizontal:false,vertical:true)
            }
            Spacer(minLength:0)
        }
    }
}
