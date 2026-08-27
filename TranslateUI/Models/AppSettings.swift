//
//  AppSettings.swift
//  TranslateUI
//

import Foundation
import Observation

enum DisplayMode: String, CaseIterable, Identifiable, Sendable {
    case overlay
    case sideBySide
    case list

    var id: String { rawValue }

    var label: String {
        switch self {
        case .overlay: String(localized: "Overlay")
        case .sideBySide: String(localized: "Side by Side")
        case .list: String(localized: "Text List")
        }
    }

    var symbol: String {
        switch self {
        case .overlay: "rectangle.on.rectangle"
        case .sideBySide: "rectangle.split.2x1"
        case .list: "list.bullet.rectangle"
        }
    }
}

/// How the Translation framework should trade quality against latency.
enum TranslationStrategy: String, CaseIterable, Identifiable, Sendable {
    case highFidelity
    case lowLatency

    var id: String { rawValue }

    var label: String {
        switch self {
        case .highFidelity: String(localized: "Best quality")
        case .lowLatency: String(localized: "Fastest")
        }
    }

    var explanation: String {
        switch self {
        case .highFidelity:
            String(localized: "Highest translation quality. Recommended for long menu descriptions.")
        case .lowLatency:
            String(localized: "Returns labels sooner, which suits short interface strings.")
        }
    }
}

/// User-facing preferences, persisted in `UserDefaults`.
@Observable
final class AppSettings {
    enum Key {
        static let refinement = "settings.useModelRefinement"
        static let displayMode = "settings.displayMode"
        static let showOriginal = "settings.showOriginalText"
        static let minimumConfidence = "settings.minimumConfidence"
        static let translationStrategy = "settings.translationStrategy"
        static let prewarmModel = "settings.prewarmModel"
        static let enableSpanish = "settings.enableSpanish"
        static let restoreRecent = "settings.restoreRecentScreenshots"
        static let copyCaptureToClipboard = "settings.copyCaptureToClipboard"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.useModelRefinement = Self.bool(defaults, Key.refinement, default: true)
        self.displayMode =
            DisplayMode(rawValue: defaults.string(forKey: Key.displayMode) ?? "")
            ?? .overlay
        self.showOriginalText = Self.bool(defaults, Key.showOriginal, default: false)
        self.minimumConfidence = defaults.object(forKey: Key.minimumConfidence) as? Double ?? 0.3
        self.translationStrategy =
            TranslationStrategy(
                rawValue: defaults.string(forKey: Key.translationStrategy) ?? ""
            ) ?? .highFidelity
        self.prewarmModel = Self.bool(defaults, Key.prewarmModel, default: true)
        self.enableSpanish = Self.bool(defaults, Key.enableSpanish, default: false)
        self.restoreRecentScreenshots = Self.bool(defaults, Key.restoreRecent, default: true)
        self.copyCaptureToClipboard = Self.bool(defaults, Key.copyCaptureToClipboard, default: false)
    }

    /// Reads a stored flag, falling back to `fallback` when nothing is set.
    ///
    /// Goes through `bool(forKey:)` rather than casting `object(forKey:)`:
    /// values supplied on the command line (`-settings.useModelRefinement 0`)
    /// arrive as strings, which a direct `as? Bool` cast rejects — so the
    /// override silently did nothing.
    private static func bool(_ defaults: UserDefaults, _ key: String, default fallback: Bool) -> Bool {
        guard defaults.object(forKey: key) != nil else { return fallback }
        return defaults.bool(forKey: key)
    }

    /// Run the Foundation Models polishing pass after translating.
    var useModelRefinement: Bool {
        didSet { defaults.set(useModelRefinement, forKey: Key.refinement) }
    }

    var displayMode: DisplayMode {
        didSet { defaults.set(displayMode.rawValue, forKey: Key.displayMode) }
    }

    /// Show the original German/Italian alongside the translation.
    var showOriginalText: Bool {
        didSet { defaults.set(showOriginalText, forKey: Key.showOriginal) }
    }

    /// Vision confidence floor for keeping a recognised line.
    var minimumConfidence: Double {
        didSet { defaults.set(minimumConfidence, forKey: Key.minimumConfidence) }
    }

    /// Quality/latency trade-off passed to `TranslationSession.Configuration`.
    var translationStrategy: TranslationStrategy {
        didSet { defaults.set(translationStrategy.rawValue, forKey: Key.translationStrategy) }
    }

    /// Warm the on-device model at launch so the first polish isn't slow.
    var prewarmModel: Bool {
        didSet { defaults.set(prewarmModel, forKey: Key.prewarmModel) }
    }

    /// Opt-in Spanish → English translation. Disabled by default because the
    /// core scope of the app is German + Italian streaming-device UIs; enabling
    /// this adds Spanish to Vision recognition, language detection, and the
    /// translation coordinator.
    var enableSpanish: Bool {
        didSet { defaults.set(enableSpanish, forKey: Key.enableSpanish) }
    }

    /// Restore the previous session's sidebar on launch. Users who prefer a
    /// clean slate each time can turn this off in Settings.
    var restoreRecentScreenshots: Bool {
        didSet { defaults.set(restoreRecentScreenshots, forKey: Key.restoreRecent) }
    }

    /// Copy every captured window/area screenshot to the clipboard as well as
    /// importing it. Matches macOS's built-in `screencapture` behaviour so the
    /// image is one paste away from another app.
    var copyCaptureToClipboard: Bool {
        didSet { defaults.set(copyCaptureToClipboard, forKey: Key.copyCaptureToClipboard) }
    }
}
