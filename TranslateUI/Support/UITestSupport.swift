//
//  UITestSupport.swift
//  TranslateUI
//

#if DEBUG
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Deterministic fixtures for the UI smoke test.
///
/// The end-to-end flow starts with a file drop, which a UI test can't perform
/// against a sandboxed open panel. Instead the test launches the app with
/// `-uiTestFixture`, and the same synthetic German TV screen is imported
/// through the *real* import path — so recognition, overlay rendering, copy and
/// export are all exercised for real.
///
/// Compiled out of release builds.
enum UITestSupport {
    /// Read as a `UserDefaults` key, so it must be passed as a *pair*:
    /// `-uiTestFixture YES`.
    ///
    /// A bare `-uiTestFixture` flag looks harmless but breaks `NSUserDefaults`'
    /// `-key value` pairing for every argument that follows it — including
    /// `-ApplePersistenceIgnoreState YES`, which left the app restoring a
    /// "no windows" state and showing nothing at all.
    static let defaultsKey = "uiTestFixture"

    /// How many screenshots to seed (`-uiTestFixtureCount 6`). More than one
    /// exercises the case where several images finish recognition at different
    /// times and compete for the same translation sessions.
    static let countKey = "uiTestFixtureCount"

    /// Labels drawn on the fixture, large enough for Vision to read reliably.
    static let fixtureLines = ["Einstellungen", "Untertitel", "Wiedergabe"]
    /// Deliberately long, on a large canvas: recognition then takes long
    /// enough for the screenshots to finish at staggered times, which is what
    /// makes them compete for the translation sessions the way real 4K
    /// captures do.
    static let germanLines = [
        "Einstellungen", "Untertitel", "Wiedergabe", "Ton und Sprachen",
        "Fernsehprogramm", "Favoriten", "Sendung suchen", "Beenden"
    ]
    static let italianLines = [
        "Impostazioni", "Sottotitoli", "Riproduzione", "Audio e lingue",
        "Guida ai programmi", "Preferiti", "Cerca trasmissione", "Esci"
    ]

    static let fixtureSize = CGSize(width: 1920, height: 1080)

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: defaultsKey)
    }

    static var fixtureCount: Int {
        max(UserDefaults.standard.integer(forKey: countKey), 1)
    }

    /// Seconds to wait before importing the second half of the fixtures
    /// (`-uiTestFixtureWave 4`). Zero imports everything in one batch.
    ///
    /// A delayed second wave lands while the first batch is still translating,
    /// which is what forces a live session to be re-armed — the situation that
    /// crashed the app when a session outlived its view.
    static var waveDelay: Int {
        UserDefaults.standard.integer(forKey: "uiTestFixtureWave")
    }

    @MainActor
    static func seed(into store: ScreenshotStore) async {
        guard isEnabled, store.screenshots.isEmpty else { return }
        guard let urls = writeFixtures() else { return }

        guard waveDelay > 0 else {
            // Imported as one batch through the real drop path, so every
            // screenshot is added together and their analyses run concurrently
            // — which is what makes them compete for the translation sessions.
            await store.importFiles(at: urls)
            return
        }

        let split = urls.count / 2
        await store.importFiles(at: Array(urls[..<split]))
        try? await Task.sleep(for: .seconds(waveDelay))
        await store.importFiles(at: Array(urls[split...]))
    }

    /// Writes the fixture screenshots to a temporary directory.
    private static func writeFixtures() -> [URL]? {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "TranslateUIFixtures", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: directory)
        guard
            (try? FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )) != nil
        else { return nil }

        var urls: [URL] = []
        for index in 0..<fixtureCount {
            let isItalian = index.isMultiple(of: 2) == false
            // Each image must hash differently or the importer de-duplicates
            // it; varying the width avoids adding text that would skew
            // language detection.
            let size = CGSize(width: fixtureSize.width + CGFloat(index), height: fixtureSize.height)
            guard
                let data = fixturePNGData(
                    lines: isItalian ? italianLines : germanLines,
                    size: size
                )
            else { continue }

            let name = isItalian ? "Italian-\(index)" : "German-\(index)"
            let url = directory.appending(path: "\(name).png")
            guard (try? data.write(to: url)) != nil else { continue }
            urls.append(url)
        }
        return urls.isEmpty ? nil : urls
    }

    /// Renders a dark interface screen with a few German labels.
    static func fixturePNGData(
        lines: [String] = fixtureLines,
        size: CGSize = CGSize(width: 1280, height: 720),
        fontSize: CGFloat = 96
    ) -> Data? {
        guard
            let context = CGContext(
                data: nil,
                width: Int(size.width),
                height: Int(size.height),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return nil }

        context.setFillColor(CGColor(red: 0.06, green: 0.06, blue: 0.08, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))

        let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        let topMargin = fontSize * 1.6
        let usableHeight = size.height - topMargin - fontSize * 0.8
        let spacing = min(fontSize * 2.4, usableHeight / CGFloat(max(lines.count - 1, 1)))

        for (index, line) in lines.enumerated() {
            let attributed = NSAttributedString(
                string: line,
                attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): font,
                    NSAttributedString.Key(kCTForegroundColorAttributeName as String):
                        CGColor(red: 1, green: 1, blue: 1, alpha: 1)
                ]
            )
            context.textPosition = CGPoint(
                x: 80,
                y: size.height - topMargin - CGFloat(index) * spacing
            )
            CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
        }

        guard let image = context.makeImage() else { return nil }

        let data = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                data as CFMutableData,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
#endif
