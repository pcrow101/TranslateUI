//
//  PipelineBanner.swift
//  TranslateUI
//

import SwiftUI

/// Actionable pipeline problems (missing language packs, failed translations)
/// shown above the screenshot instead of as blocking alerts.
struct PipelineBanner: View {
    @Environment(ScreenshotStore.self) private var store

    let alert: PipelineAlert

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: alert.symbol)
                .foregroundStyle(tint)
                .font(.title3)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(alert.title)
                    .font(.callout.weight(.semibold))
                Text(alert.message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            if let primary = alert.actions.first {
                Button(primary.title) {
                    Task { await store.perform(primary) }
                }
                .buttonStyle(.glassProminent)
            }

            ForEach(Array(alert.actions.dropFirst().enumerated()), id: \.offset) { _, action in
                Button(action.title) {
                    Task { await store.perform(action) }
                }
                .buttonStyle(.glass)
            }

            HelpButton(topic: alert.helpTopic)
                .buttonStyle(.glass)
                .labelStyle(.iconOnly)

            Button {
                store.dismiss(alert)
            } label: {
                Image(systemName: "xmark")
                    .accessibilityLabel("Dismiss")
            }
            .buttonStyle(.glass)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular.tint(tint.opacity(0.18)), in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(alert.title)
        .accessibilityHint(alert.message)
    }

    private var tint: Color {
        switch alert.severity {
        case .info: .accentColor
        case .warning: .orange
        case .error: .red
        }
    }
}

/// Stack of every current banner.
struct PipelineBannerStack: View {
    @Environment(ScreenshotStore.self) private var store

    var body: some View {
        if !store.alerts.isEmpty {
            VStack(spacing: 8) {
                ForEach(store.alerts) { alert in
                    PipelineBanner(alert: alert)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .animation(.smooth, value: store.alerts)
        }
    }
}
