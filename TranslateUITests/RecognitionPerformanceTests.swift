//
//  RecognitionPerformanceTests.swift
//  TranslateUITests
//

import CoreGraphics
import Foundation
import Testing

@testable import TranslateUI

/// Downscaling must speed recognition up without moving the labels: every
/// frame has to come back in the *original* image's pixel coordinates.
@Suite("Recognition performance")
struct RecognitionPerformanceTests {

    @Test("Images below the cap are left alone")
    func smallImagesAreNotScaled() throws {
        let image = try #require(
            TestImageFactory.screen(lines: ["Klein"], size: CGSize(width: 800, height: 400)))

        let scaled = TextRecognitionService.downscaledIfNeeded(image, maximumDimension: 2560)

        #expect(scaled == nil)
    }

    @Test("Large images are reduced to the cap, keeping their aspect ratio")
    func largeImagesAreScaled() throws {
        let image = try #require(
            TestImageFactory.screen(
                lines: ["Gross"],
                size: CGSize(width: 3840, height: 2160),
                fontSize: 120
            ))

        let scaled = try #require(TextRecognitionService.downscaledIfNeeded(image, maximumDimension: 2560))

        #expect(scaled.width == 2560)
        #expect(scaled.height == 1440)
    }

    @Test("A zero cap disables downscaling")
    func zeroDisablesScaling() throws {
        let image = try #require(
            TestImageFactory.screen(lines: ["Gross"], size: CGSize(width: 4000, height: 2000)))

        #expect(TextRecognitionService.downscaledIfNeeded(image, maximumDimension: 0) == nil)
    }

    @Test("Frames from a downscaled pass land in original image coordinates")
    func framesMapBackToOriginalCoordinates() async throws {
        // 3200px wide: above the 2560 cap, so recognition runs on a reduction.
        let size = CGSize(width: 3200, height: 900)
        let image = try #require(
            TestImageFactory.screen(
                lines: ["Wiedergabe fortsetzen"],
                size: size,
                fontSize: 150
            ))

        var service = TextRecognitionService()
        service.maximumDimension = 2560
        let blocks = try await service.recognizeText(in: SendableImage(cgImage: image))

        #expect(!blocks.isEmpty)
        let bounds = CGRect(origin: .zero, size: size)
        for block in blocks {
            #expect(bounds.contains(block.frame))
        }
        // A label drawn at 150pt must map back to a tall frame in original
        // pixels — proof the scale-back happened.
        let tallest = try #require(blocks.map(\.frame.height).max())
        #expect(tallest > 100)
    }

    @Test("Downscaled and full-resolution passes agree on the text and roughly on position")
    func downscalingPreservesResults() async throws {
        let size = CGSize(width: 3000, height: 800)
        let image = try #require(
            TestImageFactory.screen(
                lines: ["Einstellungen"],
                size: size,
                fontSize: 140
            ))
        let sendable = SendableImage(cgImage: image)

        var scaledService = TextRecognitionService()
        scaledService.maximumDimension = 1500
        var fullService = TextRecognitionService()
        fullService.maximumDimension = 0

        let scaledBlocks = try await scaledService.recognizeText(in: sendable)
        let fullBlocks = try await fullService.recognizeText(in: sendable)

        let scaledText = try #require(scaledBlocks.first?.sourceText)
        let fullText = try #require(fullBlocks.first?.sourceText)
        #expect(scaledText == fullText)

        let scaledFrame = try #require(scaledBlocks.first?.frame)
        let fullFrame = try #require(fullBlocks.first?.frame)
        // Within 2% of the image width is plenty for positioning a chip.
        #expect(abs(scaledFrame.minX - fullFrame.minX) < size.width * 0.02)
        #expect(abs(scaledFrame.minY - fullFrame.minY) < size.height * 0.05)
    }

    @Test("Downscaling is disabled by default")
    func downscalingDisabledByDefault() {
        #expect(TextRecognitionService.defaultMaximumDimension == 0)
        #expect(TextRecognitionService().maximumDimension == 0)
    }

    @Test("The cap is part of the cache signature")
    func capIsPartOfSignature() {
        let a = PipelineSignature(minimumConfidence: 0.3, maximumDimension: 2560)
        let b = PipelineSignature(minimumConfidence: 0.3, maximumDimension: 1500)

        #expect(!a.matches(b))
        #expect(a.matches(PipelineSignature(minimumConfidence: 0.3, maximumDimension: 2560)))
    }
}
