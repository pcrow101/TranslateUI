//
//  TranslationService.swift
//  TranslateUI
//

import Foundation
import Translation

/// Thin wrapper around Apple's on-device Translation framework.
///
/// A `TranslationSession` can only be vended by the `.translationTask`
/// modifier, so this type never creates one: it receives a live session and
/// performs all of the work with it in a single off-actor hop, which keeps the
/// non-`Sendable` session inside one isolation region.
nonisolated struct TranslationService: Sendable {
    static let targetLanguage = Locale.Language(identifier: "en")

    struct Item: Sendable {
        let id: UUID
        let text: String
    }

    /// Whether the language pack for `language` → English is installed,
    /// downloadable, or unavailable.
    func status(for language: SourceLanguage) async -> LanguageAvailability.Status? {
        guard let source = language.localeLanguage else { return nil }
        return await LanguageAvailability().status(from: source, to: Self.targetLanguage)
    }

    /// Downloads any missing assets, then streams translations back as the
    /// framework produces them so the UI can fill in progressively instead of
    /// waiting for the slowest label in the batch.
    ///
    /// - Parameters:
    ///   - items: the labels to translate, each carrying the block id results
    ///     are matched back to.
    ///   - session: a live session vended by `.translationTask`.
    ///   - handler: invoked once per translated label. It hops to whichever
    ///     actor it belongs to, so the caller can update the UI directly.
    /// - Throws: `CancellationError` if the owning view went away, plus
    ///   whatever the Translation framework reports, including a failure to
    ///   download the language assets.
    ///
    /// Deliberately **not** `@concurrent`: the session belongs to the view that
    /// vended it, so all of its work stays on the caller's actor inside the
    /// `.translationTask` closure. Every use is preceded by a cancellation
    /// check, because using a session whose view has gone away is an
    /// uncatchable `fatalError` inside the framework rather than a thrown
    /// error — so it has to be avoided, not handled.
    func streamTranslations(
        _ items: [Item],
        using session: sending TranslationSession,
        handler: @escaping (UUID, String) async -> Void
    ) async throws {
        guard !items.isEmpty else { return }

        try Task.checkCancellation()
        // Triggers the system download prompt the first time a pair is used.
        try await session.prepareTranslation()

        let requests = items.map { item in
            TranslationSession.Request(sourceText: item.text, clientIdentifier: item.id.uuidString)
        }

        try Task.checkCancellation()
        for try await response in session.translate(batch: requests) {
            try Task.checkCancellation()
            guard
                let identifier = response.clientIdentifier,
                let id = UUID(uuidString: identifier)
            else { continue }
            await handler(id, response.targetText)
        }
    }

    /// Convenience wrapper that collects the whole batch, used by tests and
    /// any caller that doesn't need progressive updates.
    func translate(
        _ items: [Item],
        using session: sending TranslationSession
    ) async throws -> [UUID: String] {
        let results = ResultBox()
        try await streamTranslations(items, using: session) { id, text in
            await results.insert(id, text)
        }
        return await results.values
    }
}

/// Collects streamed results without needing an actor hop per lookup.
private actor ResultBox {
    private(set) var values: [UUID: String] = [:]

    func insert(_ id: UUID, _ text: String) {
        values[id] = text
    }
}

extension TranslationStrategy {
    /// The framework's equivalent of the user's quality/latency preference.
    var sessionStrategy: TranslationSession.Strategy {
        switch self {
        case .highFidelity: .highFidelity
        case .lowLatency: .lowLatency
        }
    }
}
