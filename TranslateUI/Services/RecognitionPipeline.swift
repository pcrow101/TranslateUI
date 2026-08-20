//
//  RecognitionPipeline.swift
//  TranslateUI
//

import CoreGraphics
import Foundation

/// Recognition plus language classification, as one off-actor step.
///
/// This is the half of the pipeline that has no UI state at all, so it can be
/// exercised directly in tests with a rendered fixture image.
nonisolated struct RecognitionPipeline: Sendable {
    struct Analysis: Sendable {
        var documentLanguage: SourceLanguage
        var blocks: [TextBlock]
    }

    /// Vision confidence floor for keeping a recognised line.
    var minimumConfidence: Double = 0.3
    /// Longest edge handed to Vision. Zero disables downscaling.
    var maximumDimension: CGFloat = TextRecognitionService.defaultMaximumDimension

    func analyze(_ image: SendableImage) async throws -> Analysis {
        var service = TextRecognitionService()
        service.minimumConfidence = Float(minimumConfidence)
        service.maximumDimension = maximumDimension

        let recognized = try await service.recognizeText(in: image)

        // The document language disambiguates short labels ("Info", "Start")
        // that no per-block detector can classify on their own.
        let detector = LanguageDetector()
        let documentLanguage = await detector.dominantLanguage(for: recognized)
        let classified = await detector.classify(recognized, documentLanguage: documentLanguage)

        return Analysis(documentLanguage: documentLanguage, blocks: classified)
    }
}
