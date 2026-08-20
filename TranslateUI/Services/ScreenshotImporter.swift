//
//  ScreenshotImporter.swift
//  TranslateUI
//

import Foundation

/// Turns dropped or chosen files into decoded images.
///
/// Kept free of the store so importing can be tested without SwiftUI: it
/// reports per-file failures instead of throwing, because one unreadable file
/// in a dropped folder shouldn't abandon the rest of the batch.
nonisolated struct ScreenshotImporter: Sendable {
    /// A single file that couldn't be imported.
    struct Failure: Sendable, Identifiable {
        let id = UUID()
        let name: String
        let message: String
    }

    struct Outcome: Sendable {
        var images: [LoadedImage] = []
        var failures: [Failure] = []

        var isEmpty: Bool { images.isEmpty && failures.isEmpty }
    }

    /// The subset of `urls` that point at image types the app can decode.
    static func supportedURLs(in urls: [URL]) -> [URL] {
        urls.filter(ImageLoader.isSupported)
    }

    func load(contentsOf urls: [URL]) async -> Outcome {
        var outcome = Outcome()
        for url in Self.supportedURLs(in: urls) {
            do {
                outcome.images.append(try await ImageLoader.load(from: url))
            } catch {
                outcome.failures.append(
                    Failure(name: url.lastPathComponent, message: error.localizedDescription)
                )
            }
        }
        return outcome
    }

    func load(data: Data, name: String) async -> Outcome {
        do {
            return Outcome(images: [try await ImageLoader.load(data: data, name: name)])
        } catch {
            return Outcome(failures: [Failure(name: name, message: error.localizedDescription)])
        }
    }
}
