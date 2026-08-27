//
//  ImageLoader.swift
//  TranslateUI
//

import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Immutable Core Graphics image, safe to hand between concurrency domains.
nonisolated struct SendableImage: @unchecked Sendable {
    let cgImage: CGImage

    var pixelSize: CGSize {
        CGSize(width: cgImage.width, height: cgImage.height)
    }
}

/// A decoded screenshot before it becomes a `Screenshot` on the main actor.
nonisolated struct LoadedImage: Sendable {
    let name: String
    let sourceURL: URL?
    let contentHash: String
    let image: SendableImage
}

nonisolated enum ImageLoadingError: LocalizedError {
    case unreadableFile(String)
    case unsupportedFormat(String)

    var errorDescription: String? {
        switch self {
        case .unreadableFile(let name):
            String(localized: "“\(name)” could not be read.")
        case .unsupportedFormat(let name):
            String(localized: "“\(name)” isn’t a supported image format.")
        }
    }
}

/// Loads screenshots off the main actor and gives each one a stable content hash.
nonisolated enum ImageLoader {
    static let supportedTypes: [UTType] = [.png, .jpeg, .heic, .heif, .tiff, .bmp, .gif, .webP]

    @concurrent
    nonisolated static func load(from url: URL) async throws -> LoadedImage {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            throw ImageLoadingError.unreadableFile(url.lastPathComponent)
        }
        return LoadedImage(
            name: url.deletingPathExtension().lastPathComponent,
            sourceURL: url,
            contentHash: hash(of: data),
            image: try decode(data: data, name: url.lastPathComponent)
        )
    }

    @concurrent
    nonisolated static func load(data: Data, name: String) async throws -> LoadedImage {
        LoadedImage(
            name: name,
            sourceURL: nil,
            contentHash: hash(of: data),
            image: try decode(data: data, name: name)
        )
    }

    /// Wraps a freshly captured `CGImage` as a `LoadedImage`.
    ///
    /// The content hash is computed from a PNG encoding so identical repeat
    /// captures still deduplicate through the same code path as file imports.
    @concurrent
    nonisolated static func load(capturedImage: CGImage, name: String) async throws -> LoadedImage {
        guard let data = pngData(from: capturedImage) else {
            throw ImageLoadingError.unsupportedFormat(name)
        }
        return LoadedImage(
            name: name,
            sourceURL: nil,
            contentHash: hash(of: data),
            image: SendableImage(cgImage: capturedImage)
        )
    }

    private nonisolated static func pngData(from image: CGImage) -> Data? {
        Self.encodePNG(from: image)
    }

    /// PNG-encodes a `CGImage`. Used by `SessionStore` to persist captured
    /// screenshots whose bytes never originated from a file on disk.
    nonisolated static func encodePNG(from image: CGImage) -> Data? {
        let mutableData = CFDataCreateMutable(nil, 0)!
        guard
            let destination = CGImageDestinationCreateWithData(
                mutableData, UTType.png.identifier as CFString, 1, nil
            )
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return mutableData as Data
    }

    nonisolated static func isSupported(_ url: URL) -> Bool {
        guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else {
            let ext = url.pathExtension.lowercased()
            return supportedTypes.contains { $0.preferredFilenameExtension == ext }
        }
        return supportedTypes.contains { type.conforms(to: $0) }
    }

    // MARK: - Helpers

    private nonisolated static func decode(data: Data, name: String) throws -> SendableImage {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: true,
            kCGImageSourceShouldAllowFloat: false
        ]
        guard
            let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary),
            let image = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary)
        else {
            throw ImageLoadingError.unsupportedFormat(name)
        }
        return SendableImage(cgImage: image)
    }

    private nonisolated static func hash(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
