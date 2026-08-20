//
//  Screenshot.swift
//  TranslateUI
//

import CoreGraphics
import Foundation
import Observation

/// One imported screenshot plus everything we learned about it.
@Observable
final class Screenshot: Identifiable {
    enum Phase: Hashable, Sendable {
        case idle
        case recognizing
        case translating
        case refining
        case ready
        case failed(message: String)

        var isBusy: Bool {
            switch self {
            case .recognizing, .translating, .refining: true
            case .idle, .ready, .failed: false
            }
        }

        var label: String {
            switch self {
            case .idle: String(localized: "Queued")
            case .recognizing: String(localized: "Reading text…")
            case .translating: String(localized: "Translating…")
            case .refining: String(localized: "Refining…")
            case .ready: String(localized: "Ready")
            case .failed(let message): message
            }
        }
    }

    let id = UUID()
    let name: String
    let sourceURL: URL?
    /// Stable content hash used as the cache key.
    let contentHash: String
    @ObservationIgnored let image: SendableImage
    let pixelSize: CGSize

    var blocks: [TextBlock] = []
    var phase: Phase = .idle
    /// Dominant language across the whole screen, used to disambiguate short labels.
    var documentLanguage: SourceLanguage = .unknown

    init(loaded: LoadedImage) {
        self.name = loaded.name
        self.sourceURL = loaded.sourceURL
        self.contentHash = loaded.contentHash
        self.image = loaded.image
        self.pixelSize = loaded.image.pixelSize
    }

    var cgImage: CGImage { image.cgImage }

    var translatableBlocks: [TextBlock] {
        blocks.filter(\.sourceLanguage.isTranslatable)
    }

    /// Blocks in this language that are still waiting on a translation.
    func untranslatedBlocks(in language: SourceLanguage) -> [TextBlock] {
        blocks.filter { $0.sourceLanguage == language && $0.needsTranslation }
    }

    func blocks(for language: SourceLanguage) -> [TextBlock] {
        blocks.filter { $0.sourceLanguage == language }
    }

    func update(blockID: TextBlock.ID, _ transform: (inout TextBlock) -> Void) {
        guard let index = blocks.firstIndex(where: { $0.id == blockID }) else { return }
        transform(&blocks[index])
    }

    /// Stores a finished translation for one block.
    func applyTranslation(_ text: String, to blockID: TextBlock.ID) {
        update(blockID: blockID) { block in
            block.translatedText = text
            block.state = .translated
        }
    }

    /// Every block rendered as plain text, in reading order.
    func plainText(showingOriginal: Bool) -> String {
        blocks
            .inReadingOrder
            .map { showingOriginal ? "\($0.sourceText)\t→\t\($0.displayText)" : $0.displayText }
            .joined(separator: "\n")
    }
}
