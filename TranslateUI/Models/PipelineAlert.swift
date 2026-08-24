//
//  PipelineAlert.swift
//  TranslateUI
//

import Foundation

/// An actionable problem with the recognise → translate pipeline, shown as a
/// banner above the screenshot rather than as a modal alert.
nonisolated struct PipelineAlert: Identifiable, Hashable, Sendable {
    enum Severity: Hashable, Sendable {
        case info
        case warning
        case error
    }

    enum Action: Hashable, Sendable {
        /// Re-arm the translation session so the system download prompt appears.
        case downloadLanguage(SourceLanguage)
        /// Reset failed blocks and translate them again.
        case retryFailed
        /// Re-run recognition with the current settings.
        case reanalyze
        /// Open Language & Region in System Settings.
        case openLanguageSettings
        /// Open Privacy ▸ Screen Recording in System Settings.
        case openScreenRecordingSettings

        var title: String {
            switch self {
            case .downloadLanguage(let language):
                String(localized: "Download \(language.displayName)")
            case .retryFailed:
                String(localized: "Try Again")
            case .reanalyze:
                String(localized: "Re-analyze")
            case .openLanguageSettings:
                String(localized: "Open Settings")
            case .openScreenRecordingSettings:
                String(localized: "Open Settings")
            }
        }
    }

    let id: String
    var severity: Severity
    var title: String
    var message: String
    var symbol: String
    var actions: [Action]
    /// The help topic that explains this situation in more detail.
    var helpTopic: String

    // MARK: - Factories

    static func languageUnsupported(_ language: SourceLanguage) -> PipelineAlert {
        PipelineAlert(
            id: "unsupported-\(language.rawValue)",
            severity: .error,
            title: String(localized: "\(language.displayName) can’t be translated"),
            message: String(
                localized: "This Mac doesn’t support translating \(language.displayName) to English."),
            symbol: "exclamationmark.triangle.fill",
            actions: [.openLanguageSettings],
            helpTopic: HelpContent.ID.languages
        )
    }

    static func languageNeedsDownload(_ language: SourceLanguage) -> PipelineAlert {
        PipelineAlert(
            id: "download-\(language.rawValue)",
            severity: .info,
            title: String(localized: "\(language.displayName) needs downloading"),
            message: String(
                localized:
                    "macOS will ask permission to download the \(language.displayName) → English language pack. Translation continues once it finishes."
            ),
            symbol: "arrow.down.circle",
            actions: [.downloadLanguage(language), .openLanguageSettings],
            helpTopic: HelpContent.ID.languages
        )
    }

    static func translationsFailed(count: Int) -> PipelineAlert {
        PipelineAlert(
            id: "translation-failed",
            severity: .warning,
            title: String(localized: "\(count) labels couldn’t be translated"),
            message: String(localized: "The translation session ended early. Retrying usually clears this."),
            symbol: "exclamationmark.arrow.triangle.2.circlepath",
            actions: [.retryFailed],
            helpTopic: HelpContent.ID.troubleshooting
        )
    }

    static func screenCapturePermissionDenied() -> PipelineAlert {
        PipelineAlert(
            id: "screen-capture-denied",
            severity: .error,
            title: String(localized: "Screen recording isn’t allowed"),
            message: String(
                localized:
                    "Turn on Screen Recording for Translate UI in System Settings, then try capturing again."
            ),
            symbol: "lock.slash",
            actions: [.openScreenRecordingSettings],
            helpTopic: HelpContent.ID.capturing
        )
    }

}
