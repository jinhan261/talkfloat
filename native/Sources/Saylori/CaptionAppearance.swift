import AppKit
import SwiftUI

enum CaptionStyle:String,CaseIterable,Identifiable {
    case glass,dark,light
    var id:String{rawValue}
    var title:String{switch self{case .glass:return "磨砂";case .dark:return "深色";case .light:return "浅色"}}
    var foreground:Color{self == .light ? Color(white:0.12):Color(white:0.96)}
}

struct CaptionBackground:View {
    let style:CaptionStyle
    let opacity:Double
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body:some View {
        ZStack {
            if style == .glass && !reduceTransparency {
                FrostedSurface(opacity:opacity)
                Color.black.opacity(0.70*opacity)
            }else{
                (style == .light ? Color(white:0.98):Color(white:0.115))
                    .opacity(reduceTransparency ? 1:opacity)
            }
        }.allowsHitTesting(false)
    }
}

private struct FrostedSurface:NSViewRepresentable {
    var opacity:Double
    func makeNSView(context:Context)->NSVisualEffectView {
        let view=NSVisualEffectView()
        view.material = .hudWindow;view.blendingMode = .behindWindow;view.state = .active
        view.appearance=NSAppearance(named:.darkAqua)
        return view
    }
    func updateNSView(_ view:NSVisualEffectView,context:Context){view.alphaValue=opacity}
}

// Transparent cursor layer. Window events own resizing; this view never steals controls.
struct CaptionResizeCursors:NSViewRepresentable {
    var locked:Bool
    func makeNSView(context:Context)->ResizeCursorSurface{ResizeCursorSurface()}
    func updateNSView(_ view:ResizeCursorSurface,context:Context){view.locked=locked;view.window?.invalidateCursorRects(for:view)}
    final class ResizeCursorSurface:NSView {
        var locked=false
        override func hitTest(_ point:NSPoint)->NSView?{nil}
        override func resetCursorRects(){
            guard !locked else{return}
            let w=bounds.width,h=bounds.height,c:CGFloat=20,e:CGFloat=7
            if #available(macOS 15,*) {
                addCursorRect(NSRect(x:c,y:0,width:max(0,w-2*c),height:e),cursor:.frameResize(position:.bottom,directions:.all))
                addCursorRect(NSRect(x:c,y:h-e,width:max(0,w-2*c),height:e),cursor:.frameResize(position:.top,directions:.all))
                addCursorRect(NSRect(x:0,y:c,width:e,height:max(0,h-2*c)),cursor:.frameResize(position:.left,directions:.all))
                addCursorRect(NSRect(x:w-e,y:c,width:e,height:max(0,h-2*c)),cursor:.frameResize(position:.right,directions:.all))
                addCursorRect(NSRect(x:0,y:0,width:c,height:c),cursor:.frameResize(position:.bottomLeft,directions:.all))
                addCursorRect(NSRect(x:w-c,y:0,width:c,height:c),cursor:.frameResize(position:.bottomRight,directions:.all))
                addCursorRect(NSRect(x:0,y:h-c,width:c,height:c),cursor:.frameResize(position:.topLeft,directions:.all))
                addCursorRect(NSRect(x:w-c,y:h-c,width:c,height:c),cursor:.frameResize(position:.topRight,directions:.all))
            }else{
                addCursorRect(NSRect(x:0,y:0,width:e,height:h),cursor:.resizeLeftRight)
                addCursorRect(NSRect(x:w-e,y:0,width:e,height:h),cursor:.resizeLeftRight)
                addCursorRect(NSRect(x:0,y:0,width:w,height:e),cursor:.resizeUpDown)
                addCursorRect(NSRect(x:0,y:h-e,width:w,height:e),cursor:.resizeUpDown)
            }
        }
    }
}

struct CaptionTool:View {
    let icon:String
    let label:String
    var active=false
    var ink:Color = .primary
    let action:()->Void
    @State private var hovered=false
    var body:some View {
        Button(action:action){
            Image(systemName:icon).font(.system(size:11,weight:.medium))
                .frame(width:28,height:28)
                .background(ink.opacity(hovered || active ? 0.09:0),in:RoundedRectangle(cornerRadius:6))
        }.buttonStyle(.plain).foregroundStyle(ink.opacity(hovered || active ? 0.95:0.60))
            .help(label).accessibilityLabel(label).onHover{hovered=$0}
    }
}
