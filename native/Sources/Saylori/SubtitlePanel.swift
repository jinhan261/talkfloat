import AppKit
import SayloriCore

@MainActor final class SubtitlePanel:NSPanel {
    override var canBecomeKey:Bool{true}
    override var canBecomeMain:Bool{false}
    var dragLocked=false
    private var dragOrigin:NSPoint?
    private var mouseOrigin=NSPoint.zero
    private var resizeOrigin:NSRect?
    private var resizeEdges:CaptionEdges=[]
    override func sendEvent(_ event:NSEvent){
        switch event.type {
        case .leftMouseDown:
            let point=event.locationInWindow
            let tools=NSRect(x:frame.width-144,y:frame.height-42,width:124,height:30)
            let edges=CaptionEdges.hit(point,size:frame.size)
            if !dragLocked,!edges.isEmpty {
                resizeOrigin=frame;resizeEdges=edges;mouseOrigin=convertPoint(toScreen:point);return
            }
            if !dragLocked,!tools.contains(point){
                dragOrigin=frame.origin;mouseOrigin=convertPoint(toScreen:point)
                return
            }
        case .leftMouseDragged:
            if let origin=resizeOrigin {
                let point=convertPoint(toScreen:event.locationInWindow)
                setFrame(resizeEdges.resizing(origin,delta:NSSize(width:point.x-mouseOrigin.x,height:point.y-mouseOrigin.y),minimum:minSize,maximum:maxSize),display:true)
                return
            }
            if let origin=dragOrigin {
                let point=convertPoint(toScreen:event.locationInWindow)
                setFrameOrigin(NSPoint(x:origin.x+point.x-mouseOrigin.x,y:origin.y+point.y-mouseOrigin.y))
                return
            }
        case .leftMouseUp:
            if resizeOrigin != nil {
                resizeOrigin=nil
                UserDefaults.standard.set(NSStringFromPoint(frame.origin),forKey:"captionOrigin")
                UserDefaults.standard.set(NSStringFromSize(frame.size),forKey:"captionSize")
                TestDiagnostics.record("edge-resize",["edges":resizeEdges.rawValue,"frame":NSStringFromRect(frame)])
                return
            }
            if let origin=dragOrigin {
                dragOrigin=nil
                UserDefaults.standard.set(NSStringFromPoint(frame.origin),forKey:"captionOrigin")
                TestDiagnostics.record("content-drag",["moved":origin != frame.origin,"frame":NSStringFromRect(frame)])
                return
            }
        default:break
        }
        // Scroll-wheel events still reach the SwiftUI scroll views. Toolbar clicks
        // and the resize grip keep their normal behavior.
        super.sendEvent(event)
    }
}
