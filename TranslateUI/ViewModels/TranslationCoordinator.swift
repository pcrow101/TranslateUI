//
//  TranslationCoordinator.swift
//  TranslateUI
//

import Foundation
import OSLog
import Observation
import Translation

/// Runs the translation stage: availability, session configuration, and the
/// per-block bookkeeping of a streamed batch.
///
/// `TranslationSession` can only be vended by the `.translationTask` modifier,
/// so this type never creates one. It manages the *configurations* that drive
/// those modifiers — creating one arms the task, invalidating one re-arms it —
/// and it takes the screenshots to work on as parameters, so it owns no
/// application state and can be reasoned about on its own.
@MainActor
@Observable
final class TranslationCoordinator {
    /// The languages this app translates from.
    static let languages: [SourceLanguage] = [.german, .italian]

    private static let logger = Logger(subsystem: "com.icloud.TranslateUI", category: "Translation")

    private let service = TranslationService()

    /// What happened when we tried to arm a language.
    enum Readiness: Equatable {
        /// Nothing is waiting on this language.
        case noWork
        /// Session armed; assets are already installed.
        case ready
        /// Armed, but the language pack still has to download.
        case needsDownload
        /// This pair can't be translated on this device.
        case unsupported
        /// A batch is already in flight; another pass is queued for when it
        /// finishes. Re-arming now would cancel the running session.
        case busy
    }

    /// The outcome of one streamed batch.
    struct RunResult: Equatable {
        var touched: Set<Screenshot.ID> = []
        var failureCount = 0
        /// True when a re-arm cancelled this batch. The unfinished work has
        /// been put back on the queue rather than marked failed.
        var wasCancelled = false

        var didRun: Bool { !touched.isEmpty }
    }

    /// A block waiting on a translation, and the screenshot it belongs to.
    private struct PendingTranslation {
        let screenshot: Screenshot
        let blockID: TextBlock.ID
        let text: String
    }

    /// Latest known availability of each translation pair.
    private(set) var statuses: [SourceLanguage: LanguageAvailability.Status] = [:]

    /// One configuration per source language, observed by `.translationTask`.
    var germanConfiguration: TranslationSession.Configuration?
    var italianConfiguration: TranslationSession.Configuration?

    /// Languages with a batch currently in flight.
    private var runningLanguages: Set<SourceLanguage> = []
    /// Languages whose configuration is armed but whose `.translationTask`
    /// hasn't started running yet. Re-arming during this window would cancel
    /// the not-yet-started session and, when the pack is downloading, kick off
    /// an infinite arm/cancel loop.
    private var armedLanguages: Set<SourceLanguage> = []
    /// Languages that asked for a session while one was already running.
    private var deferredLanguages: Set<SourceLanguage> = []

    // MARK: - Availability

    func refreshAvailability() async {
        for language in Self.languages {
            statuses[language] = await service.status(for: language)
        }
    }

    @discardableResult
    func refreshStatus(for language: SourceLanguage) async -> LanguageAvailability.Status? {
        let status = await service.status(for: language)
        statuses[language] = status
        return status
    }

    // MARK: - Arming

    /// Checks availability and, when translatable work exists, arms the
    /// session for `language`.
    func prepare(
        _ language: SourceLanguage,
        screenshots: [Screenshot],
        strategy: TranslationStrategy
    ) async -> Readiness {
        guard hasWork(for: language, in: screenshots), language.localeLanguage != nil else {
            return .noWork
        }

        // Re-arming mid-batch invalidates the configuration, which cancels the
        // running session and abandons every label it hadn't returned yet.
        // The same is true in the window between arming and the session
        // actually starting — critical while a language pack is downloading,
        // because otherwise each new screenshot cancels the download and
        // triggers an infinite arm/cancel loop.
        if runningLanguages.contains(language) || armedLanguages.contains(language) {
            deferredLanguages.insert(language)
            return .busy
        }

        switch await refreshStatus(for: language) {
        case .unsupported:
            markUnsupported(language, in: screenshots)
            return .unsupported
        case .supported:
            // Not installed yet: `prepareTranslation()` inside the session
            // triggers the system download prompt.
            arm(language, strategy: strategy)
            armedLanguages.insert(language)
            return .needsDownload
        default:
            arm(language, strategy: strategy)
            armedLanguages.insert(language)
            return .ready
        }
    }

    /// Creates the configuration for `language`, or invalidates the existing
    /// one so `.translationTask` runs again with the same parameters.
    private func arm(_ language: SourceLanguage, strategy: TranslationStrategy) {
        guard let source = language.localeLanguage else { return }

        let configuration = TranslationSession.Configuration(
            source: source,
            target: TranslationService.targetLanguage,
            preferredStrategy: strategy.sessionStrategy
        )

        switch language {
        case .german:
            if germanConfiguration == nil {
                germanConfiguration = configuration
            } else {
                germanConfiguration?.invalidate()
            }
        case .italian:
            if italianConfiguration == nil {
                italianConfiguration = configuration
            } else {
                italianConfiguration?.invalidate()
            }
        default:
            break
        }
    }

    // MARK: - Running

    /// Streams a batch for `language`, applying each result as it arrives so
    /// chips fill in progressively.
    func run(
        _ language: SourceLanguage,
        using session: sending TranslationSession,
        over screenshots: [Screenshot]
    ) async -> RunResult {
        // Claimed before the early return below so the in-flight flag is
        // always balanced by the `defer`.
        beginRun(language)
        defer { endRun(language) }

        let pending: [PendingTranslation] = screenshots.flatMap { screenshot in
            screenshot.untranslatedBlocks(in: language).map {
                PendingTranslation(screenshot: screenshot, blockID: $0.id, text: $0.sourceText)
            }
        }
        guard !pending.isEmpty else { return RunResult() }

        // The session belongs to the view that vended it. If that view has
        // already gone away, touching the session is an uncatchable
        // `fatalError` inside the framework, so bail out before claiming any
        // work.
        if Task.isCancelled {
            return RunResult(wasCancelled: true)
        }

        for item in pending {
            item.screenshot.phase = .translating
            item.screenshot.update(blockID: item.blockID) { $0.state = .translating }
        }

        // Where each block lives, so streamed results can be applied one by one.
        let owners = Dictionary(
            pending.map { ($0.blockID, $0.screenshot) },
            uniquingKeysWith: { first, _ in first }
        )

        var result = RunResult(touched: Set(pending.map(\.screenshot.id)))

        do {
            try await service.streamTranslations(
                pending.map { TranslationService.Item(id: $0.blockID, text: $0.text) },
                using: session
            ) { blockID, text in
                await MainActor.run {
                    owners[blockID]?.applyTranslation(text, to: blockID)
                }
            }

            if Task.isCancelled {
                result.wasCancelled = true
                returnUnfinishedWork(for: language, in: screenshots)
            } else {
                // Anything still marked `.translating` never came back.
                result.failureCount = markOutstandingAsFailed(
                    pending,
                    message: String(localized: "No translation returned")
                )
                statuses[language] = .installed
            }
        } catch {
            // A cancellation is not a failure: it means a newly imported
            // screenshot re-armed the session. Put the unfinished labels back
            // on the queue, because `.failed` blocks are never picked up by a
            // later pass and would stay silently untranslated.
            if Task.isCancelled || error is CancellationError {
                result.wasCancelled = true
                returnUnfinishedWork(for: language, in: screenshots)
            } else {
                // Results that already streamed in are kept; only the rest fail.
                result.failureCount = markOutstandingAsFailed(
                    pending,
                    message: error.localizedDescription
                )
                Self.logger.error("Translation failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        return result
    }

    // MARK: - In-flight bookkeeping

    /// Whether a batch for `language` is currently running.
    func isRunning(_ language: SourceLanguage) -> Bool {
        runningLanguages.contains(language)
    }

    /// Whether `language` has been armed but its `.translationTask` hasn't
    /// started yet — the download window, during which re-arming would cancel.
    func isArmed(_ language: SourceLanguage) -> Bool {
        armedLanguages.contains(language)
    }

    /// Whether any screenshot still has untranslated blocks in `language`.
    func hasWork(for language: SourceLanguage, in screenshots: [Screenshot]) -> Bool {
        screenshots.contains { !$0.untranslatedBlocks(in: language).isEmpty }
    }

    /// Consumes the "another pass was requested while we were busy" flag.
    func takeDeferredRequest(for language: SourceLanguage) -> Bool {
        deferredLanguages.remove(language) != nil
    }

    /// Seam used by `run` — and by tests, which can't vend a real session.
    func beginRun(_ language: SourceLanguage) {
        runningLanguages.insert(language)
        armedLanguages.remove(language)
    }

    func endRun(_ language: SourceLanguage) {
        runningLanguages.remove(language)
        armedLanguages.remove(language)
    }

    /// Returns every half-finished label for `language` to `.pending` so the
    /// next pass retries it.
    ///
    /// Only `run` ever sets `.translating`, so anything still in that state
    /// belongs to the batch being abandoned.
    @discardableResult
    func returnUnfinishedWork(for language: SourceLanguage, in screenshots: [Screenshot]) -> Int {
        var count = 0
        for screenshot in screenshots {
            for block in screenshot.blocks(for: language) where block.state == .translating {
                count += 1
                screenshot.update(blockID: block.id) { $0.state = .pending }
            }
        }
        return count
    }

    /// Marks every block that is still awaiting a result as failed and returns
    /// how many there were.
    private func markOutstandingAsFailed(_ pending: [PendingTranslation], message: String) -> Int {
        var count = 0
        for item in pending {
            guard let block = item.screenshot.blocks.first(where: { $0.id == item.blockID }),
                block.state == .translating
            else { continue }
            count += 1
            item.screenshot.update(blockID: item.blockID) { $0.state = .failed(message: message) }
        }
        return count
    }

    /// Flags blocks the device simply can't translate, so they don't sit in
    /// `.pending` for ever with no explanation.
    private func markUnsupported(_ language: SourceLanguage, in screenshots: [Screenshot]) {
        let reason = String(localized: "\(language.displayName) → English isn’t available")
        for screenshot in screenshots {
            for block in screenshot.untranslatedBlocks(in: language) {
                screenshot.update(blockID: block.id) { $0.state = .skipped(reason: reason) }
            }
            if screenshot.phase.isBusy {
                screenshot.phase = .ready
            }
        }
    }

    // MARK: - Retrying

    /// Clears failed blocks so the next pass picks them up again.
    func resetFailures(in screenshots: [Screenshot]) {
        for screenshot in screenshots {
            for block in screenshot.blocks where block.canRetry {
                screenshot.update(blockID: block.id) {
                    $0.state = .pending
                    $0.translatedText = nil
                }
            }
        }
    }

    func reset(blockID: TextBlock.ID, in screenshot: Screenshot) {
        screenshot.update(blockID: blockID) {
            $0.state = .pending
            $0.translatedText = nil
        }
    }
}
