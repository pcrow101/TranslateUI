//
//  ResultCache.swift
//  TranslateUI
//

import Foundation
import OSLog

/// Identifies the recognition pipeline that produced a cached result.
///
/// Anything that changes what recognition returns belongs here: bump
/// `pipelineVersion` when the Vision request or the line-merging heuristic
/// changes, and the confidence threshold travels with each entry so moving the
/// slider invalidates stale results automatically.
nonisolated struct PipelineSignature: Codable, Hashable, Sendable {
    /// Bump when recognition or block assembly changes shape.
    /// 3: recognition runs on a downscaled copy for large captures.
    /// 4: failed/unfinished translations are no longer cached, so existing
    ///    entries may contain permanently-failed labels and must be discarded.
    static let currentVersion = 4

    var pipelineVersion: Int
    var minimumConfidence: Double
    /// Longest edge handed to Vision; changing it changes what is recognised.
    var maximumDimension: Double

    init(
        pipelineVersion: Int = PipelineSignature.currentVersion,
        minimumConfidence: Double,
        maximumDimension: Double = Double(TextRecognitionService.defaultMaximumDimension)
    ) {
        self.pipelineVersion = pipelineVersion
        self.minimumConfidence = minimumConfidence
        self.maximumDimension = maximumDimension
    }

    /// Confidence is compared with a tolerance so float noise doesn't thrash
    /// the cache.
    func matches(_ other: PipelineSignature) -> Bool {
        pipelineVersion == other.pipelineVersion
            && abs(minimumConfidence - other.minimumConfidence) < 0.001
            && maximumDimension == other.maximumDimension
    }
}

/// Caches recognition and translation results per image content hash so a
/// screenshot that is re-imported appears instantly.
actor ResultCache {
    struct Entry: Codable, Sendable {
        var signature: PipelineSignature
        var documentLanguage: SourceLanguage
        var blocks: [TextBlock]
    }

    static let shared = ResultCache()

    private let logger = Logger(subsystem: "com.icloud.TranslateUI", category: "Cache")
    private var memory: [String: Entry] = [:]
    private let directory: URL?

    init(directory: URL? = ResultCache.defaultDirectory()) {
        self.directory = directory
        if let directory {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    static func defaultDirectory() -> URL? {
        let base = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base?.appending(path: "TranslateUI/Cache", directoryHint: .isDirectory)
    }

    /// Returns a cached result only when it was produced by a matching
    /// pipeline; stale entries are discarded so they can be recomputed.
    func entry(for hash: String, signature: PipelineSignature) -> Entry? {
        if let cached = memory[hash] {
            guard cached.signature.matches(signature) else {
                invalidate(hash)
                return nil
            }
            return cached
        }

        guard
            let url = fileURL(for: hash),
            let data = try? Data(contentsOf: url)
        else { return nil }

        guard let entry = try? JSONDecoder().decode(Entry.self, from: data) else {
            // Written by an older build with a different schema.
            invalidate(hash)
            return nil
        }
        guard entry.signature.matches(signature) else {
            invalidate(hash)
            return nil
        }

        memory[hash] = entry
        return entry
    }

    func store(_ entry: Entry, for hash: String) {
        memory[hash] = entry
        guard let url = fileURL(for: hash) else { return }
        do {
            try JSONEncoder().encode(entry).write(to: url, options: .atomic)
        } catch {
            logger.warning("Failed to persist cache entry: \(error.localizedDescription, privacy: .public)")
        }
    }

    func invalidate(_ hash: String) {
        memory.removeValue(forKey: hash)
        guard let url = fileURL(for: hash) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    func removeAll() {
        memory.removeAll()
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func fileURL(for hash: String) -> URL? {
        directory?.appending(path: "\(hash).json")
    }
}
