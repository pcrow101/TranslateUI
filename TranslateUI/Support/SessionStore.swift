//
//  SessionStore.swift
//  TranslateUI
//

import Foundation
import ImageIO
import OSLog
import UniformTypeIdentifiers

/// Persists the currently-open sidebar between launches.
///
/// The manifest keeps only the identity of each imported screenshot (id, name,
/// content hash, source URL, import time). Image bytes are re-encoded to PNG
/// and stored alongside so captures — which have no source file — can survive a
/// quit. Recognition and translation results are **not** duplicated here: they
/// stay in `ResultCache` keyed by the same content hash, so a restored
/// screenshot picks up its finished blocks on the next `analyze()` call
/// without re-running Vision or Translation.
actor SessionStore {
    /// One remembered screenshot.
    nonisolated struct Entry: Codable, Sendable, Hashable {
        var id: UUID
        var name: String
        var sourceURL: URL?
        var contentHash: String
        var importedAt: Date
    }

    /// On-disk manifest.
    nonisolated struct Manifest: Codable, Sendable {
        var entries: [Entry] = []
        var selectionID: UUID?
    }

    /// A screenshot fully rehydrated for the main actor to consume.
    nonisolated struct RestoredScreenshot: Sendable {
        var entry: Entry
        var image: LoadedImage
    }

    /// A save request — metadata for every screenshot to keep, plus PNG data
    /// for any hash not already on disk.
    nonisolated struct SaveRequest: Sendable {
        var entries: [Entry]
        var selectionID: UUID?
        /// Keyed by content hash. Only hashes the caller believes are new need
        /// entries here; anything already on disk is preserved.
        var newImages: [String: Data]
    }

    /// How many screenshots we remember. Anything older is dropped and its
    /// PNG (if no surviving entry still references it) is deleted.
    static let capacity = 25

    static let shared = SessionStore()

    private let logger = Logger(subsystem: "com.icloud.TranslateUI", category: "Session")
    private let directory: URL?

    init(directory: URL? = SessionStore.defaultDirectory()) {
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
        return base?.appending(path: "TranslateUI/Session", directoryHint: .isDirectory)
    }

    // MARK: - Restore

    /// Rehydrates the previous session. Entries whose PNG is missing or
    /// unreadable are skipped rather than aborting the whole restore — the
    /// user still gets whatever survived.
    func restore() async -> (screenshots: [RestoredScreenshot], selectionID: UUID?) {
        guard let manifest = readManifest() else { return ([], nil) }

        var restored: [RestoredScreenshot] = []
        for entry in manifest.entries {
            guard
                let url = imageURL(for: entry.contentHash),
                let data = try? Data(contentsOf: url, options: [.mappedIfSafe])
            else {
                logger.warning("Session entry \(entry.id.uuidString) missing image; skipping")
                continue
            }
            do {
                var loaded = try await ImageLoader.load(data: data, name: entry.name)
                // Preserve the recorded hash even if the fresh decode round-
                // tripped to a byte-identical form; keeps the ResultCache key
                // stable across launches.
                loaded = LoadedImage(
                    name: loaded.name,
                    sourceURL: entry.sourceURL,
                    contentHash: entry.contentHash,
                    image: loaded.image
                )
                restored.append(RestoredScreenshot(entry: entry, image: loaded))
            } catch {
                logger.warning(
                    "Session entry \(entry.id.uuidString) failed to decode: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
        return (restored, manifest.selectionID)
    }

    // MARK: - Save

    /// Writes a new manifest and any newly-added images, then prunes to
    /// `capacity` entries and garbage-collects orphan PNGs.
    func save(_ request: SaveRequest) {
        guard let directory else { return }

        // Cap oldest-first. `entries` arrives in display order, so we trim
        // from the *front* — the user's most recent imports are at the end.
        var entries = request.entries
        if entries.count > Self.capacity {
            entries.removeFirst(entries.count - Self.capacity)
        }

        // Persist any new images the caller supplied.
        for (hash, data) in request.newImages {
            let url = directory.appending(path: "\(hash).png")
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                logger.warning(
                    "Failed to write session image \(hash): \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        // Write the manifest atomically so a crash never leaves a torn file.
        let manifest = Manifest(
            entries: entries,
            selectionID: entries.map(\.id).contains(request.selectionID ?? UUID())
                ? request.selectionID : entries.last?.id
        )
        writeManifest(manifest)

        // Sweep orphan images the manifest no longer references.
        let liveHashes = Set(entries.map(\.contentHash))
        collectOrphans(keeping: liveHashes)
    }

    /// Reports which hashes already have a PNG on disk. Lets the caller avoid
    /// re-encoding every restored screenshot on every save.
    func knownHashes() -> Set<String> {
        guard let directory else { return [] }
        let contents =
            (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return Set(
            contents
                .filter { $0.hasSuffix(".png") }
                .map { String($0.dropLast(4)) }
        )
    }

    // MARK: - Clear

    func clear() {
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: - Private

    private var manifestURL: URL? {
        directory?.appending(path: "session.json")
    }

    private func imageURL(for hash: String) -> URL? {
        directory?.appending(path: "\(hash).png")
    }

    private func readManifest() -> Manifest? {
        guard
            let url = manifestURL,
            let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(Manifest.self, from: data)
    }

    private func writeManifest(_ manifest: Manifest) {
        guard let url = manifestURL else { return }
        do {
            let data = try JSONEncoder().encode(manifest)
            try data.write(to: url, options: .atomic)
        } catch {
            logger.warning(
                "Failed to write session manifest: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func collectOrphans(keeping liveHashes: Set<String>) {
        guard let directory else { return }
        let contents =
            (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in contents where name.hasSuffix(".png") {
            let hash = String(name.dropLast(4))
            if !liveHashes.contains(hash) {
                let url = directory.appending(path: name)
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}
