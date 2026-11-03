import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

/// Small-size rendering of the approved TalkFloat mark. The two caption bars
/// and speech tail share one outline across the menu bar and app icon.
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
    /// Deterministic production export of the approved imagegen concept, without
    /// raster lighting or accidental alpha holes. No application/window lifecycle.
    static func writeAppIcon(to url:URL) throws {
        let colorSpace=CGColorSpace(name:CGColorSpace.sRGB)!
        guard let context=CGContext(data:nil,width:1024,height:1024,bitsPerComponent:8,bytesPerRow:0,space:colorSpace,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw CocoaError(.coderInvalidValue)
        }
        context.translateBy(x:0,y:1024);context.scaleBy(x:1,y:-1)
        context.setFillColor(CGColor(colorSpace:colorSpace,components:[38/255,40/255,43/255,1])!)
        context.addPath(CGPath(roundedRect:CGRect(x:100,y:100,width:824,height:824),cornerWidth:184,cornerHeight:184,transform:nil))
        context.fillPath()
        context.translateBy(x:252,y:314);context.scaleBy(x:5.2,y:5.2)
        context.addPath(path)
        context.setFillColor(CGColor(colorSpace:colorSpace,components:[247/255,250/255,248/255,1])!)
        context.fillPath()
        guard let image=context.makeImage(),let destination=CGImageDestinationCreateWithURL(url as CFURL,UTType.png.identifier as CFString,1,nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination,image,nil)
        guard CGImageDestinationFinalize(destination) else{throw CocoaError(.fileWriteUnknown)}
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
