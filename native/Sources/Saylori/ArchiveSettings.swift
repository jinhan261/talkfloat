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
        VStack(alignment:.leading,spacing:16){
            VStack(alignment:.leading,spacing:5){
                Text("保存会议记录").font(.system(size:13,weight:.medium))
                Text("原文与中文译文自动保存为 Markdown，\n不保存录音。").font(.system(size:11)).foregroundStyle(.secondary)
            }
            VStack(alignment:.leading,spacing:12){
                Label("存储位置",systemImage:"folder").font(.system(size:11,weight:.medium)).foregroundStyle(.secondary)
                Text(model.archiveDirectory.path).font(.system(size:12)).textSelection(.enabled)
                    .fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,alignment:.leading)
                Button{model.chooseArchiveDirectory()}label:{Text("选择文件夹…").frame(maxWidth:.infinity)}
                    .buttonStyle(PanelActionStyle()).disabled(!model.canChangeArchiveDirectory)
            }.padding(12).modifier(CardSurface())
            HStack {
                Button("打开文件夹"){model.openArchiveFolder()}
                Spacer()
                Button("恢复默认"){Task{await model.setArchiveDirectory(TranscriptStore.defaultDirectory)}}
                    .disabled(!model.canChangeArchiveDirectory || model.archiveDirectory == TranscriptStore.defaultDirectory)
            }.buttonStyle(.plain).font(.system(size:11)).foregroundStyle(Brand.accent)
            Text(model.hasMeeting && !model.canChangeArchiveDirectory ? "结束当前会议后可更改位置。":"新记录保存到所选位置，已有记录保留原处。")
                .font(.system(size:11)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            if !model.archiveLocationError.isEmpty {
                Label(model.archiveLocationError,systemImage:"exclamationmark.circle").font(.system(size:11)).foregroundStyle(.red).fixedSize(horizontal:false,vertical:true)
            }
        }
    }
}
