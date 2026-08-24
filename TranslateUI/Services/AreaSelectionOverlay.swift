//
//  AreaSelectionOverlay.swift
//  TranslateUI
//

import AppKit
import CoreGraphics
import Foundation

/// A rubber-band selection over every screen, used by area capture.
///
/// One transparent `NSPanel` per `NSScreen` covers the whole desktop so the
/// user can drag on any display. The panel that receives the drag reports the
/// dragged rect in *its* screen's coordinates, and `ScreenCaptureService` then
/// converts to display-local top-left points for ScreenCaptureKit.
@MainActor
enum AreaSelectionCoordinator {
    struct Result {
        /// Rect in the target screen's coordinate space (bottom-left origin).
        let regionInScreen: CGRect
        let screen: NSScreen
        let displayID: CGDirectDisplayID
        /// `NSScreen.backingScaleFactor` — the multiplier from points to pixels.
        let pixelsPerPoint: CGFloat
    }

    /// Presents the overlays and awaits the user's selection. Returns `nil` if
    /// the user hits Esc or clicks without dragging.
    static func selectRegion() async -> Result? {
        await withCheckedContinuation { (continuation: CheckedContinuation<Result?, Never>) in
            // The controller must outlive this scope: panels only hold a
            // `[weak self]` reference back to it, so without the static slot
            // below it would deallocate the instant `present()` returned and
            // `mouseUp` would never reach `finish(with:)`.
            let controller = AreaSelectionController { result in
                AreaSelectionController.active = nil
                continuation.resume(returning: result)
            }
            AreaSelectionController.active = controller
            controller.present()
        }
    }
}

@MainActor
private final class AreaSelectionController {
    /// Strong slot that keeps the live controller alive for the duration of a
    /// selection. Cleared by `AreaSelectionCoordinator.selectRegion` once the
    /// continuation resumes.
    static var active: AreaSelectionController?

    private var panels: [AreaSelectionPanel] = []
    private let completion: @MainActor (AreaSelectionCoordinator.Result?) -> Void
    private var didFinish = false
    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?

    init(completion: @escaping @MainActor (AreaSelectionCoordinator.Result?) -> Void) {
        self.completion = completion
    }

    func present() {
        // Activate first so our panels can become key and receive keyDown.
        NSApp.activate(ignoringOtherApps: true)

        // Bring one panel per screen up above everything, transparent, so
        // clicks land on our tracking view.
        for screen in NSScreen.screens {
            let panel = AreaSelectionPanel(screen: screen) { [weak self] result in
                self?.finish(with: result)
            }
            panels.append(panel)
            panel.orderFrontRegardless()
        }
        // Make the panel on the screen with the mouse the key window.
        let mouseLocation = NSEvent.mouseLocation
        let keyPanel =
            panels.first(where: { $0.screenRef.frame.contains(mouseLocation) }) ?? panels.first
        keyPanel?.makeKey()

        // Local monitor covers keys routed to us; global covers the (unlikely)
        // case that focus slips to another app while the overlay is up.
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            if event.keyCode == 53 {  // Escape
                self?.finish(with: nil)
                return nil
            }
            return event
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            if event.keyCode == 53 {
                Task { @MainActor in self?.finish(with: nil) }
            }
        }
    }

    private func finish(with result: AreaSelectionCoordinator.Result?) {
        guard !didFinish else { return }
        didFinish = true

        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
        }
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
        }
        localKeyMonitor = nil
        globalKeyMonitor = nil

        for panel in panels {
            panel.orderOut(nil)
        }
        panels.removeAll()

        completion(result)
    }
}

private final class AreaSelectionPanel: NSPanel {
    let screenRef: NSScreen
    private let onFinish: @MainActor (AreaSelectionCoordinator.Result?) -> Void

    init(
        screen: NSScreen,
        onFinish: @escaping @MainActor (AreaSelectionCoordinator.Result?) -> Void
    ) {
        self.screenRef = screen
        self.onFinish = onFinish

        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        isMovable = false
        hidesOnDeactivate = false
        isFloatingPanel = true
        worksWhenModal = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        let view = AreaSelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.onCommit = { [weak self] rectInView in
            guard let self else { return }
            let regionInScreen = CGRect(
                x: rectInView.origin.x + screen.frame.origin.x,
                y: rectInView.origin.y + screen.frame.origin.y,
                width: rectInView.width,
                height: rectInView.height
            )
            let displayID: CGDirectDisplayID = {
                if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                    as? NSNumber
                {
                    return CGDirectDisplayID(number.uint32Value)
                }
                return CGMainDisplayID()
            }()
            self.onFinish(
                AreaSelectionCoordinator.Result(
                    regionInScreen: regionInScreen,
                    screen: screen,
                    displayID: displayID,
                    pixelsPerPoint: screen.backingScaleFactor
                )
            )
        }
        view.onCancel = { [weak self] in
            self?.onFinish(nil)
        }
        contentView = view
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class AreaSelectionView: NSView {
    var onCommit: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            startPoint = nil
            currentPoint = nil
        }
        guard let rect = currentRect(), rect.width > 4, rect.height > 4 else {
            onCancel?()
            return
        }
        onCommit?(rect)
    }

    override func rightMouseDown(with event: NSEvent) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {  // Escape
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    private func currentRect() -> CGRect? {
        guard let start = startPoint, let end = currentPoint else { return nil }
        return CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.25).setFill()
        bounds.fill()

        if let rect = currentRect() {
            // Cut a bright rectangle out of the dimmed backdrop.
            NSColor.clear.setFill()
            rect.fill(using: .copy)

            NSColor.controlAccentColor.setStroke()
            let path = NSBezierPath(rect: rect)
            path.lineWidth = 2
            path.stroke()

            drawSizeBadge(near: rect)
        }

        drawInstructionHUD()
    }

    private func drawInstructionHUD() {
        let text =
            "Drag to select an area   •   Release to capture   •   Esc or right-click to cancel"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let attributed = NSAttributedString(string: text, attributes: attrs)
        let textSize = attributed.size()
        let padding = NSSize(width: 18, height: 10)
        let hudSize = NSSize(
            width: textSize.width + padding.width * 2,
            height: textSize.height + padding.height * 2
        )
        let hudRect = NSRect(
            x: (bounds.width - hudSize.width) / 2,
            y: bounds.height - hudSize.height - 40,
            width: hudSize.width,
            height: hudSize.height
        )
        let bg = NSBezierPath(roundedRect: hudRect, xRadius: 10, yRadius: 10)
        NSColor.black.withAlphaComponent(0.7).setFill()
        bg.fill()
        attributed.draw(
            at: NSPoint(x: hudRect.minX + padding.width, y: hudRect.minY + padding.height)
        )
    }

    private func drawSizeBadge(near rect: CGRect) {
        let text = "\(Int(rect.width.rounded())) × \(Int(rect.height.rounded()))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let attributed = NSAttributedString(string: text, attributes: attrs)
        let textSize = attributed.size()
        let padding = NSSize(width: 8, height: 4)
        var badgeRect = NSRect(
            x: rect.midX - (textSize.width + padding.width * 2) / 2,
            y: rect.minY - textSize.height - padding.height * 2 - 6,
            width: textSize.width + padding.width * 2,
            height: textSize.height + padding.height * 2
        )
        if badgeRect.minY < 4 {
            badgeRect.origin.y = rect.maxY + 6
        }
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: badgeRect, xRadius: 6, yRadius: 6).fill()
        attributed.draw(
            at: NSPoint(x: badgeRect.minX + padding.width, y: badgeRect.minY + padding.height)
        )
    }
}
