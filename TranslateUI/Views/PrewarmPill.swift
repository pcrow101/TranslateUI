//
//  PrewarmPill.swift
//  TranslateUI
//

import SwiftUI

/// A small floating capsule shown while the on-device model warms up so the
/// user knows why the first "Polish" is slower than the rest.
///
/// Presence is driven by `ScreenshotStore.isPrewarmingModel`; the view fades
/// itself in and out around that flag. Non-interactive: it's a status hint,
/// not a control.
struct PrewarmPill: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .progressViewStyle(.circular)
            Text("Warming Apple Intelligence…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Warming Apple Intelligence")
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}

#Preview {
    PrewarmPill()
        .padding(40)
}
