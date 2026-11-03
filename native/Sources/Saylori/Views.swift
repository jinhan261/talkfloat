import SwiftUI
import AppKit
import SayloriCore

struct PanelView:View {
    @ObservedObject var model:SessionModel
    private var stateText:String {
        if !model.canStart && model.phase == .idle{return "未连接"}
        return model.phase == .idle ? "就绪":model.phase.rawValue
    }
    var body:some View {
        VStack(alignment:.leading,spacing:16){
            header
            if model.showingSettings {SettingsView(model:model)}else{
                HStack(spacing:8){
                    Text("英语").foregroundStyle(.secondary)
                    Image(systemName:"arrow.right").font(.system(size:11,weight:.medium)).foregroundStyle(.tertiary)
                    Text("简体中文")
                    Spacer()
                    Text("实时字幕").font(.system(size:11)).foregroundStyle(.secondary)
                }.font(.system(size:13,weight:.medium)).padding(.horizontal,2)
                    .accessibilityElement(children:.combine)
                VStack(alignment:.leading,spacing:7){
                    ChoiceStrip(title:"翻译模式",options:[(TranslationMode.local,"本地免费"),(.doubao,"豆包云端")],selection:Binding(get:{model.mode},set:{model.setMode($0)}))
                        .disabled(model.active || model.hasMeeting)
                        .help(model.active || model.hasMeeting ? "结束本次会议后可切换翻译模式":"本地免费，豆包按服务用量计费")
                    Text(model.mode.detail).font(.system(size:11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal:false,vertical:true).padding(.horizontal,2)
                }
                VStack(spacing:0){
                    SourcePicker(model:model).disabled(model.active || model.hasMeeting)
                        .help(model.active || model.hasMeeting ? "结束本次会议后可切换音源":"选择收听的应用")
                    Divider().padding(.leading,46).padding(.trailing,12)
                    MicrophoneSection(model:model)
                }.modifier(CardSurface())
                if !model.notice.isEmpty{message(model.notice,error:model.phase == .failed)}
                if !model.microphoneNotice.isEmpty{message(model.microphoneNotice,error:true)}
                actions
                if #available(macOS 26.4,*),!model.localModelsReady {
                    Button{model.preparingLocalModels=true;model.localModelNotice="正在准备本机语言模型…"}label:{
                        Label(model.preparingLocalModels ? "正在准备语言模型…":(model.mode == .local ? "准备本地语言模型":"启用更快的中文预览"),systemImage:"bolt")
                    }.buttonStyle(.plain).font(.system(size:11)).foregroundStyle(Brand.accent).disabled(model.preparingLocalModels || model.active)
                }
                if !model.localModelNotice.isEmpty && model.localModelNotice != "本地英语与中文模型已就绪"{message(model.localModelNotice,error:false)}
                footer
                if !model.archiveError.isEmpty{message(model.archiveError,error:true);Button("重试保存"){Task{await model.retrySave()}}.disabled(model.active)}
            }
        }.padding(Brand.inset).frame(width:Brand.width).background(Brand.surface).tint(Brand.accent)
            .modifier(LocalModelPreparation(model:model))
    }
    private var header:some View {
        HStack(spacing:8){
            if model.showingSettings {
                PanelIcon(icon:"chevron.left",label:"返回"){model.showingSettings=false}
                Text("设置").font(.system(size:14,weight:.medium));Spacer()
            }else{
                TalkFloatMark().fill(Brand.mark).frame(width:22,height:18).accessibilityHidden(true)
                Text("TalkFloat").font(.system(size:14,weight:.medium,design:.rounded))
                Spacer()
                HStack(spacing:5){
                    Circle().fill(model.phase == .live ? Brand.accent:(model.phase == .failed ? Color.red:Color.secondary.opacity(0.5))).frame(width:4,height:4)
                    Text(stateText).font(.system(size:11)).foregroundStyle(.secondary)
                }.accessibilityElement(children:.combine)
                PanelIcon(icon:"gearshape",label:"设置"){model.showingSettings=true}
            }
        }.frame(height:28)
    }
    private var actions:some View {
        VStack(spacing:10){
            if model.phase == .live {
                HStack(spacing:8){
                    Button{Task{await model.stop(paused:true)}}label:{Label("暂停翻译",systemImage:"pause.fill").frame(maxWidth:.infinity)}.buttonStyle(PanelActionStyle(primary:true))
                    Button{Task{await model.stop()}}label:{Text("结束并存档").frame(maxWidth:.infinity)}.buttonStyle(PanelActionStyle())
                }
                HStack{
                    Button{model.toggleCaption()}label:{Label(model.visible ? "隐藏字幕":"显示字幕",systemImage:model.visible ? "eye.slash":"eye")}
                    Spacer();Button("字幕归位"){model.resetCaption()}
                }.buttonStyle(.plain).font(.system(size:11)).foregroundStyle(.secondary).padding(.horizontal,2)
            }else if model.busy {
                HStack{ProgressView().controlSize(.small);Text(model.phase == .stopping ? "正在保存会议记录…":"正在准备声音与字幕…");Spacer();if model.phase == .connecting{Button("取消"){Task{await model.stop()}}}}
                    .font(.system(size:12)).frame(height:38)
            }else{
                Button{if model.canStart{model.start()}else{model.showingSettings=true}}label:{
                    Label(model.canStart ? (model.phase == .paused ? "继续翻译":"开始翻译"):"设置翻译连接",systemImage:model.canStart ? "play.fill":"link").frame(maxWidth:.infinity)
                }.buttonStyle(PanelActionStyle(primary:true))
                if model.phase == .paused{Button("结束并存档"){Task{await model.stop()}}.buttonStyle(.plain).font(.system(size:11))}
            }
        }
    }
    private var footer:some View {
        HStack(spacing:8){
            Button{model.openArchiveFolder()}label:{
                HStack(spacing:9){
                    Image(systemName:"clock.arrow.circlepath").font(.system(size:14)).foregroundStyle(.secondary).frame(width:24)
                    VStack(alignment:.leading,spacing:3){
                        Text("会议记录").font(.system(size:11.5,weight:.medium))
                        Text("中英对照，自动存档").font(.system(size:11)).foregroundStyle(.secondary)
                    }
                }.padding(.vertical,4).padding(.horizontal,2)
            }.buttonStyle(QuietButtonStyle()).help("打开本机中英记录；不保存录音")
            Spacer(minLength:4)
            Menu {
                if model.archiveURL != nil{Button("查看最近记录"){model.revealLatestArchive()}}
                Button("设置"){model.showingSettings=true}
                Divider()
                Button("关于 TalkFloat"){NSApp.orderFrontStandardAboutPanel(nil)}
                Divider()
                Button("退出 TalkFloat"){NSApp.terminate(nil)}
            }label:{Image(systemName:"ellipsis").font(.system(size:13,weight:.semibold)).frame(width:24,height:28)}
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().foregroundStyle(.secondary).help("更多").accessibilityLabel("更多")
        }
    }
    private func message(_ text:String,error:Bool)->some View {
        Label(text,systemImage:error ? "exclamationmark.circle":"info.circle")
            .font(.system(size:11)).foregroundStyle(error ? Color.red:.secondary)
            .fixedSize(horizontal:false,vertical:true).textSelection(.enabled)
    }
}

struct SettingsView:View {
    @ObservedObject var model:SessionModel
    @State private var section=0
    var body:some View {
        VStack(spacing:16){
            ChoiceStrip(title:"设置分类",options:[(0,"字幕外观"),(1,"服务连接")],selection:$section)
            ScrollView {
                VStack(alignment:.leading,spacing:16){
                    if section==0 {appearance}else{ConnectionSettings(model:model,access:model.access)}
                }.padding(1)
            }.scrollIndicators(.automatic)
        }.frame(height:min(section==0 ? 454:480,(NSScreen.main?.visibleFrame.height ?? 800)-110))
            .onAppear{if !model.canStart{section=1}}
    }
    private var appearance:some View {
        VStack(alignment:.leading,spacing:16){
            VStack(alignment:.leading,spacing:7){
                HStack{Text("字幕预览").font(.system(size:11,weight:.medium));Spacer();Image(systemName:"captions.bubble").font(.system(size:12))}.opacity(0.55)
                Text("下周二上午十点见。").font(.system(size:model.fontSize*0.6,weight:.medium))
                Text("See you next Tuesday at ten.").font(.system(size:11)).opacity(model.showSource ? 0.65:0)
            }.padding(16).frame(maxWidth:.infinity,alignment:.leading).foregroundStyle(model.captionStyle.foreground)
                .background(CaptionBackground(style:model.captionStyle,opacity:model.backgroundOpacity))
                .clipShape(RoundedRectangle(cornerRadius:12,style:.continuous))
                .overlay(RoundedRectangle(cornerRadius:12).strokeBorder(Brand.border,lineWidth:0.5))
                .compositingGroup()
            VStack(alignment:.leading,spacing:8){
                SectionLabel(title:"背景")
                HStack(spacing:6){ForEach(CaptionStyle.allCases){style in
                    Button{model.captionStyle=style}label:{
                        VStack(spacing:7){
                            Image(systemName:style == .glass ? "square.on.square":(style == .dark ? "moon.fill":"sun.max.fill")).font(.system(size:15,weight:.regular))
                                .foregroundStyle(model.captionStyle==style ? Brand.accent:Color.secondary)
                            Text(style.title).font(.system(size:11,weight:model.captionStyle==style ? .medium:.regular))
                        }.frame(maxWidth:.infinity).frame(height:56)
                            .background(Brand.card,in:RoundedRectangle(cornerRadius:10))
                            .overlay(RoundedRectangle(cornerRadius:10).strokeBorder(model.captionStyle==style ? Brand.accent.opacity(0.65):Brand.border,lineWidth:model.captionStyle==style ? 1.5:0.5))
                    }.buttonStyle(QuietButtonStyle()).accessibilityLabel("字幕背景："+style.title).accessibilityValue(model.captionStyle==style ? "已选择":"")
                }}
            }
            VStack(spacing:0){
                VStack(spacing:6){
                    HStack{Text("背景不透明度");Spacer();Text("\(Int((model.backgroundOpacity*100).rounded()))%").monospacedDigit().foregroundStyle(.secondary)}
                    Slider(value:Binding(get:{model.backgroundOpacity},set:{model.backgroundOpacity=($0*20).rounded()/20}),in:0.40...1)
                        .accessibilityLabel("背景不透明度").controlSize(.small)
                }.padding(12)
                Divider().padding(.horizontal,12)
                HStack{Text("文字大小");Spacer();ChoiceStrip(title:"字幕字号",options:[(24.0,"小"),(30.0,"中"),(36.0,"大")],selection:$model.fontSize).frame(width:138)}.padding(.horizontal,12).padding(.vertical,9)
                Divider().padding(.horizontal,12)
                HStack{Text("显示英语原文");Spacer();Toggle("显示英语原文",isOn:$model.showSource).labelsHidden().toggleStyle(.switch).controlSize(.mini)}.padding(12)
            }.font(.system(size:11.5)).modifier(CardSurface())
            HStack{
                Button("打开字幕预览"){model.previewCaption()}.disabled(model.hasMeeting || model.busy)
                Spacer()
                Button("字幕归位"){if !model.visible && !model.hasMeeting{model.previewCaption()};model.resetCaption()}
            }.buttonStyle(.plain).foregroundStyle(Brand.accent).font(.system(size:11)).padding(.horizontal,2)
        }
    }
}

struct ConnectionSettings:View {
    @ObservedObject var model:SessionModel
    @ObservedObject var access:CredentialSession
    @State private var remember=false
    @State private var audioResult=""
    @FocusState private var focus:String?
    var body:some View {
        VStack(alignment:.leading,spacing:16){
            HStack{
                VStack(alignment:.leading,spacing:4){
                    Text("豆包同声传译").font(.system(size:13,weight:.medium))
                    Text("所选音频发送至豆包进行翻译").font(.system(size:11)).foregroundStyle(.secondary)
                }
                Spacer()
                Text(model.configured ? "已配置":"未配置").font(.system(size:11)).foregroundStyle(.secondary)
            }
            VStack(alignment:.leading,spacing:12){
                ChoiceStrip(title:"凭据类型",options:[(true,"App ID / Token"),(false,"API Key")],selection:$access.draft.legacy)
                if access.draft.legacy{
                    field("App ID",id:"id"){TextField("输入 App ID",text:$access.draft.appID).focused($focus,equals:"id")}
                    field("Access Token",id:"token"){SecureField("输入 Access Token",text:$access.draft.accessToken).focused($focus,equals:"token")}
                }else{field("API Key",id:"key"){SecureField("输入 API Key",text:$access.draft.apiKey).focused($focus,equals:"key")}}
                Toggle("保存到 macOS 钥匙串",isOn:$remember).toggleStyle(.checkbox).font(.system(size:11))
                Button{Task{await model.applyCredentials(remember:remember)}}label:{
                    HStack(spacing:7){if model.connectionChecking{ProgressView().controlSize(.small)};Text(model.connectionChecking ? "正在检查…":(remember ? "保存并检查":"检查连接"))}.frame(maxWidth:.infinity)
                }.buttonStyle(PanelActionStyle(primary:true)).disabled(model.active || !access.draft.trimmed.isValid)
                Text(remember ? "保存到本机钥匙串。检查连接不上传声音。":"仅本次使用，不修改已存凭据。检查连接不上传声音。")
                    .font(.system(size:11)).lineSpacing(2).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }.padding(12).modifier(CardSurface())
            if !model.connectionResult.isEmpty{Text(model.connectionResult).font(.system(size:11)).fixedSize(horizontal:false,vertical:true).textSelection(.enabled)}
            if !access.message.isEmpty{Text(access.message).font(.system(size:11)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)}
            HStack{
                Button(access.working ? "正在读取…":"读取已存凭据"){Task{await access.load(interactive:true)}}.disabled(access.working || model.active)
                Spacer()
                Link("豆包控制台 ↗",destination:URL(string:"https://console.volcengine.com/speech/service/10030")!)
            }.buttonStyle(.plain).font(.system(size:11)).foregroundStyle(Brand.accent)
            VStack(alignment:.leading,spacing:10){
                SectionLabel(title:"声音与权限")
                Button(model.phase == .checking ? "正在检测，请播放英语…":"检测所选音源（8 秒）"){Task{audioResult=await model.testAudio()}}.disabled(model.active || model.hasMeeting)
                if !audioResult.isEmpty{Text(audioResult).font(.system(size:11)).fixedSize(horizontal:false,vertical:true)}
                Button("录屏与系统录音权限…"){NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)}
            }.buttonStyle(.plain).font(.system(size:11)).foregroundStyle(Brand.accent)
            Text("中英文字保存在这台 Mac。即时预览可能会校正，会议记录以最终译文为准。")
                .font(.system(size:11)).lineSpacing(2).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }.onDisappear{focus=nil}
    }
    private func field<V:View>(_ title:String,id:String,@ViewBuilder content:()->V)->some View {
        VStack(alignment:.leading,spacing:6){
            Text(title).font(.system(size:11,weight:.medium)).foregroundStyle(.secondary)
            content().textFieldStyle(.plain).font(.system(size:12)).padding(.horizontal,10).frame(height:34)
                .background(Brand.field,in:RoundedRectangle(cornerRadius:7))
                .overlay(RoundedRectangle(cornerRadius:7).strokeBorder(focus==id ? Brand.accent:Brand.border,lineWidth:focus==id ? 1.5:0.5))
                .accessibilityLabel(title)
        }
    }
}
