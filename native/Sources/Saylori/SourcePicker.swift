import SwiftUI
import AppKit
import SayloriCore

struct SourcePicker:View {
    @ObservedObject var model:SessionModel
    @State private var expanded=false
    @State private var highlighted="system"
    var body:some View {
        VStack(spacing:0){
            Button{highlighted=model.source.id;expanded.toggle()}label:{
                HStack(spacing:10){
                    InputGlyph(symbol:model.source.id=="system" ? "speaker.wave.2":"macwindow")
                    VStack(alignment:.leading,spacing:4){
                        Text("系统声音").font(.system(size:12,weight:.medium))
                        Text(model.source.name).font(.system(size:11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Image(systemName:expanded ? "chevron.up":"chevron.down").font(.system(size:9,weight:.semibold)).foregroundStyle(.tertiary)
                }.padding(12).contentShape(Rectangle())
            }.buttonStyle(QuietButtonStyle()).accessibilityLabel("收听：\(model.source.name)").accessibilityValue(expanded ? "已展开":"已收起")
            if expanded{sourceList}
        }
    }
    var sourceList:some View {
        VStack(spacing:3){
            ForEach(model.sources){item in
                Button{select(item)}label:{
                    HStack(spacing:9){
                        Image(systemName:item.id=="system" ? "speaker.wave.2":"macwindow").frame(width:16)
                        Text(item.name).font(.system(size:11.5))
                        Spacer()
                        Image(systemName:"checkmark").font(.system(size:10,weight:.semibold)).opacity(item==model.source ? 1:0)
                    }.foregroundStyle(highlighted==item.id ? Brand.accent:Color.primary)
                        .padding(.horizontal,10).frame(height:32)
                        .background(highlighted==item.id ? Brand.accent.opacity(0.08):Color.clear,in:RoundedRectangle(cornerRadius:7))
                        .overlay(RoundedRectangle(cornerRadius:7).strokeBorder(highlighted==item.id ? Brand.accent.opacity(0.25):Color.clear,lineWidth:0.5))
                        .contentShape(RoundedRectangle(cornerRadius:7))
                }.buttonStyle(.plain).onHover{if $0{highlighted=item.id}}
                    .accessibilityLabel(item.name+(item==model.source ? "，已选择":""))
            }
        }.padding(.horizontal,8).padding(.bottom,8).frame(width:Brand.width-Brand.inset*2)
            .background(SourceKeyboardBridge{key in
                switch key {
                case 125:move(1)
                case 126:move(-1)
                case 36,76:if let item=model.sources.first(where:{$0.id==highlighted}){select(item)}
                case 53:expanded=false
                default:return false
                }
                return true
            })
    }
    private func move(_ offset:Int){
        guard !model.sources.isEmpty else{return}
        let index=model.sources.firstIndex(where:{$0.id==highlighted}) ?? 0
        highlighted=model.sources[max(0,min(model.sources.count-1,index+offset))].id
    }
    private func select(_ item:AudioSource){model.source=item;expanded=false}
}

// Avoid SwiftUI KeyViewProxy retaining an expired focus target when a nested popover reopens.
private struct SourceKeyboardBridge:NSViewRepresentable {
    let handle:(UInt16)->Bool
    func makeNSView(context:Context)->KeyView{let view=KeyView();view.handle=handle;return view}
    func updateNSView(_ view:KeyView,context:Context){view.handle=handle}
    static func dismantleNSView(_ view:KeyView,coordinator:Void){
        if view.window?.firstResponder === view{view.window?.makeFirstResponder(nil)}
        view.handle=nil
    }
    final class KeyView:NSView {
        var handle:((UInt16)->Bool)?
        override var acceptsFirstResponder:Bool{true}
        override func hitTest(_ point:NSPoint)->NSView?{nil}
        override func viewDidMoveToWindow(){
            super.viewDidMoveToWindow()
            DispatchQueue.main.async{[weak self] in guard let self,let window=self.window else{return};window.makeFirstResponder(self)}
        }
        override func keyDown(with event:NSEvent){if handle?(event.keyCode) != true{super.keyDown(with:event)}}
    }
}

