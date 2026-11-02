import AppKit
import SwiftUI

/// Small-size rendering of the approved TalkFloat mark. The two caption bars
/// and speech tail stay crisp in the menu bar; app artwork is supplied separately.
enum TalkFloatArtwork {
    static let size = CGSize(width: 100, height: 76)
    static var path: CGPath {
        let path = CGMutablePath()
        path.addRoundedRect(in: CGRect(x: 30, y: 0, width: 70, height: 24), cornerWidth: 12, cornerHeight: 12)
        path.addRoundedRect(in: CGRect(x: 0, y: 33, width: 88, height: 28), cornerWidth: 14, cornerHeight: 14)
        path.move(to: CGPoint(x: 47, y: 56))
        path.addLine(to: CGPoint(x: 22, y: 75))
        path.addQuadCurve(to: CGPoint(x: 19, y: 73), control: CGPoint(x: 18, y: 78))
        path.addLine(to: CGPoint(x: 24, y: 56))
        path.closeSubpath()
        return path
    }
    static func menuImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 18), flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.translateBy(x: 1, y: 1)
            context.scaleBy(x: 0.20, y: 0.20)
            context.addPath(path)
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "TalkFloat 实时翻译"
        return image
    }
}

struct TalkFloatMark: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width / TalkFloatArtwork.size.width, rect.height / TalkFloatArtwork.size.height)
        var transform = CGAffineTransform(translationX: rect.midX - TalkFloatArtwork.size.width * scale / 2,
                                         y: rect.midY - TalkFloatArtwork.size.height * scale / 2)
        transform = transform.scaledBy(x: scale, y: scale)
        return Path(TalkFloatArtwork.path.copy(using: &transform)!)
    }
}
