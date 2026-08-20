//
//  TextRecognitionService.swift
//  TranslateUI
//

import CoreGraphics
import Foundation
import OSLog
import Vision

/// Wraps Vision's text recogniser and turns raw observations into logical
/// `TextBlock` values in image-pixel coordinates.
nonisolated struct TextRecognitionService: Sendable {
    private static let signposter = OSSignposter(
        subsystem: "com.icloud.TranslateUI",
        category: "Recognition"
    )
    private static let logger = Logger(subsystem: "com.icloud.TranslateUI", category: "Recognition")

    /// Downscaling before recognition is **off by default**.
    ///
    /// Reducing a capture makes small interface text smaller still, and Vision
    /// stops reporting labels once they fall below its detection threshold —
    /// exactly the text this app exists to read. Measured 4K recognition is
    /// only ~0.5 s, so there is no problem worth that risk today. The machinery
    /// stays (and is covered by the cache signature) for pathological inputs,
    /// but enabling it needs a benchmark on *real* screenshots: synthetic
    /// fixtures sit near the detection cliff and give unstable numbers.
    static let defaultMaximumDimension: CGFloat = 0

    /// Observations below this confidence are discarded as noise (compression
    /// artefacts on TV captures produce a lot of them).
    var minimumConfidence: Float = 0.3

    /// Longest edge handed to Vision. Zero disables downscaling.
    var maximumDimension: CGFloat = TextRecognitionService.defaultMaximumDimension

    @concurrent
    nonisolated func recognizeText(in image: SendableImage) async throws -> [TextBlock] {
        let state = Self.signposter.beginInterval("recognizeText")
        defer { Self.signposter.endInterval("recognizeText", state) }

        let started = ContinuousClock.now
        let originalSize = image.pixelSize

        // Recognition runs on the (possibly) downscaled copy; every frame is
        // mapped back into original pixel coordinates afterwards.
        let scaled = Self.downscaledIfNeeded(image.cgImage, maximumDimension: maximumDimension)
        let workingImage = scaled ?? image.cgImage
        let workingSize = CGSize(width: workingImage.width, height: workingImage.height)
        let scaleBack = originalSize.width / max(workingSize.width, 1)

        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = SourceLanguage.recognitionIdentifiers
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = true

        let observations = try await request.perform(on: workingImage)

        let blocks: [TextBlock] = observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, candidate.confidence >= minimumConfidence else { return nil }

            let workingFrame = observation.boundingBox.toImageCoordinates(workingSize, origin: .upperLeft)
            let frame = scaleBack == 1 ? workingFrame : workingFrame.scaled(by: scaleBack)
            return TextBlock(
                sourceText: text,
                frame: frame,
                confidence: candidate.confidence,
                backgroundLuminance: Self.averageLuminance(of: workingImage, in: workingFrame)
            )
        }

        let merged = Self.mergeFragmentsOnSameLine(blocks)
        let elapsed = started.duration(to: .now)
        Self.logger.debug(
            """
            Recognised \(merged.count, privacy: .public) blocks from \
            \(Int(originalSize.width), privacy: .public)×\(Int(originalSize.height), privacy: .public) \
            (working \(workingImage.width, privacy: .public)×\(workingImage.height, privacy: .public)) \
            in \(elapsed.milliseconds, privacy: .public) ms
            """
        )
        return merged
    }

    // MARK: - Downscaling

    /// Returns a reduced copy when the image exceeds `maximumDimension`,
    /// or `nil` when the original is already small enough.
    nonisolated static func downscaledIfNeeded(
        _ image: CGImage,
        maximumDimension: CGFloat
    ) -> CGImage? {
        guard maximumDimension > 0 else { return nil }
        let longestEdge = CGFloat(max(image.width, image.height))
        guard longestEdge > maximumDimension else { return nil }

        let ratio = maximumDimension / longestEdge
        let width = Int((CGFloat(image.width) * ratio).rounded())
        let height = Int((CGFloat(image.height) * ratio).rounded())
        guard width > 0, height > 0 else { return nil }

        guard
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return nil }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    // MARK: - Contrast

    /// Average perceived brightness of `rect` in the screenshot, so overlay
    /// chips can choose light or dark text instead of relying on the system
    /// appearance (a TV UI is usually dark even in Light Mode).
    nonisolated static func averageLuminance(of image: CGImage, in rect: CGRect) -> Double {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let cropRect = rect.integral.intersection(bounds)
        guard
            !cropRect.isNull, cropRect.width >= 1, cropRect.height >= 1,
            let crop = image.cropping(to: cropRect)
        else { return 0 }

        var pixel: [UInt8] = [0, 0, 0, 0]
        let success = pixel.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress,
                    width: 1,
                    height: 1,
                    bitsPerComponent: 8,
                    bytesPerRow: 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            else { return false }
            context.interpolationQuality = .medium
            context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard success else { return 0 }

        let red = Double(pixel[0]) / 255
        let green = Double(pixel[1]) / 255
        let blue = Double(pixel[2]) / 255
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    // MARK: - Line assembly

    /// Vision often splits a single menu label into several observations
    /// (e.g. an icon between words). Fragments that share a baseline and sit
    /// close together are merged so they translate as one phrase.
    nonisolated static func mergeFragmentsOnSameLine(_ blocks: [TextBlock]) -> [TextBlock] {
        let sorted = blocks.sorted { lhs, rhs in
            if abs(lhs.frame.midY - rhs.frame.midY) > min(lhs.frame.height, rhs.frame.height) * 0.5 {
                return lhs.frame.midY < rhs.frame.midY
            }
            return lhs.frame.minX < rhs.frame.minX
        }

        var merged: [TextBlock] = []
        for block in sorted {
            guard var previous = merged.last else {
                merged.append(block)
                continue
            }

            let sharesBaseline =
                abs(previous.frame.midY - block.frame.midY)
                < min(previous.frame.height, block.frame.height) * 0.45
            let horizontalGap = block.frame.minX - previous.frame.maxX
            let isAdjacent = horizontalGap >= 0 && horizontalGap < previous.frame.height * 1.2

            guard sharesBaseline, isAdjacent else {
                merged.append(block)
                continue
            }

            previous.sourceText += " " + block.sourceText
            previous.frame = previous.frame.union(block.frame)
            previous.confidence = min(previous.confidence, block.confidence)
            previous.backgroundLuminance = (previous.backgroundLuminance + block.backgroundLuminance) / 2
            merged[merged.count - 1] = previous
        }
        return merged
    }
}
nonisolated

    extension CGRect
{
    fileprivate func scaled(by factor: CGFloat) -> CGRect {
        CGRect(
            x: minX * factor,
            y: minY * factor,
            width: width * factor,
            height: height * factor
        )
    }
}
nonisolated

    extension Duration
{
    /// Whole milliseconds, for logging.
    fileprivate var milliseconds: Int {
        let (seconds, attoseconds) = components
        return Int(seconds * 1000 + attoseconds / 1_000_000_000_000_000)
    }
}
