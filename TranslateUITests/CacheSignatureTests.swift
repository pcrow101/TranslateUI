//
//  CacheSignatureTests.swift
//  TranslateUITests
//

import Foundation
import Testing

@testable import TranslateUI

/// Cached results must never outlive the pipeline that produced them.
@Suite("Cache invalidation")
struct CacheSignatureTests {

    private func makeCache() -> ResultCache {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "CacheTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        return ResultCache(directory: directory)
    }

    private func entry(
        confidence: Double, version: Int = PipelineSignature.currentVersion
    ) -> ResultCache.Entry {
        ResultCache.Entry(
            signature: PipelineSignature(pipelineVersion: version, minimumConfidence: confidence),
            documentLanguage: .german,
            blocks: [TestFixtures.block("Einstellungen", translated: "Settings", state: .translated)]
        )
    }

    @Test("A matching signature returns the cached result")
    func matchingSignatureHits() async {
        let cache = makeCache()
        let signature = PipelineSignature(minimumConfidence: 0.3)
        await cache.store(entry(confidence: 0.3), for: "hash")

        let result = await cache.entry(for: "hash", signature: signature)

        #expect(result?.blocks.first?.sourceText == "Einstellungen")
    }

    @Test("Changing the confidence threshold invalidates the entry")
    func confidenceChangeMisses() async {
        let cache = makeCache()
        await cache.store(entry(confidence: 0.3), for: "hash")

        let result = await cache.entry(for: "hash", signature: PipelineSignature(minimumConfidence: 0.5))

        #expect(result == nil)
    }

    @Test("A stale entry is deleted, not just skipped")
    func staleEntryIsDiscarded() async {
        let cache = makeCache()
        await cache.store(entry(confidence: 0.3), for: "hash")

        _ = await cache.entry(for: "hash", signature: PipelineSignature(minimumConfidence: 0.5))
        // Even asking with the original signature must now miss.
        let result = await cache.entry(for: "hash", signature: PipelineSignature(minimumConfidence: 0.3))

        #expect(result == nil)
    }

    @Test("Bumping the pipeline version invalidates older results")
    func pipelineVersionMisses() async {
        let cache = makeCache()
        await cache.store(entry(confidence: 0.3, version: PipelineSignature.currentVersion - 1), for: "hash")

        let result = await cache.entry(for: "hash", signature: PipelineSignature(minimumConfidence: 0.3))

        #expect(result == nil)
    }

    @Test("Tiny floating point differences still count as a match")
    func toleratesFloatNoise() async {
        let cache = makeCache()
        await cache.store(entry(confidence: 0.3), for: "hash")

        let result = await cache.entry(
            for: "hash",
            signature: PipelineSignature(minimumConfidence: 0.3 + 1e-9)
        )

        #expect(result != nil)
    }

    @Test("The store's signature tracks the confidence setting")
    @MainActor
    func storeSignatureFollowsSettings() {
        let settings = AppSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        settings.minimumConfidence = 0.42
        let store = TestFixtures.store(settings: settings)

        #expect(store.pipelineSignature.minimumConfidence == 0.42)
        #expect(store.pipelineSignature.pipelineVersion == PipelineSignature.currentVersion)
    }
}
