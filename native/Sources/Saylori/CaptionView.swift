import SwiftUI
import AppKit
import SayloriCore

struct CaptionView:View {
    @ObservedObject var model:SessionModel
    @State private var copied=false
    @State private var hovering=false
    private var ink:Color{model.captionStyle.foreground}
    private var current:CaptionSegment?{model.displayCurrent}
    private var currentText:String {
        if model.previewing{return "会议将于周二上午十点开始。"}
        if let current,current.hasReadableTranslation{return current.translation}
        if let current,!current.source.isEmpty{return current.source}
        return model.phase == .live ? "等待英语发言…":model.phase.rawValue
    }
    private var currentSource:String {model.previewing ? "The meeting starts on Tuesday at ten in the morning.":current?.source ?? ""}
    private var statusText: String {
        if model.phase == .connecting { return "正在准备声音与字幕" }
        if model.phase == .paused { return "已暂停" }
        guard let current, !model.previewing else { return "" }
        if !current.hasReadableTranslation { return "正在翻译" }
        if current.provisional == true && model.mode == .doubao { return "预览 · 待校正" }
        return current.translationFinal ? "" : "实时生成"
    }
    var body:some View {
        VStack(alignment:.leading,spacing:12){
            HStack(spacing:4){
                HStack(spacing:7){
                    Image(systemName:current?.audioOrigin.icon ?? "waveform").font(.system(size:11,weight:.medium))
                        .foregroundStyle(originTint(current?.audioOrigin ?? .system))
                        .frame(width:18,height:24)
                    Text(model.previewing ? "样式预览":(current?.audioOrigin.label ?? "英语 → 中文")).font(.system(size:11,weight:.medium))
                    Text(statusText)
                        .font(.system(size:11)).opacity(0.65).lineLimit(1)
                    Spacer(minLength:8)
                }.foregroundStyle(ink.opacity(0.8)).frame(height:30)
                    .help(model.locked ? "位置已锁定":"按住文字或空白处拖动字幕窗")
                CaptionTool(icon:copied ? "checkmark":"doc.on.doc",label:copied ? "已复制":"复制当前中英内容",ink:ink,quiet:!hovering && !model.previewing){
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString([currentSource,model.previewing ? currentText:(current?.translation ?? "")].filter{!$0.isEmpty}.joined(separator:"\n"),forType:.string)
                    copied=true;Task{try? await Task.sleep(for:.seconds(1.5));copied=false}
                }
                CaptionTool(icon:model.locked ? "lock.fill":"lock.open",label:model.locked ? "解锁字幕位置":"锁定字幕位置",active:model.locked,ink:ink,quiet:!hovering && !model.previewing){model.toggleLock()}
                CaptionTool(icon:"slider.horizontal.3",label:"字幕设置",ink:ink,quiet:!hovering && !model.previewing){model.openSettings()}
                CaptionTool(icon:"xmark",label:"隐藏字幕",ink:ink,quiet:!hovering && !model.previewing){model.toggleCaption()}
            }.foregroundStyle(ink)
            ViewThatFits(in: .vertical) {
                // Keep the live turn pinned when a useful portion of history fits.
                VStack(alignment: .leading, spacing: 12) {
                    currentTurn
                    historyHeading
                    ScrollView(.vertical) { historyRows }
                        .id(current?.id)
                        .frame(minHeight: 52)
                }
                // On short windows or very long turns, give the entire reading
                // area to one document so both languages and every line are reachable.
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 12) {
                        currentTurn
                        historyHeading
                        historyRows
                    }
                }.id(current?.id)
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if !model.archiveError.isEmpty {Text(model.archiveError).font(.caption).foregroundStyle(.red)}
        }.padding(.horizontal,20).padding(.top,12).padding(.bottom,20).onHover{hovering=$0}
            .background(CaptionBackground(style:model.captionStyle,opacity:model.backgroundOpacity))
            .clipShape(RoundedRectangle(cornerRadius:20,style:.continuous))
            .overlay(RoundedRectangle(cornerRadius:20,style:.continuous).stroke(ink.opacity(0.09),lineWidth:0.5)).tint(ink)
            .overlay(CaptionResizeCursors(locked:model.locked))
            .overlay(alignment:.bottomTrailing){
                if !model.locked {
                    Image(systemName:"arrow.up.left.and.arrow.down.right")
                        .font(.system(size:9,weight:.medium)).foregroundStyle(ink.opacity(0.45))
                        .frame(width:22,height:22).padding(4).allowsHitTesting(false)
                        .accessibilityLabel("拖动任一边缘调整字幕大小").help("拖动任一边缘或角落调整大小")
                }
            }
    }

    private var currentTurn: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(currentText)
                .font(.system(size: model.fontSize, weight: .medium))
                .lineSpacing(4)
                .foregroundStyle(ink)
            if !currentSource.isEmpty && model.showSource && (model.previewing || current?.hasReadableTranslation == true) {
                Text(currentSource)
                    .font(.system(size: 15))
                    .lineSpacing(3)
                    .foregroundStyle(ink.opacity(0.68))
            }
        }
        .lineLimit(nil)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var historyHeading: some View {
        VStack(spacing: 12) {
            Rectangle().fill(ink.opacity(0.09)).frame(height: 0.5)
            HStack {
                Text("最近内容")
                Spacer()
                Text(model.previewing ? "示例内容" : "中英自动存档")
            }.font(.system(size: 11, weight: .medium)).foregroundStyle(ink.opacity(0.65))
        }.fixedSize(horizontal: false, vertical: true)
    }

    private var historyRows: some View {
        let history = model.captionWindow.history.suffix(24).reversed()
        return LazyVStack(alignment: .leading, spacing: 14) {
            if model.previewing {
                contextRow(english: "Let's review the plan for next week.", chinese: "我们来过一下下周的计划。", pending: false, origin: .system)
            } else if history.isEmpty {
                Text("之前的发言会显示在这里。").font(.system(size: 13)).foregroundStyle(ink.opacity(0.6))
            } else {
                ForEach(history) { item in
                    contextRow(english: item.source, chinese: item.translation, pending: !item.translationFinal, origin: item.audioOrigin)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func originTint(_ origin:AudioOrigin)->Color {
        if origin == .microphone{return model.captionStyle == .light ? Color(red:0.55,green:0.36,blue:0.17):Color(red:0.84,green:0.68,blue:0.45)}
        return ink.opacity(0.72)
    }
    private func contextRow(english:String,chinese:String,pending:Bool,origin:AudioOrigin)->some View {
        HStack(alignment:.top,spacing:8){
            Image(systemName:origin.icon).font(.system(size:11,weight:.regular)).foregroundStyle(originTint(origin))
                .frame(width:16,height:18)
            VStack(alignment:.leading,spacing:4){
                HStack(spacing:6){
                    Text(origin.label).font(.system(size:11,weight:.medium))
                    if pending{Text("生成中").font(.system(size:11))}
                }.foregroundStyle(ink.opacity(0.65))
                Text(chinese.isEmpty ? "等待这段译文…":chinese).font(.system(size:16)).lineSpacing(3).foregroundStyle(ink.opacity(0.85))
                if model.showSource && !english.isEmpty{Text(english).font(.system(size:12.5)).lineSpacing(2).foregroundStyle(ink.opacity(0.68))}
            }
        }.fixedSize(horizontal:false,vertical:true)
            .frame(maxWidth:.infinity,alignment:.leading)
    }
}
