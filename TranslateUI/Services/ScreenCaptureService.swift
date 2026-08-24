//
//  ScreenCaptureService.swift
//  TranslateUI
//

import AppKit
import CoreGraphics
import Foundation
import OSLog
@preconcurrency import ScreenCaptureKit

/// The seam through which `ScreenshotStore` asks for a screen capture.
///
/// Fronted by a protocol so tests inject a stub returning a fixture image; the
/// real ScreenCaptureKit path only runs when the user clicks the buttons.
protocol ScreenCapturing: Sendable {
    /// Presents the system window picker and captures the chosen window.
    /// Returns `nil` if the user cancels.
    func captureWindow() async throws -> LoadedImage?

    /// Presents a rubber-band overlay and captures the dragged region.
    /// Returns `nil` if the user cancels (Esc or empty drag).
    func captureArea() async throws -> LoadedImage?
}

// MARK: - Errors

/// The screen-recording TCC permission has not been granted.
///
/// Thrown when `SCShareableContent` is empty or the resulting capture is a
/// black frame — some macOS builds report denial silently by returning black
/// pixels instead of throwing, so the store maps both signals to the same
/// permission-denied banner.
struct ScreenCapturePermissionDenied: LocalizedError {
    var errorDescription: String? {
        String(localized: "Translate UI doesn’t have permission to record the screen.")
    }
}

struct ScreenCaptureUnavailable: LocalizedError {
    let reason: String
    var errorDescription: String? { reason }
}

// MARK: - Real service

/// The shipping implementation, wrapping `SCContentSharingPicker` and
/// `SCScreenshotManager`.
///
/// The picker is a shared singleton with a delegate-based API, so each
/// `captureWindow` call installs an observer, resumes a continuation on the
/// callback, and always removes the observer in `defer` — otherwise old
/// continuations would receive later picker callbacks.
@MainActor
final class ScreenCaptureService: ScreenCapturing {
    private let logger = Logger(subsystem: "com.icloud.TranslateUI", category: "ScreenCapture")

    nonisolated init() {}

    // MARK: Window capture

    func captureWindow() async throws -> LoadedImage? {
        // Force TCC to prompt (or fail) before we present the picker, so a
        // silent denial doesn't look like an empty picker.
        try await ensurePermission()

        guard let filter = await presentWindowPicker() else { return nil }

        let (image, name) = try await snapshot(
            filter: filter, sourceRect: nil, label: windowLabel(for: filter))
        try assertNotBlackFrame(image)
        return try await ImageLoader.load(capturedImage: image, name: name)
    }

    // MARK: Area capture

    func captureArea() async throws -> LoadedImage? {
        try await ensurePermission()

        guard let selection = await AreaSelectionCoordinator.selectRegion() else { return nil }

        // The overlay reports the region in the target screen's own coordinate
        // space (bottom-left origin, like NSScreen). SCStreamConfiguration
        // wants points in the display, top-left origin.
        let sourceRect = Self.sourceRect(
            for: selection.regionInScreen,
            in: selection.screen
        )
        guard sourceRect.width >= 4, sourceRect.height >= 4 else { return nil }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first(where: { $0.displayID == selection.displayID }) else {
            throw ScreenCaptureUnavailable(
                reason: String(localized: "The selected display is no longer available.")
            )
        }

        let currentApp = content.applications.first { app in
            app.bundleIdentifier == Bundle.main.bundleIdentifier
        }
        let filter = SCContentFilter(
            display: display,
            excludingApplications: currentApp.map { [$0] } ?? [],
            exceptingWindows: []
        )

        let config = SCStreamConfiguration()
        config.sourceRect = sourceRect
        config.width = Int(sourceRect.width * selection.pixelsPerPoint)
        config.height = Int(sourceRect.height * selection.pixelsPerPoint)
        config.showsCursor = false
        config.capturesShadowsOnly = false
        config.captureResolution = .best

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )
        try assertNotBlackFrame(image)

        let name = Self.timestampName()
        return try await ImageLoader.load(capturedImage: image, name: name)
    }

    // MARK: Geometry

    /// Convert a rect in the given screen's coordinate space (bottom-left
    /// origin, like `NSScreen`) into the top-left-origin rect ScreenCaptureKit
    /// wants for `SCStreamConfiguration.sourceRect`.
    ///
    /// Both are in points — `SCScreenshotManager` scales up to display pixels
    /// itself. The screen origin is subtracted so multi-display layouts land in
    /// the display's local coordinates.
    nonisolated static func sourceRect(for regionInScreen: CGRect, in screen: NSScreen) -> CGRect {
        let localX = regionInScreen.origin.x - screen.frame.origin.x
        let localBottom = regionInScreen.origin.y - screen.frame.origin.y
        let topLeftY = screen.frame.height - (localBottom + regionInScreen.height)
        return CGRect(x: localX, y: topLeftY, width: regionInScreen.width, height: regionInScreen.height)
    }

    // MARK: Helpers

    private func ensurePermission() async throws {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        } catch {
            logger.warning("SCShareableContent failed: \(error.localizedDescription, privacy: .public)")
            throw ScreenCapturePermissionDenied()
        }
    }

    private func snapshot(
        filter: SCContentFilter,
        sourceRect: CGRect?,
        label: String
    ) async throws -> (CGImage, String) {
        let config = SCStreamConfiguration()
        if let rect = sourceRect {
            config.sourceRect = rect
        }
        config.showsCursor = false
        config.captureResolution = .best
        // Match the filter's content rect so the output isn't scaled.
        let contentRect = filter.contentRect
        let scale = max(filter.pointPixelScale, 1)
        config.width = Int(contentRect.width * CGFloat(scale))
        config.height = Int(contentRect.height * CGFloat(scale))

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )
        return (image, label)
    }

    private func windowLabel(for filter: SCContentFilter) -> String {
        // Best effort — SCContentFilter doesn't expose the picked window
        // directly, so use a timestamped generic name. The picker itself shows
        // the user which window they chose.
        Self.timestampName(prefix: "Window Capture")
    }

    /// Very cheap black-frame heuristic: sample a grid of pixels and if the
    /// mean luminance is essentially zero the frame is almost certainly a TCC
    /// denial masquerading as a successful capture. Threshold chosen so a
    /// near-black-but-real screen (e.g. dark mode desktop with a menu bar)
    /// still passes.
    nonisolated static func isLikelyBlackFrame(_ image: CGImage, sampleGrid: Int = 12) -> Bool {
        guard image.width >= sampleGrid, image.height >= sampleGrid else { return false }

        let width = 32
        let height = 32
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var buffer = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        guard
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: &buffer,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return false }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var sum: Int = 0
        var count: Int = 0
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * bytesPerRow) + (x * bytesPerPixel)
                let r = Int(buffer[offset])
                let g = Int(buffer[offset + 1])
                let b = Int(buffer[offset + 2])
                sum += (r + g + b)
                count += 3
            }
        }
        guard count > 0 else { return false }
        let mean = Double(sum) / Double(count)
        return mean < 2.0
    }

    private func assertNotBlackFrame(_ image: CGImage) throws {
        if Self.isLikelyBlackFrame(image) {
            logger.warning("Capture returned a black frame — treating as permission denial")
            throw ScreenCapturePermissionDenied()
        }
    }

    private nonisolated static func timestampName(prefix: String = "Capture") -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "\(prefix) \(formatter.string(from: Date()))"
    }

    // MARK: Picker glue

    private func presentWindowPicker() async -> SCContentFilter? {
        await withCheckedContinuation { (continuation: CheckedContinuation<SCContentFilter?, Never>) in
            let observer = PickerObserver { filter in
                Task { @MainActor in
                    Self.tearDownPicker()
                    continuation.resume(returning: filter)
                }
            } cancelled: {
                Task { @MainActor in
                    Self.tearDownPicker()
                    continuation.resume(returning: nil)
                }
            }

            PickerObserver.current = observer
            let picker = SCContentSharingPicker.shared
            picker.add(observer)

            var config = SCContentSharingPickerConfiguration()
            config.allowedPickerModes = [.singleWindow]
            config.allowsChangingSelectedContent = false
            picker.defaultConfiguration = config
            picker.isActive = true
            picker.present()
        }
    }

    @MainActor
    private static func tearDownPicker() {
        let picker = SCContentSharingPicker.shared
        if let observer = PickerObserver.current {
            picker.remove(observer)
        }
        picker.isActive = false
        PickerObserver.current = nil
    }
}

// MARK: - Picker observer

/// One-shot adapter from `SCContentSharingPickerObserver`'s delegate callbacks
/// to a Swift continuation. Removes itself from the picker when resolved so
/// stale observers can never fire a second time on the next capture.
private final class PickerObserver: NSObject, @unchecked Sendable {
    /// The main-actor slot that keeps the current observer alive and lets the
    /// completion callbacks find it to remove from the picker. Access on main.
    @MainActor static var current: PickerObserver?

    private let picked: @Sendable (SCContentFilter) -> Void
    private let cancelled: @Sendable () -> Void
    nonisolated(unsafe) private var didFire = false
    private let lock = NSLock()

    nonisolated init(
        picked: @escaping @Sendable (SCContentFilter) -> Void,
        cancelled: @escaping @Sendable () -> Void
    ) {
        self.picked = picked
        self.cancelled = cancelled
    }

    private nonisolated func fireOnce(_ body: @Sendable () -> Void) {
        lock.lock()
        let alreadyFired = didFire
        didFire = true
        lock.unlock()
        guard !alreadyFired else { return }
        body()
    }
}

extension PickerObserver: SCContentSharingPickerObserver {
    nonisolated func contentSharingPicker(
        _ picker: SCContentSharingPicker,
        didUpdateWith filter: SCContentFilter,
        for stream: SCStream?
    ) {
        fireOnce { self.picked(filter) }
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        fireOnce { self.cancelled() }
    }

    nonisolated func contentSharingPickerStartDidFailWithError(_ error: any Error) {
        fireOnce { self.cancelled() }
    }
}
