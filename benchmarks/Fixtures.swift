import CoreGraphics
import CoreText
import Foundation
import ImageIO

func makeFixtures(directory: String) throws {
    for (name, width, height) in [("square", 640, 640), ("portrait", 512, 896), ("landscape", 896, 512)] {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let side = CGFloat(min(width, height)) * 0.15
        let w = CGFloat(width), h = CGFloat(height)
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fillEllipse(in: CGRect(x: w * 0.15, y: h * 0.72, width: side, height: side))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: w * 0.62, y: h * 0.45, width: side, height: side))
        context.setFillColor(CGColor(red: 0, green: 0.6, blue: 0, alpha: 1))
        context.move(to: CGPoint(x: w * 0.35, y: h * 0.22 + side))
        context.addLine(to: CGPoint(x: w * 0.35 - side / 2, y: h * 0.22))
        context.addLine(to: CGPoint(x: w * 0.35 + side / 2, y: h * 0.22))
        context.closePath(); context.fillPath()
        let label = NSAttributedString(string: "MAP 42", attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica-Bold" as CFString, 42, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)])
        context.textPosition = CGPoint(x: w * 0.25, y: h * 0.08)
        CTLineDraw(CTLineCreateWithAttributedString(label), context)
        let url = URL(fileURLWithPath: directory).appendingPathComponent(name + ".png")
        let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        guard CGImageDestinationFinalize(destination) else { throw NSError(domain: "Image encoding", code: 1) }
    }
}
