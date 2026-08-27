//
//  PrewarmStateTests.swift
//  TranslateUITests
//

import Foundation
import Testing

@testable import TranslateUI

/// Verifies the store's `isPrewarmingModel` flag lifecycle so the pill in
/// `ContentView` shows and clears at the right times.
@Suite("Prewarm state")
@MainActor
struct PrewarmStateTests {

    private func settings(prewarm: Bool = true, refinement: Bool = true) -> AppSettings {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let settings = AppSettings(defaults: defaults)
        settings.prewarmModel = prewarm
        settings.useModelRefinement = refinement
        return settings
    }

    @Test("Flag starts false")
    func flagDefaultsFalse() {
        let store = TestFixtures.store(settings: settings())
        #expect(store.isPrewarmingModel == false)
    }

    @Test("Prewarm sets the flag when Apple Intelligence is available")
    func prewarmSetsFlagWhenAvailable() async {
        // Skip on hosts without Apple Intelligence — the store won't kick off
        // a prewarm window at all, and there's nothing to observe.
        guard UIStringRefiner.isAvailable else { return }

        let store = TestFixtures.store(settings: settings())
        await store.prewarm()
        #expect(store.isPrewarmingModel)
    }

    @Test("Prewarm skips the window when refinement is off")
    func prewarmSkippedWhenRefinementDisabled() async {
        let store = TestFixtures.store(
            settings: settings(prewarm: true, refinement: false)
        )
        await store.prewarm()
        #expect(store.isPrewarmingModel == false)
    }

    @Test("Prewarm skips the window when the user turned prewarming off")
    func prewarmSkippedWhenPrewarmDisabled() async {
        let store = TestFixtures.store(
            settings: settings(prewarm: false, refinement: true)
        )
        await store.prewarm()
        #expect(store.isPrewarmingModel == false)
    }
}
