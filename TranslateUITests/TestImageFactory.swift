//  TestImageFactory.swift
//  TranslateUITests
//

import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Renders a synthetic "TV interface" screen for tests.
enum TestImageFactory {
    static func screen(
        lines: [String],
        size: CGSize = CGSize(width: 900, height: 500),
        fontSize: CGFloat = 46
    ) -> CGImage? {
        guard
            let context = CGContext(
                data: nil,
                width: Int(size.width),
                height: Int(size.height),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return nil }

        context.setFillColor(CGColor(red: 0.06, green: 0.06, blue: 0.08, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))

        let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        // Space the lines so they always fit the canvas: a fixed multiple of
        // the font size silently pushed later lines off the image, which made
        // fixtures look like recognition failures.
        let topMargin = fontSize * 1.6
        let usableHeight = size.height - topMargin - fontSize * 0.8
        let spacing = min(fontSize * 2.4, usableHeight / CGFloat(max(lines.count - 1, 1)))
        for (index, line) in lines.enumerated() {
            let attributed = NSAttributedString(
                string: line,
                attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): font,
                    NSAttributedString.Key(kCTForegroundColorAttributeName as String):
                        CGColor(red: 1, green: 1, blue: 1, alpha: 1)
                ]
            )
            let ctLine = CTLineCreateWithAttributedString(attributed)
            // Core Graphics uses a bottom-left origin when drawing.
            context.textPosition = CGPoint(
                x: 80,
                y: size.height - topMargin - CGFloat(index) * spacing
            )
            CTLineDraw(ctLine, context)
        }

        return context.makeImage()
    }

    /// Encodes a rendered image as PNG, for tests that need real files on disk.
    static func pngData(from image: CGImage) -> Data? {
        let data = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                data as CFMutableData,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// A synthetic German TV screen written to a real PNG file.
    static func writeScreen(
        lines: [String],
        to url: URL,
        size: CGSize = CGSize(width: 900, height: 500),
        fontSize: CGFloat = 46
    ) throws {
        guard let image = screen(lines: lines, size: size, fontSize: fontSize),
            let data = pngData(from: image)
        else {
            struct RenderFailure: Error {}
            throw RenderFailure()
        }
        try data.write(to: url)
    }
}
