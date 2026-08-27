//
//  ScreenshotStore.swift
//  TranslateUI
//

import AppKit
import Foundation
import OSLog
import Observation
import Translation

/// Owns the imported screenshots and sequences the
/// recognise → detect → translate → refine → glossary pipeline.
///
/// The individual stages live in their own types (`ScreenshotImporter`,
/// `RecognitionPipeline`, `TranslationCoordinator`, `GlossaryCoordinator`,
/// `AlertCenter`); this class is the façade the views talk to and the place
/// where the *order* of those stages is decided.
@MainActor
@Observable
final class ScreenshotStore {
    private let logger = Logger(subsystem: "com.icloud.TranslateUI", category: "Store")

    private let importer = ScreenshotImporter()
    private let refiner = UIStringRefiner()
    private let translation = TranslationCoordinator()
    private let alertCenter = AlertCenter()
    private let glossaryCoordinator: GlossaryCoordinator
    private let cache: ResultCache
    private let session: SessionStore
    private let settings: AppSettings
    private let screenCapture: any ScreenCapturing

    let glossary: Glossary

    init(
        settings: AppSettings,
        glossary: Glossary = Glossary(),
        cache: ResultCache = .shared,
        session: SessionStore = .shared,
        screenCapture: (any ScreenCapturing)? = nil
    ) {
        self.settings = settings
        self.glossary = glossary
        self.cache = cache
        self.session = session
        self.glossaryCoordinator = GlossaryCoordinator(glossary: glossary)
        self.screenCapture = screenCapture ?? ScreenCaptureService()
    }

    // MARK: - State

    var screenshots: [Screenshot] = []
    var selectionID: Screenshot.ID? {
        didSet {
            guard selectionID != oldValue else { return }
            scheduleSessionSave()
        }
    }
    var isImporting = false
    var errorMessage: String?
    /// True from the moment `prewarm()` kicks off the on-device model until
    /// the first refinement chunk succeeds — or a safety timeout expires,
    /// whichever comes first. Drives a small "Warming Apple Intelligence…"
    /// pill so the user knows why the first polish feels sluggish.
    var isPrewarmingModel = false
    /// Driven by the toolbar button and the File ▸ Open command.
    var showsFileImporter = false
    /// True while `restore()` is repopulating the sidebar. Guards the save
    /// debouncer so restoring doesn't immediately trigger a redundant write.
    private var isRestoring = false

    private var reanalysisTask: Task<Void, Never>?
    private var translationRequestTask: Task<Void, Never>?
    private var sessionSaveTask: Task<Void, Never>?
    private var prewarmTimeoutTask: Task<Void, Never>?

    /// Actionable pipeline problems, shown as banners.
    var alerts: [PipelineAlert] { alertCenter.alerts }

    /// Latest known availability of each translation pair.
    var languageStatuses: [SourceLanguage: LanguageAvailability.Status] { translation.statuses }

    /// Observed by `.translationTask` to vend a live session per language.
    var germanConfiguration: TranslationSession.Configuration? { translation.germanConfiguration }
    var italianConfiguration: TranslationSession.Configuration? { translation.italianConfiguration }
    var spanishConfiguration: TranslationSession.Configuration? { translation.spanishConfiguration }

    var selectedScreenshot: Screenshot? {
        guard let selectionID else { return nil }
        return screenshots.first { $0.id == selectionID }
    }

    var isBusy: Bool {
        isImporting || screenshots.contains { $0.phase.isBusy }
    }

    /// The recognition parameters currently in force; cached results produced
    /// with anything else are discarded.
    var pipelineSignature: PipelineSignature {
        PipelineSignature(minimumConfidence: settings.minimumConfidence)
    }

    private var recognitionPipeline: RecognitionPipeline {
        var pipeline = RecognitionPipeline(minimumConfidence: settings.minimumConfidence)
        if settings.enableSpanish {
            pipeline.enabledOptional = [.spanish]
        }
        return pipeline
    }

    // MARK: - Import

    func importFiles(at urls: [URL]) async {
        guard !ScreenshotImporter.supportedURLs(in: urls).isEmpty else { return }

        isImporting = true
        defer { isImporting = false }

        apply(await importer.load(contentsOf: urls))
    }

    func importImageData(_ data: Data, name: String) async {
        isImporting = true
        defer { isImporting = false }

        apply(await importer.load(data: data, name: name))
    }

    // MARK: - Screen capture

    /// Presents the system window picker and imports the captured window.
    func captureWindow() async {
        await performCapture { try await self.screenCapture.captureWindow() }
    }

    /// Presents the area selection overlay and imports the captured region.
    func captureArea() async {
        await performCapture { try await self.screenCapture.captureArea() }
    }

    private func performCapture(_ operation: () async throws -> LoadedImage?) async {
        isImporting = true
        defer { isImporting = false }

        do {
            guard let image = try await operation() else { return }
            apply(ScreenshotImporter.Outcome(images: [image]))
            // A fresh capture should become the active screenshot — otherwise
            // the user is left looking at whatever was on screen before.
            // `apply` only auto-selects when nothing is selected yet; match by
            // content hash so this also works when the capture deduplicated
            // onto an existing import.
            if let match = screenshots.first(where: { $0.contentHash == image.contentHash }) {
                selectionID = match.id
            }
            // Optional: leave a copy on the pasteboard, matching macOS's
            // built-in screencapture. Toggleable in Settings.
            if settings.copyCaptureToClipboard {
                Pasteboard.write(image.image.cgImage)
            }
            // The overlay/picker deactivates the app; make sure the new
            // screenshot is visible without a Dock click.
            NSApp.activate(ignoringOtherApps: true)
        } catch is ScreenCapturePermissionDenied {
            alertCenter.post(.screenCapturePermissionDenied())
        } catch {
            report(error)
        }
    }

    private func apply(_ outcome: ScreenshotImporter.Outcome) {
        for image in outcome.images {
            add(Screenshot(loaded: image))
        }
        if let failure = outcome.failures.first {
            logger.error("Import failed: \(failure.message, privacy: .public)")
            errorMessage = failure.message
        }
    }

    func remove(_ screenshot: Screenshot) {
        screenshots.removeAll { $0.id == screenshot.id }
        if selectionID == screenshot.id {
            selectionID = screenshots.first?.id
        }
        scheduleSessionSave()
    }

    func removeAll() {
        screenshots.removeAll()
        selectionID = nil
        alertCenter.removeAll()
        scheduleSessionSave()
    }

    private func add(_ screenshot: Screenshot) {
        // Re-select an existing import instead of duplicating it.
        if let existing = screenshots.first(where: { $0.contentHash == screenshot.contentHash }) {
            selectionID = existing.id
            return
        }
        screenshots.append(screenshot)
        selectionID = selectionID ?? screenshot.id
        scheduleSessionSave()
        Task { await analyze(screenshot) }
    }

    // MARK: - Session persistence

    /// Rehydrates the previous session's sidebar. Called once at launch when
    /// `AppSettings.restoreRecentScreenshots` is on. Each restored screenshot
    /// runs `analyze` — which hits `ResultCache` for anything already
    /// recognised, so restored screens usually come back translated and
    /// ready.
    func restoreSession() async {
        guard screenshots.isEmpty else { return }
        isRestoring = true
        defer { isRestoring = false }

        let (restored, selection) = await session.restore()
        for item in restored {
            let screenshot = Screenshot(loaded: item.image, id: item.entry.id)
            screenshots.append(screenshot)
        }
        if let selection, screenshots.contains(where: { $0.id == selection }) {
            selectionID = selection
        } else {
            selectionID = screenshots.first?.id
        }

        // Trigger analysis for each; cache hits are near-instant.
        for screenshot in screenshots {
            Task { await analyze(screenshot) }
        }
    }

    /// Debounced write. Every mutation posts one; the tail wins.
    private func scheduleSessionSave() {
        guard !isRestoring else { return }
        #if DEBUG
        // UI test fixtures shouldn't leak into the persisted session — the
        // next real launch would restore them and confuse the user.
        guard !UITestSupport.isEnabled else { return }
        #endif
        sessionSaveTask?.cancel()
        sessionSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self else { return }
            await self.saveSessionNow()
        }
    }

    private func saveSessionNow() async {
        // Snapshot on the main actor first so nothing crosses without being
        // Sendable.
        let entries: [SessionStore.Entry] = screenshots.map { screenshot in
            SessionStore.Entry(
                id: screenshot.id,
                name: screenshot.name,
                sourceURL: screenshot.sourceURL,
                contentHash: screenshot.contentHash,
                importedAt: Date()
            )
        }
        let selection = selectionID
        let known = await session.knownHashes()

        // Encode any PNGs the store hasn't seen. Happens off-main so we don't
        // stall the UI while re-encoding a fresh 4K capture.
        var newImages: [String: Data] = [:]
        for screenshot in screenshots where !known.contains(screenshot.contentHash) {
            let cgImage = screenshot.cgImage
            let hash = screenshot.contentHash
            let data = await Task.detached { ImageLoader.encodePNG(from: cgImage) }.value
            if let data { newImages[hash] = data }
        }

        await session.save(
            SessionStore.SaveRequest(
                entries: entries,
                selectionID: selection,
                newImages: newImages
            )
        )
    }

    /// Wipes the persisted session. Exposed to Settings.
    func clearRecent() async {
        sessionSaveTask?.cancel()
        await session.clear()
    }

    // MARK: - Recognition

    func analyze(_ screenshot: Screenshot, ignoringCache: Bool = false) async {
        let signature = pipelineSignature

        if !ignoringCache,
            let entry = await cache.entry(for: screenshot.contentHash, signature: signature)
        {
            screenshot.documentLanguage = entry.documentLanguage
            // Revive anything an interrupted run left behind so it is retried
            // rather than replayed as a permanent failure.
            screenshot.blocks = entry.blocks.map { $0.revivedForRetry() }
            applyGlossary(to: screenshot)
            screenshot.phase = .ready
            requestTranslationsSoon()
            return
        }

        if ignoringCache {
            await cache.invalidate(screenshot.contentHash)
        }

        screenshot.phase = .recognizing
        do {
            let analysis = try await recognitionPipeline.analyze(screenshot.image)
            screenshot.documentLanguage = analysis.documentLanguage
            screenshot.blocks = analysis.blocks
            applyGlossary(to: screenshot)

            if screenshot.blocks.contains(where: \.needsTranslation) {
                screenshot.phase = .translating
                requestTranslationsSoon()
            } else {
                screenshot.phase = .ready
                await persist(screenshot)
            }
        } catch {
            screenshot.phase = .failed(message: error.localizedDescription)
            report(error)
        }
    }

    func reanalyzeSelection() async {
        guard let screenshot = selectedScreenshot else { return }
        await analyze(screenshot, ignoringCache: true)
    }

    func reanalyzeAll() async {
        for screenshot in screenshots {
            await analyze(screenshot, ignoringCache: true)
        }
    }

    /// Called when a recognition-affecting setting changes. Debounced so
    /// dragging the confidence slider doesn't restart Vision on every step.
    func recognitionSettingsChanged() {
        guard !screenshots.isEmpty else { return }
        reanalysisTask?.cancel()
        reanalysisTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled, let self else { return }
            await self.reanalyzeAll()
        }
    }

    // MARK: - Translation

    /// Coalesces the burst of requests a multi-file import produces.
    ///
    /// Every screenshot finishes recognition separately, and each one arming a
    /// session would invalidate the previous configuration — cancelling a live
    /// batch and risking use of a session whose view has gone. One short pause
    /// lets the whole batch arm a single session.
    func requestTranslationsSoon() {
        translationRequestTask?.cancel()
        translationRequestTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            await self.requestTranslations()
        }
    }

    /// Checks availability, then arms a session for every language that still
    /// has untranslated blocks.
    func requestTranslations() async {
        for language in TranslationCoordinator.languages(includingSpanish: settings.enableSpanish) {
            let readiness = await translation.prepare(
                language,
                screenshots: screenshots,
                strategy: settings.translationStrategy
            )

            switch readiness {
            case .noWork:
                continue
            case .unsupported:
                alertCenter.post(.languageUnsupported(language))
            case .needsDownload:
                alertCenter.post(.languageNeedsDownload(language))
            case .ready:
                alertCenter.dismiss(id: PipelineAlert.languageNeedsDownload(language).id)
                alertCenter.dismiss(id: PipelineAlert.languageUnsupported(language).id)
            case .busy:
                // A batch is mid-flight. `runTranslation` asks again when it
                // finishes, so the new screenshot is picked up without
                // cancelling the labels already being translated.
                continue
            }
        }
    }

    /// Called from `.translationTask` once a session exists.
    func runTranslation(for language: SourceLanguage, using session: sending TranslationSession) async {
        let result = await translation.run(language, using: session, over: screenshots)

        // Whether or not `run` did work, the pack may now be installed —
        // clear a stale "Download …" banner from the first pass.
        if await translation.refreshStatus(for: language) == .installed {
            alertCenter.dismiss(id: PipelineAlert.languageNeedsDownload(language).id)
        }

        guard result.didRun else { return }

        // Cancelled by a re-arm: the labels went back on the queue, so ask for
        // a fresh session rather than reporting a failure the user can't act on.
        if result.wasCancelled {
            await requestTranslations()
            return
        }

        if result.failureCount > 0 {
            alertCenter.post(.translationsFailed(count: result.failureCount))
        } else {
            alertCenter.dismiss(id: PipelineAlert.translationsFailed(count: 0).id)
        }

        await finish(result.touched)

        // Screenshots that finished recognition while this batch was running
        // were deferred rather than allowed to cancel it. Pick them up now.
        // This terminates: a pass with no pending work arms nothing.
        if translation.takeDeferredRequest(for: language)
            || translation.hasWork(for: language, in: screenshots)
        {
            await requestTranslations()
        }
    }

    /// Runs the post-translation stages for every screenshot that is now complete.
    private func finish(_ touched: Set<Screenshot.ID>) async {
        for screenshot in screenshots where touched.contains(screenshot.id) {
            guard !screenshot.blocks.contains(where: \.needsTranslation) else { continue }
            if settings.useModelRefinement, UIStringRefiner.isAvailable {
                await refine(screenshot)
            }
            applyGlossary(to: screenshot)
            screenshot.phase = .ready
            await persist(screenshot)
        }
    }

    /// Applies a single streamed translation so chips fill in as they arrive.
    func applyTranslation(_ text: String, to blockID: TextBlock.ID, in screenshot: Screenshot?) {
        screenshot?.applyTranslation(text, to: blockID)
    }

    /// Warms the on-device pieces so the first screenshot isn't the slow one.
    func prewarm() async {
        await translation.refreshAvailability()
        guard settings.prewarmModel, settings.useModelRefinement, UIStringRefiner.isAvailable else {
            return
        }
        refiner.prewarm()
        beginPrewarmWindow()
    }

    /// Marks the model as warming for `maxPrewarmSeconds` unless something
    /// else (e.g. the first successful refinement chunk) clears it earlier.
    private func beginPrewarmWindow() {
        isPrewarmingModel = true
        prewarmTimeoutTask?.cancel()
        prewarmTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.maxPrewarmSeconds))
            guard !Task.isCancelled, let self else { return }
            self.finishPrewarmWindow()
        }
    }

    /// Clears the warming flag. Idempotent.
    private func finishPrewarmWindow() {
        prewarmTimeoutTask?.cancel()
        prewarmTimeoutTask = nil
        isPrewarmingModel = false
    }

    /// Fallback ceiling for the "warming" pill so it never sticks forever
    /// if the model is quicker than we expect on the host.
    private static let maxPrewarmSeconds: Int = 12

    /// Resets failed blocks and asks for a fresh session.
    func retryFailedTranslations() async {
        translation.resetFailures(in: screenshots)
        alertCenter.dismiss(id: PipelineAlert.translationsFailed(count: 0).id)
        await requestTranslations()
    }

    func retryTranslation(for blockID: TextBlock.ID, in screenshot: Screenshot) async {
        translation.reset(blockID: blockID, in: screenshot)
        await requestTranslations()
    }

    /// Re-arms the session so `prepareTranslation()` shows the download prompt.
    /// A no-op if the pack is already downloading — that would cancel it.
    func requestLanguageDownload(_ language: SourceLanguage) async {
        let status = await translation.refreshStatus(for: language)
        if status == .installed {
            alertCenter.dismiss(id: PipelineAlert.languageNeedsDownload(language).id)
            return
        }
        // Already downloading: don't re-arm, that would cancel the in-flight
        // `prepareTranslation()`.
        if translation.isRunning(language) || translation.isArmed(language) {
            return
        }
        await requestTranslations()
    }

    func refreshLanguageAvailability() async {
        await translation.refreshAvailability()
    }

    // MARK: - Refinement

    func refineSelection() async {
        guard let screenshot = selectedScreenshot else { return }
        await refine(screenshot)
        applyGlossary(to: screenshot)
        screenshot.phase = .ready
        await persist(screenshot)
    }

    private func refine(_ screenshot: Screenshot) async {
        let items = screenshot.blocks.compactMap { block -> UIStringRefiner.Item? in
            guard block.sourceLanguage.isTranslatable, let translated = block.translatedText else {
                return nil
            }
            return UIStringRefiner.Item(
                id: block.id,
                source: block.sourceText,
                translation: translated,
                sourceLanguage: block.sourceLanguage
            )
        }
        guard !items.isEmpty else { return }

        screenshot.phase = .refining
        // Applied per chunk so polished labels appear while later chunks run.
        _ = await refiner.refine(items, glossary: glossaryCoordinator.examples(for: screenshot)) { chunk in
            // The very first chunk to arrive is proof the model is warm; drop
            // the "warming" pill even if the timeout hasn't expired.
            self.finishPrewarmWindow()
            for (id, text) in chunk {
                screenshot.update(blockID: id) { $0.refinedText = text }
            }
            self.applyGlossary(to: screenshot)
        }
    }

    func clearRefinements() {
        for screenshot in screenshots {
            for block in screenshot.blocks {
                screenshot.update(blockID: block.id) { $0.refinedText = nil }
            }
        }
    }

    // MARK: - Glossary & manual edits

    /// Overrides a translation, optionally teaching it to the glossary so the
    /// same label is translated identically everywhere else.
    func setTranslation(
        _ text: String,
        for blockID: TextBlock.ID,
        in screenshot: Screenshot,
        rememberInGlossary: Bool
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let block = screenshot.blocks.first(where: { $0.id == blockID }) else { return }

        screenshot.update(blockID: blockID) {
            $0.userText = trimmed.isEmpty ? nil : trimmed
            $0.isGlossaryMatch = false
        }

        if rememberInGlossary, !trimmed.isEmpty, block.sourceLanguage.isTranslatable {
            glossary.learn(
                sourceText: block.sourceText,
                language: block.sourceLanguage,
                translation: trimmed
            )
            applyGlossaryToAll()
        }

        Task { await persist(screenshot) }
    }

    /// Drops a manual override and falls back to the machine translation.
    func resetTranslation(for blockID: TextBlock.ID, in screenshot: Screenshot) {
        screenshot.update(blockID: blockID) {
            $0.userText = nil
            $0.isGlossaryMatch = false
        }
        applyGlossary(to: screenshot)
        Task { await persist(screenshot) }
    }

    /// Replays remembered terms onto a screenshot.
    func applyGlossary(to screenshot: Screenshot) {
        glossaryCoordinator.apply(to: screenshot)
    }

    func applyGlossaryToAll() {
        for screenshot in screenshots {
            applyGlossary(to: screenshot)
            Task { await persist(screenshot) }
        }
    }

    func removeGlossaryEntry(_ entry: GlossaryEntry) {
        glossary.remove(entry)
        applyGlossaryToAll()
    }

    // MARK: - Alerts

    func post(_ alert: PipelineAlert) {
        alertCenter.post(alert)
    }

    func dismiss(_ alert: PipelineAlert) {
        alertCenter.dismiss(alert)
    }

    func dismissAlert(id: PipelineAlert.ID) {
        alertCenter.dismiss(id: id)
    }

    func perform(_ action: PipelineAlert.Action) async {
        switch action {
        case .downloadLanguage(let language):
            await requestLanguageDownload(language)
        case .retryFailed:
            await retryFailedTranslations()
        case .reanalyze:
            await reanalyzeAll()
        case .openLanguageSettings:
            if let url = URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension") {
                NSWorkspace.shared.open(url)
            }
        case .openScreenRecordingSettings:
            if let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
            ) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    // MARK: - Persistence

    private func persist(_ screenshot: Screenshot) async {
        // Only cache a finished result. Caching a failed or in-flight label
        // would make the failure permanent for that screenshot.
        guard screenshot.blocks.allSatisfy(\.isSettled) else { return }

        let entry = ResultCache.Entry(
            signature: pipelineSignature,
            documentLanguage: screenshot.documentLanguage,
            blocks: screenshot.blocks
        )
        await cache.store(entry, for: screenshot.contentHash)
    }

    func clearCache() async {
        await cache.removeAll()
    }

    // MARK: - Helpers

    private func report(_ error: Error) {
        logger.error("\(error.localizedDescription, privacy: .public)")
        errorMessage = error.localizedDescription
    }
}
