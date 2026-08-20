//
//  SettingsView.swift
//  TranslateUI
//

import SwiftUI
import Translation

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ScreenshotStore.self) private var store
    @Environment(\.showHelp) private var showHelp

    var body: some View {
        @Bindable var settings = settings

        TabView {
            Form {
                Section {
                    Toggle("Polish labels with Apple Intelligence", isOn: $settings.useModelRefinement)
                    if let reason = UIStringRefiner.unavailableReason {
                        Label(reason, systemImage: "info.circle")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    }
                } header: {
                    Text("Translation")
                } footer: {
                    Text(
                        "Rewrites machine translations using the standard English wording of TV interfaces. Runs on device."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section {
                    Picker("Translation speed", selection: $settings.translationStrategy) {
                        ForEach(TranslationStrategy.allCases) { strategy in
                            Text(strategy.label).tag(strategy)
                        }
                    }
                    .pickerStyle(.inline)
                    Text(settings.translationStrategy.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle("Warm up the model at launch", isOn: $settings.prewarmModel)
                    Text(
                        "Loads Apple Intelligence in the background so the first polished screenshot isn’t the slow one."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } header: {
                    Text("Performance")
                }

                Section("Recognition") {
                    LabeledContent("Minimum confidence") {
                        HStack {
                            Slider(value: $settings.minimumConfidence, in: 0...0.9, step: 0.05)
                                .frame(width: 200)
                            Text(settings.minimumConfidence, format: .percent.precision(.fractionLength(0)))
                                .monospacedDigit()
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                }

                Section("Appearance") {
                    Picker("Default display mode", selection: $settings.displayMode) {
                        ForEach(DisplayMode.allCases) { mode in
                            Label(mode.label, systemImage: mode.symbol).tag(mode)
                        }
                    }
                    Toggle("Always show original text", isOn: $settings.showOriginalText)
                }

                Section("Storage") {
                    Button("Clear Cached Results") {
                        Task { await store.clearCache() }
                    }
                    Text(
                        "Recognition and translation results are cached per image so re-imported screenshots open instantly."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section("Help") {
                    Button("Speed & Quality") { showHelp(HelpContent.ID.performance) }
                    Button("Privacy") { showHelp(HelpContent.ID.privacy) }
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("General", systemImage: "gearshape") }

            GlossarySettingsView()
                .tabItem { Label("Glossary", systemImage: "bookmark") }

            LanguageAvailabilityView()
                .tabItem { Label("Languages", systemImage: "character.bubble") }
        }
        .frame(width: 580, height: 460)
    }
}

/// Shows whether the German → English and Italian → English packs are ready.
private struct LanguageAvailabilityView: View {
    @Environment(\.showHelp) private var showHelp
    @State private var statuses: [SourceLanguage: LanguageAvailability.Status] = [:]

    var body: some View {
        Form {
            Section {
                ForEach([SourceLanguage.german, .italian], id: \.self) { language in
                    LabeledContent {
                        Text(description(for: statuses[language]))
                            .foregroundStyle(.secondary)
                    } label: {
                        Text("\(language.flagSymbol) \(language.displayName) → English")
                    }
                }
            } footer: {
                Text(
                    "Language packs download automatically the first time they’re needed. Manage them in System Settings ▸ General ▸ Language & Region ▸ Translation Languages."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                Button("Languages & Downloads Help") { showHelp(HelpContent.ID.languages) }
            }
        }
        .formStyle(.grouped)
        .task {
            let service = TranslationService()
            for language in [SourceLanguage.german, .italian] {
                statuses[language] = await service.status(for: language)
            }
        }
    }

    private func description(for status: LanguageAvailability.Status?) -> String {
        switch status {
        case .installed: String(localized: "Installed")
        case .supported: String(localized: "Downloads on first use")
        case .unsupported: String(localized: "Not supported")
        case nil: String(localized: "Checking…")
        @unknown default: String(localized: "Unknown")
        }
    }
}
