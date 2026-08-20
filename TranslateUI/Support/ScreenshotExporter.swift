//
//  ScreenshotExporter.swift
//  TranslateUI
//

import SwiftUI
import UniformTypeIdentifiers

/// Renders an annotated screenshot to PNG data.
enum ScreenshotExporter {
    @MainActor
    static func pngData(for view: some View) -> Data? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        renderer.isOpaque = true
        guard
            let cgImage = renderer.cgImage,
            let representation = NSBitmapImageRep(cgImage: cgImage).representation(
                using: .png, properties: [:])
        else { return nil }
        return representation
    }
}

/// Minimal `FileDocument` so `.fileExporter` can save the rendered PNG.
struct PNGDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.png]

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
