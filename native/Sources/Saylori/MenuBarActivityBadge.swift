import AppKit

/// The logo remains a native template image. A separate, click-through badge
/// communicates live translation without recoloring that image or moving it.
final class MenuBarActivityBadge:NSView {
    override var isOpaque:Bool{false}
    override func hitTest(_ point:NSPoint)->NSView?{nil}
    override func draw(_ dirtyRect:NSRect){
        let circle=NSBezierPath(ovalIn:NSRect(x:bounds.midX+5.5,y:bounds.midY-7.5,width:6,height:6))
        NSColor.systemBlue.setFill();circle.fill()
        NSColor.white.withAlphaComponent(0.9).setStroke();circle.lineWidth=0.75;circle.stroke()
    }
}
