import SwiftUI
import AppKit

enum SettingsSection:String,CaseIterable,Identifiable {
    case general,appearance,connection,archive,about
    var id:String{rawValue}
    var title:String{switch self{case .general:return "声音与模型";case .appearance:return "字幕外观";case .connection:return "豆包连接";case .archive:return "会议记录";case .about:return "关于与更新"}}
    var icon:String{switch self{case .general:return "waveform";case .appearance:return "captions.bubble";case .connection:return "cloud";case .archive:return "folder";case .about:return "info.circle"}}
    var detail:String{switch self{case .general:return "检查声音、权限与本机语言资源。";case .appearance:return "让字幕适合你的阅读习惯。";case .connection:return "使用自己的豆包同声传译服务。";case .archive:return "中英文字自动保存为 Markdown。";case .about:return "版本、更新与问题反馈。"}}
}

struct SettingsView:View {
    @ObservedObject var model:SessionModel
    @ObservedObject var setup:SetupCoordinator
    @ObservedObject var updates:AppUpdater
    @State private var copied=false
    var body:some View {
        HStack(spacing:0){
            VStack(alignment:.leading,spacing:5){
                HStack(spacing:8){TalkFloatMark().fill(.primary).frame(width:21,height:18);Text("TalkFloat").font(.system(size:13,weight:.semibold))}
                    .padding(.horizontal,10).padding(.top,12).padding(.bottom,20)
                ForEach(SettingsSection.allCases){section in
                    Button{model.settingsSection=section}label:{
                        Label(section.title,systemImage:section.icon).font(.system(size:12.5,weight:model.settingsSection==section ? .medium:.regular))
                            .frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,10).padding(.vertical,10)
                            .foregroundStyle(model.settingsSection==section ? Brand.accent:Color.primary)
                            .background(model.settingsSection==section ? Brand.accent.opacity(0.10):.clear,in:RoundedRectangle(cornerRadius:8))
                    }.buttonStyle(QuietButtonStyle()).accessibilityValue(model.settingsSection==section ? "已选择":"")
                }
                Spacer()
            }.padding(10).frame(width:152).background(.regularMaterial)
            Divider()
            VStack(alignment:.leading,spacing:0){
                VStack(alignment:.leading,spacing:7){
                    Text(model.settingsSection.title).font(.system(size:20,weight:.semibold))
                    Text(model.settingsSection.detail).font(.system(size:12)).foregroundStyle(.secondary)
                }.padding(.bottom,24)
                ScrollView{
                    VStack(alignment:.leading,spacing:20){
                        switch model.settingsSection{
                        case .general:general
                        case .appearance:AppearanceSettings(model:model)
                        case .connection:ConnectionSettings(model:model,access:model.access)
                        case .archive:ArchiveSettings(model:model)
                        case .about:about
                        }
                    }.frame(maxWidth:.infinity,alignment:.leading).padding(2)
                }.scrollIndicators(.automatic)
            }.padding(26).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading).background(Brand.surface)
        }.frame(minWidth:620,minHeight:520).tint(Brand.accent)
    }
    private var general:some View{
        VStack(alignment:.leading,spacing:20){
            ReadinessRow(icon:"waveform",title:"系统声音",detail:model.systemAudioSummary,ready:model.systemSignalObserved)
            ReadinessRow(icon:"mic",title:"麦克风声音",detail:setup.microphoneAuthorized ? "已授权，可在菜单栏开启或关闭":"可选；仅在需要翻译麦克风发言时开启",ready:setup.microphoneAuthorized)
            ReadinessRow(icon:"desktopcomputer",title:"Apple 本地模型",detail:model.localModelsReady ? "英语与中文资源已就绪":"在首次设置中检查系统要求并准备语言资源",ready:model.localModelsReady)
            Button("打开首次设置与声音测试…"){model.onSetup?()}.disabled(model.active || model.hasMeeting || updates.installing)
            Divider()
            Text("声音从哪里来").font(.system(size:13,weight:.medium))
            Text("系统声音可选择所有应用或仅 Chrome。麦克风跟随 macOS 当前输入设备，包括笔记本麦克风和耳机。")
                .font(.system(size:12)).foregroundStyle(.secondary).lineSpacing(4)
            Text("背景声过滤根据音量和语音处理减少杂音，不代表识别出了某个人。建议开会时使用耳机。")
                .font(.system(size:12)).foregroundStyle(.secondary).lineSpacing(4)
            HStack{Button("系统录音权限…"){PermissionLinks.systemAudio()};Button("麦克风权限…"){PermissionLinks.microphone()}}.buttonStyle(.link).font(.system(size:12))
        }.onAppear{setup.refreshMicrophone()}
    }
    private var about:some View {
        VStack(alignment:.leading,spacing:18){
            HStack(spacing:14){
                Image(nsImage:NSApp.applicationIconImage).resizable().frame(width:56,height:56)
                VStack(alignment:.leading,spacing:5){
                    Text("TalkFloat").font(.system(size:17,weight:.semibold))
                    Text("版本 \(Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "—") · 开源预览版")
                        .font(.system(size:12)).foregroundStyle(.secondary)
                }
            }
            Divider()
            Toggle("自动检查更新",isOn:$updates.automaticallyChecks).toggleStyle(.switch).controlSize(.small).font(.system(size:13))
            Text("只检查新版本；安装由你确认。翻译、暂停会话和未保存的记录都会阻止更新重启。")
                .font(.system(size:12)).foregroundStyle(.secondary).lineSpacing(4)
            HStack{
                Button(updates.checking ? "正在检查…":"检查更新…"){updates.check()}.disabled(!updates.mayCheck)
                Link("下载 DMG ↗",destination:URL(string:"https://github.com/jinhan261/talkfloat/releases")!).font(.system(size:12))
            }
            Text(model.safeToUpdate ? updates.message:"结束并保存当前会话后即可检查更新。")
                .font(.system(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            Divider()
            HStack{
                Link("反馈问题 ↗",destination:URL(string:"https://github.com/jinhan261/talkfloat/issues")!)
                Spacer()
                Button(copied ? "已复制":"复制诊断信息"){
                    SupportInfo.copy(model:model);copied=true
                    Task{try? await Task.sleep(for:.seconds(2));copied=false}
                }
            }.font(.system(size:12))
            Text("诊断信息只含版本、运行状态与权限状态，不含音频、会议文字、密钥或文件路径。")
                .font(.system(size:11.5)).foregroundStyle(.secondary).lineSpacing(3)
            HStack{
                Link("隐私说明",destination:URL(string:"https://github.com/jinhan261/talkfloat/blob/main/PRIVACY.md")!)
                Link("MIT 许可证",destination:URL(string:"https://github.com/jinhan261/talkfloat/blob/main/LICENSE")!)
            }.font(.system(size:12))
        }
    }
}
