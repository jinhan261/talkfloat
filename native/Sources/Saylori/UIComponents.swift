import SwiftUI
import AppKit

// Shared macOS metrics: one reading edge, quiet surfaces, one functional accent.
enum Brand {
    static let width:CGFloat=336
    static let inset:CGFloat=16
    static let radius:CGFloat=12
    // Dark teal keeps white primary-button labels readable in either appearance.
    static let action=Color(red:34/255,green:121/255,blue:106/255)
    static let accentNS=NSColor(name:nil){appearance in
        appearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua
            ? NSColor(srgbRed:0.40,green:0.80,blue:0.71,alpha:1)
            : NSColor(srgbRed:34/255,green:121/255,blue:106/255,alpha:1)
    }
    static let accent=Color(nsColor:accentNS)
    static let mark=accent
    static func neutral(_ light:CGFloat,_ dark:CGFloat)->Color {
        Color(nsColor:NSColor(name:nil){$0.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua ? NSColor(white:dark,alpha:1):NSColor(white:light,alpha:1)})
    }
    static let surface=neutral(0.965,0.105)
    static let card=neutral(1,0.155)
    static let field=neutral(1,0.12)
    static let selectionTrack=neutral(0.925,0.085)
    static let rowFill=Color.primary.opacity(0.045)
    static let border=Color.primary.opacity(0.075)
}

struct CardSurface:ViewModifier {
    func body(content:Content)->some View {
        content.background(Brand.card,in:RoundedRectangle(cornerRadius:Brand.radius,style:.continuous))
            .overlay(RoundedRectangle(cornerRadius:Brand.radius,style:.continuous).strokeBorder(Brand.border,lineWidth:0.5))
    }
}
struct InputGlyph:View {
    let symbol:String
    var enabled=true
    var body:some View {
        Image(systemName:symbol).font(.system(size:13,weight:.medium))
            .foregroundStyle(enabled ? Brand.accent:Color.secondary)
            .frame(width:28,height:28)
            .background(enabled ? Brand.accent.opacity(0.09):Brand.rowFill,in:RoundedRectangle(cornerRadius:8,style:.continuous))
    }
}
struct PanelIcon:View {
    let icon:String
    let label:String
    let action:()->Void
    var body:some View {
        Button(action:action){Image(systemName:icon).font(.system(size:12,weight:.medium)).frame(width:28,height:28)}
            .buttonStyle(QuietButtonStyle()).foregroundStyle(.secondary).help(label).accessibilityLabel(label)
    }
}
struct QuietButtonStyle:ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration:Configuration)->some View {
        QuietButtonBody(configuration:configuration).opacity(enabled ? 1:0.45)
    }
    private struct QuietButtonBody:View {
        let configuration:ButtonStyle.Configuration
        @State private var hovered=false
        var body:some View {
            configuration.label.contentShape(RoundedRectangle(cornerRadius:7))
                .background(.primary.opacity(configuration.isPressed ? 0.10:(hovered ? 0.055:0)),in:RoundedRectangle(cornerRadius:7))
                .onHover{hovered=$0}
        }
    }
}
struct PanelActionStyle:ButtonStyle {
    var primary=false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration:Configuration)->some View {
        configuration.label.font(.system(size:12.5,weight:.semibold)).frame(minHeight:38)
            .foregroundStyle(primary ? Color.white:Color.primary)
            .background(primary ? Brand.action:Brand.card,in:RoundedRectangle(cornerRadius:10,style:.continuous))
            .overlay(RoundedRectangle(cornerRadius:10,style:.continuous).strokeBorder(primary ? .clear:Brand.border,lineWidth:0.5))
            .overlay(RoundedRectangle(cornerRadius:10).fill(Color.black.opacity(configuration.isPressed ? 0.10:0)))
            .opacity(enabled ? 1:0.45).contentShape(RoundedRectangle(cornerRadius:10))
    }
}
struct ChoiceStrip<Value:Hashable>:View {
    let title:String
    let options:[(Value,String)]
    @Binding var selection:Value
    @FocusState private var focused:Value?
    var body:some View {
        HStack(spacing:2){
            ForEach(options.indices,id:\.self){index in
                let option=options[index]
                Button{selection=option.0;focused=option.0}label:{
                    Text(option.1).font(.system(size:11.5,weight:selection==option.0 ? .semibold:.regular))
                        .frame(maxWidth:.infinity).frame(height:28)
                        .background(selection==option.0 ? Brand.card:Color.clear,in:RoundedRectangle(cornerRadius:7,style:.continuous))
                        .shadow(color:selection==option.0 ? .black.opacity(0.06):.clear,radius:2,y:1)
                }.buttonStyle(QuietButtonStyle()).focusable().focusEffectDisabled().focused($focused,equals:option.0)
                    .overlay(RoundedRectangle(cornerRadius:7).strokeBorder(focused==option.0 ? Brand.accent:Color.clear,lineWidth:1.5).allowsHitTesting(false))
                    .onKeyPress(.leftArrow){moveSelection(from:index,by:-1);return .handled}
                    .onKeyPress(.rightArrow){moveSelection(from:index,by:1);return .handled}
                    .accessibilityLabel(title+"："+option.1)
                    .accessibilityValue(selection==option.0 ? "已选择":"")
            }
        }.padding(3).background(Brand.selectionTrack,in:RoundedRectangle(cornerRadius:10,style:.continuous))
            .accessibilityElement(children:.contain).accessibilityLabel(title)
            .onDisappear{focused=nil}
    }
    private func moveSelection(from index:Int,by delta:Int){
        let next=max(0,min(options.count-1,index+delta))
        selection=options[next].0;focused=options[next].0
    }
}
struct SectionLabel:View {
    let title:String
    var body:some View {Text(title).font(.system(size:10.5,weight:.medium)).foregroundStyle(Color.secondary).padding(.leading,2)}
}
