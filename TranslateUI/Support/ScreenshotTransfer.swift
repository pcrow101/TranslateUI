//
//  ScreenshotTransfer.swift
//  TranslateUI
//

import CoreGraphics
import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// A drag payload for a screenshot: PNG bytes and a sensible file name.
///
/// Adopting `Transferable` lets us hand a `Screenshot` to
/// `.draggable(_:)` and have SwiftUI negotiate the item provider with the
/// destination — Finder receives a `.png` file, Mail/Messages attach the
/// image, other Mac apps (Preview, Notes) accept the picture directly.
///
/// The value carries the encoded bytes rather than the `CGImage` so it's
/// `Sendable` and cheap to pass across the concurrency boundary the drag
/// coordinator crosses.
nonisolated struct ScreenshotTransfer: Transferable, Sendable {
    let name: String
    let pngData: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { transfer in
            transfer.pngData
        }
        .suggestedFileName { "\($0.name).png" }
    }

    /// Encodes `screenshot.cgImage` to PNG and packages the result for a
    /// drag. Returns `nil` if encoding fails — callers should skip the drag
    /// rather than transfer empty bytes.
    @MainActor
    static func make(from screenshot: Screenshot) -> ScreenshotTransfer? {
        guard let data = ImageLoader.encodePNG(from: screenshot.cgImage) else {
            return nil
        }
        return ScreenshotTransfer(name: screenshot.name, pngData: data)
    }
}
