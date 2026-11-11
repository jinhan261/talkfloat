import SwiftUI
import AppKit

struct AppearanceSettings:View {
    @ObservedObject var model:SessionModel
    var body:some View {
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
