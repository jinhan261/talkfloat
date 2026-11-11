import SwiftUI
import AppKit
import SayloriCore

/// The popover follows content changes, but remains usable on short displays.
/// A measured, unconstrained child avoids compressing away the footer when a
/// source menu, microphone controls or an error explanation is expanded.
struct MenuPopoverContent:View {
    @ObservedObject var model:SessionModel
    let maximumHeight:CGFloat
    @State private var contentHeight:CGFloat=450
    var body:some View {
        ScrollView(.vertical){
            PanelView(model:model).fixedSize(horizontal:false,vertical:true)
                .background(GeometryReader{geometry in
                    Color.clear.preference(key:MenuHeightPreference.self,value:geometry.size.height)
                })
        }.scrollIndicators(.automatic)
            .frame(width:Brand.width,height:min(maximumHeight,contentHeight))
            .background(Brand.surface)
            .onPreferenceChange(MenuHeightPreference.self){height in
                guard height>0,abs(contentHeight-height)>0.5 else{return}
                contentHeight=height
            }
    }
}
private struct MenuHeightPreference:PreferenceKey {
    static let defaultValue:CGFloat=0
    static func reduce(value:inout CGFloat,nextValue:()->CGFloat){value=max(value,nextValue())}
}

struct PanelView:View {
    @ObservedObject var model:SessionModel
    private var stateText:String {
        if model.phase == .idle {
            if model.mode == .local && !model.localModelsReady{return "待准备"}
            if !model.canStart{return "待连接"}
            return "就绪"
        }
        return model.phase.rawValue
    }
    var body:some View {
        VStack(alignment:.leading,spacing:18){
            HStack(spacing:8){
                TalkFloatMark().fill(Brand.mark).frame(width:23,height:19).accessibilityHidden(true)
                Text("TalkFloat").font(.system(size:14,weight:.semibold))
                Spacer()
                HStack(spacing:5){
                    Image(systemName:model.phase == .live ? "waveform":(model.phase == .failed ? "exclamationmark.circle":"circle.fill"))
                        .font(.system(size:model.phase == .idle ? 4:10)).foregroundStyle(model.phase == .live ? Brand.accent:Color.secondary)
                    Text(stateText).font(.system(size:11.5)).foregroundStyle(.secondary)
                }.accessibilityElement(children:.combine)
                PanelIcon(icon:"gearshape",label:"设置"){model.openSettings(section:.general)}
                    .overlay(alignment:.topTrailing){if model.updateAvailable{Circle().fill(Brand.accent).frame(width:5,height:5).allowsHitTesting(false)}}
                    .help(model.updateAvailable ? "有新版本，可在关于页面安装":"设置")
            }.frame(height:26)
            HStack(spacing:8){
                Text("英语").foregroundStyle(.secondary)
                Image(systemName:"arrow.right").font(.system(size:11)).foregroundStyle(.tertiary)
                Text("简体中文")
                Spacer()
                Text("实时字幕").font(.system(size:11)).foregroundStyle(.secondary)
            }.font(.system(size:13,weight:.medium)).padding(.horizontal,2).accessibilityElement(children:.combine)
            VStack(alignment:.leading,spacing:8){
                ChoiceStrip(title:"翻译模式",options:[(TranslationMode.local,"本地模型"),(.doubao,"豆包云端")],selection:Binding(get:{model.mode},set:{model.setMode($0)}))
                    .disabled(model.active || model.hasMeeting || model.setupInProgress || model.preparingLocalModels)
                    .help(model.active || model.hasMeeting ? "结束本次会议后可切换翻译模式":"本地无 API 费用；豆包按服务用量计费")
                Text(model.mode.detail).font(.system(size:11.5)).foregroundStyle(.secondary).padding(.horizontal,2)
            }
            VStack(spacing:0){
                SourcePicker(model:model).disabled(model.active || model.hasMeeting || model.setupInProgress)
                    .help(model.active || model.hasMeeting ? "结束本次会议后可切换音源":"选择收听的应用")
                Divider().padding(.leading,46).padding(.trailing,12)
                MicrophoneSection(model:model)
            }.modifier(CardSurface())
            if !model.notice.isEmpty {
                if model.phase == .failed || !model.active {RecoveryNotice(model:model,text:model.notice)}
                else{Text(model.notice).font(.system(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)}
            }
            if !model.microphoneNotice.isEmpty{RecoveryNotice(model:model,text:model.microphoneNotice)}
            actions
            Divider()
            footer
            if !model.archiveError.isEmpty{RecoveryNotice(model:model,text:model.archiveError)}
        }.padding(Brand.inset).frame(width:Brand.width).background(Brand.surface).tint(Brand.accent)
    }
    private var actions:some View {
        VStack(spacing:12){
            if model.phase == .live {
                HStack(spacing:8){
                    Button{Task{await model.stop(paused:true)}}label:{Label("暂停",systemImage:"pause.fill").frame(maxWidth:.infinity)}.buttonStyle(PanelActionStyle())
                    Button{Task{await model.stop()}}label:{Text("结束并存档").frame(maxWidth:.infinity)}.buttonStyle(PanelActionStyle(primary:true))
                }
                HStack{
                    Button{model.toggleCaption()}label:{Label(model.visible ? "隐藏字幕":"显示字幕",systemImage:model.visible ? "eye.slash":"eye")}
                    Spacer();Button("字幕归位"){model.resetCaption()}
                }.buttonStyle(.plain).font(.system(size:12)).foregroundStyle(.secondary).padding(.horizontal,2)
            }else if model.busy {
                HStack{ProgressView().controlSize(.small);Text(model.phase == .stopping ? "正在保存会议记录…":"正在准备声音与字幕…");Spacer();if model.phase == .connecting{Button("取消"){Task{await model.stop()}}}}
                    .font(.system(size:12)).frame(height:38)
            }else{
                Button{
                    if model.mode == .local && !model.localModelsReady{model.onSetup?()}
                    else if !model.canStart{model.openSettings(section:.connection)}
                    else{model.start()}
                }label:{
                    Label(startTitle,systemImage:startTitle.contains("开始") || startTitle.contains("继续") ? "play.fill":"arrow.right").frame(maxWidth:.infinity)
                }.buttonStyle(PanelActionStyle(primary:true)).disabled(model.setupInProgress || model.preparingLocalModels || model.updateInstallationInProgress)
                if model.hasMeeting{Button("结束并存档"){Task{await model.stop()}}.buttonStyle(.plain).font(.system(size:12))}
            }
        }
    }
    private var startTitle:String {
        if model.mode == .local && !model.localModelsReady{return "准备本地模型"}
        if !model.canStart{return "连接豆包服务"}
        return model.phase == .paused ? "继续翻译":"开始翻译"
    }
    private var footer:some View {
        HStack(spacing:8){
            Button{model.openArchiveFolder()}label:{
                HStack(spacing:10){
                    Image(systemName:"clock.arrow.circlepath").font(.system(size:15)).foregroundStyle(.secondary).frame(width:22)
                    VStack(alignment:.leading,spacing:4){
                        Text("会议记录").font(.system(size:12,weight:.medium))
                        Text(model.archiveURL != nil && !model.hasMeeting && model.phase == .idle && model.archiveError.isEmpty ? "已保存 · Markdown":"中英对照 · Markdown").font(.system(size:11)).foregroundStyle(.secondary)
                    }
                }.padding(.vertical,2)
            }.buttonStyle(QuietButtonStyle()).help("打开本机中英记录；不保存录音")
            Spacer()
            Menu {
                if model.archiveURL != nil{Button("查看最近记录"){model.revealLatestArchive()};Divider()}
                Button("首次设置与声音测试…"){model.onSetup?()}.disabled(model.active || model.hasMeeting)
                Button(model.updateAvailable ? "安装可用更新…":"检查更新…"){model.onCheckUpdates?()}.disabled(!model.safeToUpdate)
                Button("关于 TalkFloat"){model.openSettings(section:.about)}
                Divider()
                Button("退出 TalkFloat"){NSApp.terminate(nil)}
            }label:{Image(systemName:"ellipsis").font(.system(size:14,weight:.medium)).frame(width:26,height:28)}
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().foregroundStyle(.secondary).help("更多").accessibilityLabel("更多")
        }
    }
}

struct RecoveryNotice:View {
    @ObservedObject var model:SessionModel
    let text:String
    @State private var expanded=false
    private var advice:RecoveryAdvice{.forMessage(text)}
    var body:some View {
        VStack(alignment:.leading,spacing:8){
            Label(advice.title,systemImage:"exclamationmark.circle").font(.system(size:12,weight:.medium))
            Text(advice.detail).font(.system(size:11.5)).foregroundStyle(.secondary).lineSpacing(3).fixedSize(horizontal:false,vertical:true)
            HStack{
                Button(actionTitle){
                    switch advice.action{
                    case .setup:model.onSetup?()
                    case .connection:model.openSettings(section:.connection)
                    case .archive:model.openSettings(section:.archive)
                    case .retry:model.start()
                    }
                }.disabled(model.active || model.updateInstallationInProgress)
                Spacer()
                Button(expanded ? "收起详情":"详细原因"){expanded.toggle()}
            }.buttonStyle(.plain).font(.system(size:11.5)).foregroundStyle(Brand.accent)
            if expanded{Text(text).font(.system(size:11)).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)}
            if !model.archiveError.isEmpty{Button("重试保存"){Task{await model.retrySave()}}.font(.system(size:12)).disabled(model.active)}
        }.padding(12).frame(maxWidth:.infinity,alignment:.leading).background(Brand.rowFill,in:RoundedRectangle(cornerRadius:10))
    }
    private var actionTitle:String{switch advice.action{case .setup:return "检查声音与模型";case .connection:return "检查连接";case .archive:return "检查存储位置";case .retry:return "重新开始"}}
}
