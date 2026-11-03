import SwiftUI
import AppKit
import SayloriCore

struct CaptionView:View {
    @ObservedObject var model:SessionModel
    @State private var copied=false
    private var ink:Color{model.captionStyle.foreground}
    private var current:CaptionSegment?{model.displayCurrent}
    private var currentText:String {
        if model.previewing{return "会议将于周二上午十点开始。"}
        if let current,!current.translation.isEmpty{return current.translation}
        return current?.source.isEmpty == false ? "正在翻译…":(model.phase == .live ? "等待英语发言…":model.phase.rawValue)
    }
    private var currentSource:String {model.previewing ? "The meeting starts on Tuesday at ten in the morning.":current?.source ?? ""}
    var body:some View {
        GeometryReader{geometry in
        let history=visibleHistory(size:geometry.size)
        VStack(alignment:.leading,spacing:12){
            HStack(spacing:4){
                HStack(spacing:7){
                    Image(systemName:current?.audioOrigin.icon ?? "waveform").font(.system(size:11,weight:.medium))
                        .foregroundStyle(originTint(current?.audioOrigin ?? .system))
                        .frame(width:18,height:24)
                    Text(model.previewing ? "样式预览":(current?.audioOrigin.label ?? "英语 → 中文")).font(.system(size:11,weight:.medium))
                    Text(model.phase == .connecting ? "正在准备声音与字幕":(model.phase == .paused ? "已暂停":(current?.provisional == true ? (model.mode == .local ? "实时生成":"预览 · 待校正"):(current?.translationFinal == false ? "实时生成":""))))
                        .font(.system(size:11)).opacity(0.65).lineLimit(1)
                    Spacer(minLength:8)
                }.foregroundStyle(ink.opacity(0.8)).frame(height:30)
                    .help(model.locked ? "位置已锁定":"按住文字或空白处拖动字幕窗")
                CaptionTool(icon:copied ? "checkmark":"doc.on.doc",label:copied ? "已复制":"复制当前中英内容",ink:ink){
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString([currentSource,model.previewing ? currentText:(current?.translation ?? "")].filter{!$0.isEmpty}.joined(separator:"\n"),forType:.string)
                    copied=true;Task{try? await Task.sleep(for:.seconds(1.5));copied=false}
                }
                CaptionTool(icon:model.locked ? "lock.fill":"lock.open",label:model.locked ? "解锁字幕位置":"锁定字幕位置",active:model.locked,ink:ink){model.toggleLock()}
                CaptionTool(icon:"slider.horizontal.3",label:"字幕设置",ink:ink){model.openSettings()}
                CaptionTool(icon:"xmark",label:"隐藏字幕",ink:ink){model.toggleCaption()}
            }.foregroundStyle(ink)
            ScrollView {
                VStack(alignment:.leading,spacing:9){
                    Text(currentText).font(.system(size:model.fontSize,weight:.medium)).lineSpacing(4)
                        .frame(maxWidth:.infinity,alignment:.leading).foregroundStyle(ink)
                    if !currentSource.isEmpty && (model.showSource || current?.translation.isEmpty == true) {
                        Text(currentSource).font(.system(size:15)).lineSpacing(3).foregroundStyle(ink.opacity(0.68))
                    }
                }.frame(maxWidth:.infinity,alignment:.leading)
            }.frame(height:contentHeight(width:geometry.size.width-40,available:geometry.size.height)).id(current?.id)
            Rectangle().fill(ink.opacity(0.09)).frame(height:0.5)
            HStack {
                Text("最近内容").font(.system(size:11,weight:.medium))
                Spacer()
                Text(model.previewing ? "示例内容":"中英自动存档")
                    .font(.system(size:11))
            }.foregroundStyle(ink.opacity(0.65))
            ScrollViewReader{proxy in
                ScrollView {
                    VStack(alignment:.leading,spacing:14){
                        if model.previewing {
                            contextRow(english:"Let's review the plan for next week.",chinese:"我们来过一下下周的计划。",pending:false,origin:.system)
                        }else if model.displayContext.isEmpty {
                            Text("之前的发言会显示在这里。").font(.system(size:13)).foregroundStyle(ink.opacity(0.6))
                        }else{
                            ForEach(history){item in
                                contextRow(english:item.source,chinese:item.translation,pending:!item.translationFinal,origin:item.audioOrigin)
                            }
                        }
                    }.frame(maxWidth:.infinity,alignment:.leading).id("context-start")
                }.onChange(of:history.first?.id){_,_ in proxy.scrollTo("context-start",anchor:.top)}
                    .onChange(of:geometry.size){_,_ in proxy.scrollTo("context-start",anchor:.top)}
                    .accessibilityLabel("最近内容，最新在上，\(model.previewing ? 1:history.count)段")
            }.frame(minHeight:56)
            if !model.archiveError.isEmpty {Text(model.archiveError).font(.caption).foregroundStyle(.red)}
        }.padding(.horizontal,20).padding(.top,12).padding(.bottom,20)
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
    }
    private func contentHeight(width:CGFloat,available:CGFloat)->CGFloat {
        func height(_ text:String,size:CGFloat,spacing:CGFloat)->CGFloat {
            let style=NSMutableParagraphStyle();style.lineSpacing=spacing
            return ceil((text as NSString).boundingRect(with:NSSize(width:max(100,width),height:10000),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:[.font:NSFont.systemFont(ofSize:size,weight:.medium),.paragraphStyle:style]).height)
        }
        let english = !currentSource.isEmpty && (model.showSource || current?.translation.isEmpty == true)
        let needed=height(currentText,size:model.fontSize,spacing:4)+(english ? 9+height(currentSource,size:15,spacing:3):0)+6
        return max(72,min(needed,max(72,min(available*0.48,available-210))))
    }
    private func visibleHistory(size:CGSize)->[CaptionSegment] {
        let rows=model.displayContext
        let width=max(100,size.width-64)
        func height(_ text:String,size:CGFloat)->Double {
            let style=NSMutableParagraphStyle();style.lineSpacing=size>13 ? 3:2
            return ceil((text as NSString).boundingRect(with:NSSize(width:width,height:10000),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:[.font:NSFont.systemFont(ofSize:size),.paragraphStyle:style]).height)
        }
        let heights=rows.map { item in
            18+height(item.translation.isEmpty ? "等待这段译文…":item.translation,size:16)+(model.showSource && !item.source.isEmpty ? 4+height(item.source,size:12.5):0)
        }
        let available=max(56,size.height-contentHeight(width:size.width-40,available:size.height)-126)
        // Fit the newest turns first, then display them from newest to oldest.
        // Keep the model and saved meeting in their original chronological order.
        return Array(rows.suffix(CaptionHistoryLayout.visibleCount(heights:heights,available:available)).reversed())
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
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
}
