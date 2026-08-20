//
//  ScreenshotDetailView.swift
//  TranslateUI
//

import SwiftUI

/// Shows the selected screenshot in the current display mode and surfaces the
/// pipeline status in a floating Liquid Glass bar.
struct ScreenshotDetailView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ScreenshotStore.self) private var store

    let screenshot: Screenshot
    @Binding var selectedBlockID: TextBlock.ID?
    @Binding var editingBlockID: TextBlock.ID?

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.background.secondary)
            .overlay(alignment: .top) {
                PipelineBannerStack()
            }
            .overlay(alignment: .bottom) {
                statusBar
                    .padding(.bottom, 16)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch settings.displayMode {
        case .overlay:
            canvas(showsTranslations: true)
                .padding(20)

        case .sideBySide:
            HStack(spacing: 16) {
                canvas(showsTranslations: false)
                Divider()
                canvas(showsTranslations: true)
            }
            .padding(20)

        case .list:
            TranslationTable(screenshot: screenshot, selectedBlockID: $selectedBlockID)
        }
    }

    private func canvas(showsTranslations: Bool) -> some View {
        ScreenshotCanvas(
            screenshot: screenshot,
            selectedBlockID: $selectedBlockID,
            editingBlockID: $editingBlockID,
            showsOriginal: settings.showOriginalText,
            isInteractive: true,
            showsTranslations: showsTranslations
        )
    }

    private var statusBar: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                if screenshot.phase.isBusy {
                    ProgressView()
                        .controlSize(.small)
                }

                Label(
                    screenshot.phase.label,
                    systemImage: screenshot.phase.isBusy ? "wand.and.sparkles" : "checkmark.circle"
                )
                .labelStyle(.titleAndIcon)
                .font(.callout)

                Divider().frame(height: 16)

                Text("\(screenshot.blocks.count) lines")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())

                if screenshot.documentLanguage != .unknown {
                    Text(
                        "\(screenshot.documentLanguage.flagSymbol) \(screenshot.documentLanguage.displayName)"
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }

                if settings.useModelRefinement, let reason = UIStringRefiner.unavailableReason {
                    Divider().frame(height: 16)
                    Label(reason, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: .capsule)
        }
        .animation(.smooth, value: screenshot.phase)
    }
}
