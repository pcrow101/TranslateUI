//
//  ContentView.swift
//  TranslateUI
//

import AppKit
import SwiftUI
import Translation
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(ScreenshotStore.self) private var store
    @Environment(AppSettings.self) private var settings

    @State private var isInspectorPresented = true
    @State private var selectedBlockID: TextBlock.ID?
    @State private var editingBlockID: TextBlock.ID?
    @State private var exportDocument: PNGDocument?
    @State private var isExporterPresented = false

    // The body is split into layers so the type checker doesn't have to solve
    // one enormous modifier chain in a single expression.
    var body: some View {
        fileHandling
            .task {
                #if DEBUG
                await UITestSupport.seed(into: store)
                #endif
                await store.prewarm()
            }
            // Publish the document actions so the main menu can invoke them too.
            .focusedSceneValue(\.copyTranslations, copyAction)
            .focusedSceneValue(\.exportAnnotatedImage, exportAction)
            // Re-run recognition (debounced) when a recognition setting changes.
            .onChange(of: settings.minimumConfidence) { _, _ in
                store.recognitionSettingsChanged()
            }
            // One session per source language: the modifier vends the session
            // and re-runs whenever a configuration is created or invalidated.
            .translationTask(store.germanConfiguration) { session in
                await store.runTranslation(for: .german, using: session)
            }
            .translationTask(store.italianConfiguration) { session in
                await store.runTranslation(for: .italian, using: session)
            }
            .alert(
                "Something went wrong",
                isPresented: errorBinding,
                presenting: store.errorMessage
            ) { _ in
                Button("OK", role: .cancel) { store.errorMessage = nil }
            } message: { message in
                Text(message)
            }
    }

    private var fileHandling: some View {
        @Bindable var store = store

        return
            splitView
            .dropDestination(for: URL.self) { urls, _ in
                Task { await store.importFiles(at: urls) }
                return true
            }
            .fileImporter(
                isPresented: $store.showsFileImporter,
                allowedContentTypes: ImageLoader.supportedTypes,
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    Task { await store.importFiles(at: urls) }
                case .failure(let error):
                    store.errorMessage = error.localizedDescription
                }
            }
            .fileExporter(
                isPresented: $isExporterPresented,
                document: exportDocument,
                contentType: .png,
                defaultFilename: exportFilename
            ) { result in
                if case .failure(let error) = result {
                    store.errorMessage = error.localizedDescription
                }
            }
    }

    private var splitView: some View {
        NavigationSplitView {
            ScreenshotSidebar(selectedBlockID: $selectedBlockID)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
        } detail: {
            detail
        }
        .navigationTitle("Translate UI")
        .navigationSubtitle(store.selectedScreenshot?.name ?? "")
        .toolbar { toolbarContent }
        .inspector(isPresented: $isInspectorPresented) {
            TextListInspector(selectedBlockID: $selectedBlockID)
                .inspectorColumnWidth(min: 260, ideal: 320, max: 420)
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let screenshot = store.selectedScreenshot {
            ScreenshotDetailView(
                screenshot: screenshot,
                selectedBlockID: $selectedBlockID,
                editingBlockID: $editingBlockID
            )
            .id(screenshot.id)
        } else {
            DropZoneView()
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        @Bindable var settings = settings

        ToolbarItem(placement: .principal) {
            Picker("Display Mode", selection: $settings.displayMode) {
                ForEach(DisplayMode.allCases) { mode in
                    Label(mode.label, systemImage: mode.symbol).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelStyle(.iconOnly)
            .help("Choose how translations are displayed")
        }

        ToolbarSpacer(.flexible)

        ToolbarItem {
            Toggle(isOn: $settings.showOriginalText) {
                Label("Show Original", systemImage: "textformat.alt")
            }
            .help("Show the original German or Italian text")
        }

        ToolbarItem {
            Button {
                Task { await store.reanalyzeSelection() }
            } label: {
                Label("Re-analyze", systemImage: "arrow.clockwise")
            }
            .disabled(store.selectedScreenshot == nil)
            .help("Run text recognition again")
        }

        ToolbarSpacer(.fixed)

        ToolbarItem {
            Button {
                copyTranslations()
            } label: {
                Label("Copy Text", systemImage: "doc.on.doc")
            }
            .disabled(store.selectedScreenshot == nil)
            .help("Copy every translated line")
        }

        ToolbarItem {
            Button {
                exportAnnotatedImage()
            } label: {
                Label("Export Image", systemImage: "square.and.arrow.up")
            }
            .disabled(store.selectedScreenshot == nil)
            .help("Save the screenshot with translations burned in")
        }

        ToolbarItem {
            Button {
                isInspectorPresented.toggle()
            } label: {
                Label("Inspector", systemImage: "sidebar.trailing")
            }
            .help("Show or hide the text list")
        }
    }

    /// Menu actions are published only while a screenshot is selected, which
    /// is what keeps the menu items disabled at the right times.
    private var copyAction: (() -> Void)? {
        guard store.selectedScreenshot != nil else { return nil }
        return copyTranslations
    }

    private var exportAction: (() -> Void)? {
        guard store.selectedScreenshot != nil else { return nil }
        return exportAnnotatedImage
    }

    private var exportFilename: String {
        guard let screenshot = store.selectedScreenshot else { return "Translation" }
        return "\(screenshot.name)-EN"
    }

    // MARK: - Actions

    private func copyTranslations() {
        guard let screenshot = store.selectedScreenshot else { return }
        let text = screenshot.plainText(showingOriginal: settings.showOriginalText)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func exportAnnotatedImage() {
        guard let screenshot = store.selectedScreenshot else { return }
        let view = ScreenshotCanvas(
            screenshot: screenshot,
            selectedBlockID: .constant(nil),
            showsOriginal: settings.showOriginalText,
            isInteractive: false
        )
        .frame(width: screenshot.pixelSize.width, height: screenshot.pixelSize.height)

        guard let data = ScreenshotExporter.pngData(for: view) else {
            store.errorMessage = String(localized: "The annotated image couldn’t be rendered.")
            return
        }
        exportDocument = PNGDocument(data: data)
        isExporterPresented = true
    }
}

#Preview {
    let settings = AppSettings()
    ContentView()
        .environment(settings)
        .environment(ScreenshotStore(settings: settings))
        .frame(width: 1100, height: 700)
}
