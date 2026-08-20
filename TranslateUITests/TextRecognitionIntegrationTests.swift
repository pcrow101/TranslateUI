//
//  TextRecognitionIntegrationTests.swift
//  TranslateUITests
//

import CoreGraphics
import Foundation
import Testing

@testable import TranslateUI

/// Renders a synthetic "TV interface" and runs the real Vision pipeline over
/// it, which validates the request configuration and the normalised-rect to
/// image-pixel conversion.
@Suite("Vision integration")
struct TextRecognitionIntegrationTests {

    @Test("Recognises rendered German UI labels and maps them to pixel frames")
    func recognizesRenderedLabels() async throws {
        let lines = ["Einstellungen", "Wiedergabe fortsetzen", "Untertitel und Audio"]
        let image = try #require(TestImageFactory.screen(lines: lines))

        let blocks = try await TextRecognitionService()
            .recognizeText(in: SendableImage(cgImage: image))

        #expect(blocks.count >= lines.count)

        let recognised = blocks.map(\.sourceText).joined(separator: " ")
        #expect(recognised.contains("Einstellungen"))

        // Frames must land inside the image, using a top-left origin.
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        for block in blocks {
            #expect(bounds.contains(block.frame))
        }

        // The first label is drawn above the others, so it sorts first.
        let topBlock = try #require(blocks.min(by: { $0.frame.minY < $1.frame.minY }))
        #expect(topBlock.sourceText.contains("Einstellungen"))
    }
}
