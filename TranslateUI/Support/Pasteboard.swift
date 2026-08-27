//
//  Pasteboard.swift
//  TranslateUI
//

import AppKit
import CoreGraphics

/// Puts a captured screenshot on the general pasteboard so the user can paste
/// it into another app.
///
/// Wraps the CGImage as an `NSImage` and writes it as a single pasteboard
/// item; that gives every consumer (Preview, chat clients, image editors) a
/// format they understand without us having to promise every possible type.
enum Pasteboard {
    @discardableResult
    static func write(_ image: CGImage, to pasteboard: NSPasteboard = .general) -> Int {
        let ns = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        pasteboard.clearContents()
        pasteboard.writeObjects([ns])
        return pasteboard.changeCount
    }
}
