import AppKit
import SwiftUI
import SayloriCore

extension SessionModel {
    func chooseArchiveDirectory(){
        guard canChangeArchiveDirectory else{return}
        let panel=NSOpenPanel()
        panel.title="选择会议记录文件夹";panel.prompt="选择文件夹"
        panel.canChooseDirectories=true;panel.canChooseFiles=false
        panel.allowsMultipleSelection=false;panel.canCreateDirectories=true
        panel.directoryURL=archiveDirectory
        NSApp.activate(ignoringOtherApps:true)
        panel.begin { [weak self] response in
            guard response == .OK,let url=panel.url else{return}
            Task{@MainActor in await self?.setArchiveDirectory(url)}
        }
    }
}

struct ArchiveSettings:View {
    @ObservedObject var model:SessionModel
    var body:some View {
        VStack(alignment:.leading,spacing:20){
            VStack(alignment:.leading,spacing:6){
                Text("保存会议记录").font(.system(size:13,weight:.semibold))
                Text("原文与中文译文自动保存为 Markdown 文档。")
                    .font(.system(size:12)).foregroundStyle(.secondary).lineSpacing(3)
                    .fixedSize(horizontal:false,vertical:true)
            }
            VStack(alignment:.leading,spacing:8){
                Text("存储位置").font(.system(size:11,weight:.medium)).foregroundStyle(.secondary)
                    .padding(.leading,2)
                ArchiveLocationRow(directory:model.archiveDirectory,canChange:model.canChangeArchiveDirectory){model.chooseArchiveDirectory()}
                HStack {
                    Button("在 Finder 中打开"){model.openArchiveFolder()}
                    Spacer()
                    Button("恢复默认"){Task{await model.setArchiveDirectory(TranscriptStore.defaultDirectory)}}
                        .disabled(!model.canChangeArchiveDirectory || model.archiveDirectory == TranscriptStore.defaultDirectory)
                }.buttonStyle(.plain).font(.system(size:11.5)).foregroundStyle(Brand.accent)
                    .padding(.horizontal,2).padding(.top,4)
            }
            VStack(alignment:.leading,spacing:5){
                Text(model.hasMeeting && !model.canChangeArchiveDirectory ? "结束当前会议后可更改位置。":"更改位置后，新记录将保存到所选文件夹。")
                Text("已有记录留在原处；仅保存文字，不保存录音。")
            }.font(.system(size:11.5)).foregroundStyle(.secondary).lineSpacing(3)
                .fixedSize(horizontal:false,vertical:true)
            if !model.archiveLocationError.isEmpty {
                Label(model.archiveLocationError,systemImage:"exclamationmark.circle")
                    .font(.system(size:11.5)).foregroundStyle(.red).lineSpacing(3)
                    .fixedSize(horizontal:false,vertical:true)
            }
        }
    }
}

/// A short, stable row even for deep directories. Full paths remain available
/// to VoiceOver, the tooltip and Copy, without competing with the folder name.
struct ArchiveLocationRow:View {
    let directory:URL
    var canChange=true
    let onChoose:()->Void
    private var parentPath:String{(directory.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath}
    var body:some View {
        HStack(spacing:10){
            Image(systemName:"folder").font(.system(size:20,weight:.regular))
                .foregroundStyle(.secondary).frame(width:26).accessibilityHidden(true)
            VStack(alignment:.leading,spacing:4){
                Text(directory.lastPathComponent).font(.system(size:13,weight:.medium))
                    .foregroundStyle(.primary).lineLimit(1).truncationMode(.middle)
                Text(parentPath).font(.system(size:11)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }.frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle()).help(directory.path)
                .accessibilityElement(children:.ignore)
                .accessibilityLabel("记录文件夹").accessibilityValue(directory.path)
                .contextMenu {
                    Button("复制完整路径"){
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(directory.path,forType:.string)
                    }
                }
            Button("更改…",action:onChoose).buttonStyle(.bordered).controlSize(.small)
                .font(.system(size:11.5,weight:.medium)).fixedSize().focusable()
                .onKeyPress(.return){guard canChange else{return .ignored};onChoose();return .handled}
                .onKeyPress(.space){guard canChange else{return .ignored};onChoose();return .handled}
                .disabled(!canChange).accessibilityLabel("更改会议记录文件夹")
                .help("选择保存会议记录的文件夹")
        }.padding(14).modifier(CardSurface())
    }
}
