//
//  SessionStoreTests.swift
//  TranslateUITests
//

import CoreGraphics
import Foundation
import Testing

@testable import TranslateUI

@Suite("Session persistence")
struct SessionStoreTests {

    /// Fresh SessionStore rooted at a throwaway directory so tests never
    /// touch the real Application Support folder.
    private func makeStore() -> (SessionStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appending(
                path: "TranslateUITests-Session-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        return (SessionStore(directory: dir), dir)
    }

    private func pngData(hash: String) -> Data {
        // A one-pixel PNG is enough for round-trip tests — content is opaque
        // to SessionStore, which only reads/writes bytes.
        let bytes = Array("PNG-\(hash)".utf8)
        return Data(bytes)
    }

    private func entry(
        _ name: String,
        hash: String,
        importedAt: Date = Date()
    ) -> SessionStore.Entry {
        SessionStore.Entry(
            id: UUID(),
            name: name,
            sourceURL: nil,
            contentHash: hash,
            importedAt: importedAt
        )
    }

    @Test("A saved manifest round-trips through restore")
    func roundTrip() async throws {
        let (store, _) = makeStore()
        let png = TestImageFactory.pngData(
            from: TestImageFactory.screen(
                lines: ["Alpha"],
                size: CGSize(width: 240, height: 80),
                fontSize: 24
            )!
        )!

        let one = entry("Alpha", hash: "hash-alpha")
        await store.save(
            SessionStore.SaveRequest(
                entries: [one],
                selectionID: one.id,
                newImages: [one.contentHash: png]
            )
        )

        let (restored, selection) = await store.restore()
        #expect(restored.count == 1)
        #expect(restored.first?.entry.name == "Alpha")
        #expect(restored.first?.image.contentHash == "hash-alpha")
        #expect(selection == one.id)
    }

    @Test("Save trims to the configured capacity, oldest first")
    func capacityEviction() async throws {
        let (store, _) = makeStore()
        // A single valid PNG shared by every entry so the test focuses on
        // manifest ordering + orphan sweeping rather than image decoding.
        let sharedPNG = TestImageFactory.pngData(
            from: TestImageFactory.screen(
                lines: ["x"], size: CGSize(width: 80, height: 40), fontSize: 18
            )!
        )!

        var entries: [SessionStore.Entry] = []
        var images: [String: Data] = [:]
        for index in 0..<(SessionStore.capacity + 3) {
            let hash = "hash-\(index)"
            entries.append(entry("Shot \(index)", hash: hash))
            images[hash] = sharedPNG
        }
        await store.save(
            SessionStore.SaveRequest(
                entries: entries, selectionID: entries.last?.id, newImages: images
            )
        )

        // Sanity: manifest was trimmed correctly and PNGs exist for the survivors.
        let liveBefore = await store.knownHashes()
        #expect(liveBefore.count == SessionStore.capacity)

        // Manifest is capped and *keeps the newest*.
        let (restored, _) = await store.restore()
        #expect(restored.count == SessionStore.capacity)
        #expect(restored.first?.entry.name == "Shot 3")
        #expect(restored.last?.entry.name == "Shot \(SessionStore.capacity + 2)")

        // Orphan PNGs are swept — only the surviving hashes remain on disk.
        let live = await store.knownHashes()
        #expect(live.count == SessionStore.capacity)
        #expect(!live.contains("hash-0"))
        #expect(live.contains("hash-\(SessionStore.capacity + 2)"))
    }

    @Test("Two entries sharing a content hash share one PNG file")
    func deduplicatesByHash() async throws {
        let (store, _) = makeStore()
        let png = pngData(hash: "shared")
        let first = entry("First", hash: "shared")
        let second = entry("Second", hash: "shared")
        await store.save(
            SessionStore.SaveRequest(
                entries: [first, second],
                selectionID: second.id,
                newImages: [first.contentHash: png]
            )
        )

        // Removing one entry — the file survives because the other still needs it.
        await store.save(
            SessionStore.SaveRequest(
                entries: [second], selectionID: second.id, newImages: [:]
            )
        )
        var live = await store.knownHashes()
        #expect(live.contains("shared"))

        // Removing the last reference deletes the PNG.
        await store.save(
            SessionStore.SaveRequest(entries: [], selectionID: nil, newImages: [:])
        )
        live = await store.knownHashes()
        #expect(live.isEmpty)
    }

    @Test("Missing images are skipped rather than aborting restore")
    func missingImageIsSkipped() async throws {
        let (store, _) = makeStore()
        let good = entry("Good", hash: "has-file")
        let bad = entry("Ghost", hash: "no-file-here")

        // Only supply the PNG for `good` — `bad` will fail to load.
        await store.save(
            SessionStore.SaveRequest(
                entries: [bad, good],
                selectionID: good.id,
                newImages: [
                    good.contentHash: TestImageFactory.pngData(
                        from: TestImageFactory.screen(
                            lines: ["ok"],
                            size: CGSize(width: 100, height: 60),
                            fontSize: 20
                        )!
                    )!
                ]
            )
        )

        let (restored, _) = await store.restore()
        #expect(restored.count == 1)
        #expect(restored.first?.entry.name == "Good")
    }

    @Test("Clear wipes the manifest and all images")
    func clearWipesEverything() async throws {
        let (store, _) = makeStore()
        let png = pngData(hash: "one")
        let solo = entry("Solo", hash: "one")
        await store.save(
            SessionStore.SaveRequest(
                entries: [solo], selectionID: solo.id, newImages: [solo.contentHash: png]
            )
        )

        await store.clear()

        let (restored, selection) = await store.restore()
        #expect(restored.isEmpty)
        #expect(selection == nil)
        #expect(await store.knownHashes().isEmpty)
    }

    @Test("Restoring a saved session repopulates the store's sidebar")
    @MainActor
    func storeRestoresPreviousSession() async throws {
        // Seed a store that shares a `SessionStore` with the next store,
        // so the second one restores what the first persisted.
        let sessionDir = FileManager.default.temporaryDirectory
            .appending(
                path: "TranslateUITests-Session-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        let shared = SessionStore(directory: sessionDir)

        let first = TestFixtures.store(session: shared)
        let png = TestImageFactory.pngData(
            from: TestImageFactory.screen(
                lines: ["Persist"], size: CGSize(width: 240, height: 80), fontSize: 24
            )!
        )!
        await first.importImageData(png, name: "Persist")

        // Give the debounced save enough time to flush. Generous because the
        // suite runs under heavy parallel load.
        try await Task.sleep(for: .milliseconds(1500))

        // A fresh store, same session directory: expected to rehydrate.
        let second = TestFixtures.store(session: shared)
        #expect(second.screenshots.isEmpty)
        await second.restoreSession()

        #expect(second.screenshots.count == 1)
        #expect(second.screenshots.first?.name == "Persist")
        #expect(second.selectionID == second.screenshots.first?.id)
    }
}
