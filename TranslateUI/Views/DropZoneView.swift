//
//  DropZoneView.swift
//  TranslateUI
//

import AppKit
import SwiftUI

/// Empty state: drag-and-drop target with keyboard and clipboard shortcuts.
struct DropZoneView: View {
    @Environment(ScreenshotStore.self) private var store
    @Environment(\.showHelp) private var showHelp
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "text.viewfinder")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.tint)
                .symbolEffect(.pulse, options: .repeating, isActive: isTargeted)

            VStack(spacing: 6) {
                Text("Drop a TV screenshot")
                    .font(.title2.weight(.semibold))
                    .accessibilityIdentifier("dropZone.title")
                Text(
                    "German and Italian interface text is recognised and translated to English entirely on this Mac."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            }

            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    Button {
                        store.showsFileImporter = true
                    } label: {
                        Label("Choose Files…", systemImage: "folder")
                    }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut("o")

                    Button {
                        pasteFromClipboard()
                    } label: {
                        Label("Paste Screenshot", systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(.glass)
                    .keyboardShortcut("v")
                }
            }
            .controlSize(.large)

            Button {
                showHelp(HelpContent.ID.gettingStarted)
            } label: {
                Label("How this works", systemImage: "questionmark.circle")
            }
            .buttonStyle(.link)
            .accessibilityIdentifier("dropZone.help")
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background.secondary)
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(
                    isTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator),
                    style: StrokeStyle(lineWidth: isTargeted ? 3 : 1, dash: [8, 6])
                )
                .padding(24)
                .animation(.smooth, value: isTargeted)
        }
        .dropDestination(for: URL.self) { urls, _ in
            Task { await store.importFiles(at: urls) }
            return true
        } isTargeted: {
            isTargeted = $0
        }
    }

    private func pasteFromClipboard() {
        let pasteboard = NSPasteboard.general
        if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            Task { await store.importImageData(data, name: "Pasted Screenshot") }
            return
        }
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL], !urls.isEmpty {
            Task { await store.importFiles(at: urls) }
            return
        }
        store.errorMessage = String(localized: "The clipboard doesn’t contain an image.")
    }
}
