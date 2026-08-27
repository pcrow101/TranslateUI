//
//  ScreenCaptureServiceTests.swift
//  TranslateUITests
//

import AppKit
import CoreGraphics
import Foundation
import Testing

@testable import TranslateUI

@Suite("Screen capture")
struct ScreenCaptureServiceTests {

    // MARK: - Coordinate math

    @Test("Origin-screen conversion flips Y and stays inside the display")
    func sourceRectForPrimaryScreen() {
        let screen = FakeScreen(frame: CGRect(x: 0, y: 0, width: 1440, height: 900))

        let region = CGRect(x: 100, y: 200, width: 300, height: 150)
        let rect = ScreenCaptureService.sourceRect(for: region, in: screen.screen)

        // Bottom-left (0, 200) with height 150 → top-left y = 900 - (200 + 150).
        #expect(rect == CGRect(x: 100, y: 550, width: 300, height: 150))
    }

    @Test("Multi-display layouts land in the display's local coordinates")
    func sourceRectForSecondaryScreen() {
        // A 1920×1080 secondary sitting to the right of the primary.
        let secondary = FakeScreen(frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080))

        // A region high on the secondary screen.
        let region = CGRect(x: 1440 + 50, y: 1080 - 400, width: 200, height: 100)
        let rect = ScreenCaptureService.sourceRect(for: region, in: secondary.screen)

        // Local x = 50, and top-left y = 1080 - ((1080 - 400) + 100) = 300.
        #expect(rect.origin.x == 50)
        #expect(rect.origin.y == 300)
        #expect(rect.width == 200)
        #expect(rect.height == 100)
    }

    // MARK: - Black-frame heuristic

    @Test("A fully black image is treated as a permission denial")
    func blackFrameIsDetected() {
        let image = makeSolid(color: .black, size: CGSize(width: 64, height: 64))
        #expect(ScreenCaptureService.isLikelyBlackFrame(image))
    }

    @Test("A normal image is not mistaken for a denial")
    func realImageIsNotFlagged() {
        let image = makeSolid(color: .white, size: CGSize(width: 64, height: 64))
        #expect(!ScreenCaptureService.isLikelyBlackFrame(image))
    }

    @Test("A mostly-dark UI still passes the heuristic")
    func mostlyDarkStillPasses() {
        // Dark charcoal — roughly what a dark-mode window looks like.
        let image = makeSolid(color: NSColor(white: 0.06, alpha: 1), size: CGSize(width: 64, height: 64))
        #expect(!ScreenCaptureService.isLikelyBlackFrame(image))
    }

    // MARK: - Store integration

    @Test("A stubbed window capture flows through the import path")
    @MainActor
    func windowCaptureImportsIntoStore() async {
        let cgImage = TestImageFactory.screen(
            lines: ["Suchen"],
            size: CGSize(width: 300, height: 120),
            fontSize: 24
        )!
        let loaded = try! await ImageLoader.load(capturedImage: cgImage, name: "Fixture Window")

        let stub = StubScreenCapture(window: loaded)
        let store = TestFixtures.store(screenCapture: stub)

        await store.captureWindow()

        #expect(store.screenshots.count == 1)
        #expect(store.screenshots.first?.name == "Fixture Window")
        #expect(store.selectionID == store.screenshots.first?.id)
    }

    @Test("A denied capture posts the permission alert instead of throwing")
    @MainActor
    func deniedCapturePostsAlert() async {
        let stub = StubScreenCapture(windowError: ScreenCapturePermissionDenied())
        let store = TestFixtures.store(screenCapture: stub)

        await store.captureWindow()

        #expect(store.screenshots.isEmpty)
        let denialID = PipelineAlert.screenCapturePermissionDenied().id
        #expect(store.alerts.contains { $0.id == denialID })
    }

    @Test("A cancelled capture is silent")
    @MainActor
    func cancelledCaptureIsSilent() async {
        let stub = StubScreenCapture(window: nil)
        let store = TestFixtures.store(screenCapture: stub)

        await store.captureArea()

        #expect(store.screenshots.isEmpty)
        #expect(store.alerts.isEmpty)
        #expect(store.errorMessage == nil)
    }

    @Test("A new capture becomes the active screenshot")
    @MainActor
    func captureSwitchesSelectionToTheNewShot() async throws {
        let firstCG = TestImageFactory.screen(
            lines: ["Alpha"], size: CGSize(width: 300, height: 120), fontSize: 24)!
        let first = try await ImageLoader.load(capturedImage: firstCG, name: "First")
        let secondCG = TestImageFactory.screen(
            lines: ["Beta"], size: CGSize(width: 300, height: 120), fontSize: 24)!
        let second = try await ImageLoader.load(capturedImage: secondCG, name: "Second")

        let store = TestFixtures.store(screenCapture: StubScreenCapture(window: first, area: second))

        await store.captureWindow()
        let firstShotID = try #require(store.selectionID)

        // A second capture, on top of an already-selected shot, must switch
        // the selection to the new image — otherwise the user keeps looking
        // at the old one.
        await store.captureArea()
        #expect(store.screenshots.count == 2)
        #expect(store.selectionID != firstShotID)
        #expect(store.screenshots.first(where: { $0.id == store.selectionID })?.name == "Second")
    }
}

// MARK: - Helpers

/// A minimal shim wrapping an `NSScreen`-like frame. `NSScreen` can't be
/// synthesised directly, but only `frame` is used by `sourceRect`.
private struct FakeScreen {
    let frame: CGRect
    var screen: NSScreen {
        // We can't build an NSScreen, but `sourceRect(for:in:)` only reads
        // `screen.frame`, so we bounce through a shim class using KVC. The
        // simplest workaround is to route through NSScreen.main and reset
        // the frame lazily via method swizzling — but that's overkill. Use
        // a subclass fixture instead.
        FakeNSScreen.make(with: frame)
    }
}

/// Subclass of `NSScreen` that reports a fixture frame. `NSScreen` can be
/// subclassed for use as a value under test as long as no AppKit code paths
/// inspect its private state — `sourceRect(for:in:)` only reads `frame`.
private final class FakeNSScreen: NSScreen {
    private var storedFrame: NSRect = .zero
    override var frame: NSRect { storedFrame }

    static func make(with frame: NSRect) -> FakeNSScreen {
        let screen = FakeNSScreen()
        screen.storedFrame = frame
        return screen
    }
}

private func makeSolid(color: NSColor, size: CGSize) -> CGImage {
    let image = NSImage(size: size)
    image.lockFocus()
    color.setFill()
    NSRect(origin: .zero, size: size).fill()
    image.unlockFocus()
    var rect = NSRect(origin: .zero, size: size)
    return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)!
}

/// Stub capture service returning canned outcomes.
private final class StubScreenCapture: ScreenCapturing, @unchecked Sendable {
    private let windowResult: Result<LoadedImage?, Error>
    private let areaResult: Result<LoadedImage?, Error>

    init(
        window: LoadedImage? = nil,
        windowError: Error? = nil,
        area: LoadedImage? = nil,
        areaError: Error? = nil
    ) {
        if let windowError { windowResult = .failure(windowError) } else { windowResult = .success(window) }
        if let areaError { areaResult = .failure(areaError) } else { areaResult = .success(area) }
    }

    func captureWindow() async throws -> LoadedImage? {
        try windowResult.get()
    }

    func captureArea() async throws -> LoadedImage? {
        try areaResult.get()
    }
}
