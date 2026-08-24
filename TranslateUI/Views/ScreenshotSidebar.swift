//
//  ScreenshotSidebar.swift
//  TranslateUI
//

import SwiftUI

struct ScreenshotSidebar: View {
    @Environment(ScreenshotStore.self) private var store
    @Binding var selectedBlockID: TextBlock.ID?

    var body: some View {
        @Bindable var store = store

        List(selection: $store.selectionID) {
            Section("Screenshots") {
                ForEach(store.screenshots) { screenshot in
                    row(for: screenshot)
                        .tag(screenshot.id)
                        .contextMenu {
                            Button("Re-analyze") {
                                Task { await store.analyze(screenshot, ignoringCache: true) }
                            }
                            Button("Remove", role: .destructive) {
                                store.remove(screenshot)
                            }
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .accessibilityIdentifier("sidebar.screenshots")
        .onChange(of: store.selectionID) { _, _ in selectedBlockID = nil }
        .overlay {
            if store.screenshots.isEmpty {
                ContentUnavailableView(
                    "No Screenshots",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("Drop captures here or use ⌘O.")
                )
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                Button {
                    store.showsFileImporter = true
                } label: {
                    Label("Add Screenshots", systemImage: "plus")
                }
                .buttonStyle(.glass)
                .disabled(store.isImporting)

                Button {
                    Task { await store.captureWindow() }
                } label: {
                    Label("Capture Window", systemImage: "macwindow")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.glass)
                .help("Capture a window (⇧⌘W)")
                .accessibilityIdentifier("sidebar.captureWindow")
                .disabled(store.isImporting)

                Button {
                    Task { await store.captureArea() }
                } label: {
                    Label("Capture Area", systemImage: "rectangle.dashed")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.glass)
                .help("Capture an area (⇧⌘A)")
                .accessibilityIdentifier("sidebar.captureArea")
                .disabled(store.isImporting)

                Spacer()

                Button {
                    store.removeAll()
                } label: {
                    Label("Clear", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.glass)
                .disabled(store.screenshots.isEmpty)
            }
            .padding(12)
        }
    }

    private func row(for screenshot: Screenshot) -> some View {
        HStack(spacing: 10) {
            Image(decorative: screenshot.cgImage, scale: 1, orientation: .up)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 56, height: 32)
                .clipShape(.rect(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.separator, lineWidth: 0.5)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(screenshot.name)
                    .lineLimit(1)
                    .accessibilityIdentifier("sidebar.name")
                HStack(spacing: 4) {
                    if screenshot.documentLanguage != .unknown {
                        Text(screenshot.documentLanguage.flagSymbol)
                    }
                    Text(screenshot.phase.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .accessibilityIdentifier("sidebar.phase")
                }
            }

            Spacer(minLength: 0)

            if screenshot.phase.isBusy {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }
}
