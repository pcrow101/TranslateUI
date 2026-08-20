//
//  OverlayChip.swift
//  TranslateUI
//

import SwiftUI

/// A single translated label floating over the screenshot.
///
/// The chip sizes itself to its text: the recognised rectangle only supplies a
/// minimum size and the type size, so long German compounds stay readable
/// instead of being clipped to the height of the original line.
struct OverlayChip: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let block: TextBlock
    /// Derived from the recognised line height by `ScreenshotCanvas`.
    var fontSize: CGFloat = 13
    var showsOriginal: Bool
    var isSelected: Bool

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: max(fontSize * 0.2, 3)) {
                Text(block.displayText)
                    .font(.system(size: fontSize, weight: .medium))
                    .foregroundStyle(textColor)
                    .lineLimit(1)

                if let badge = provenanceBadge {
                    Image(systemName: badge)
                        .font(.system(size: max(fontSize * 0.62, 7)))
                        .foregroundStyle(textColor.opacity(0.7))
                        .accessibilityHidden(true)
                }
            }

            if showsSecondaryLine {
                Text(block.sourceText)
                    .font(.system(size: max(fontSize * 0.78, 8)))
                    .foregroundStyle(textColor.opacity(0.75))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, max(fontSize * 0.34, 4))
        .padding(.vertical, max(fontSize * 0.18, 2))
        .background(chipBackground)
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(.tint, lineWidth: 2)
            }
        }
        .opacity(block.state == .translating ? 0.55 : 1)
        .zIndex(expanded ? 1 : 0)
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(block.displayText)
        .accessibilityValue(Text(block.sourceText))
        .animation(.smooth(duration: 0.18), value: isHovering)
        .animation(.smooth(duration: 0.18), value: showsOriginal)
    }

    /// A small mark showing where the text came from: a pencil for a manual
    /// edit, a bookmark for a remembered glossary term.
    private var provenanceBadge: String? {
        if block.isManuallyEdited { return "pencil" }
        if block.isGlossaryMatch { return "bookmark.fill" }
        if case .failed = block.state { return "exclamationmark.triangle.fill" }
        return nil
    }

    private var expanded: Bool { isHovering || isSelected }

    /// Showing the original only makes sense once it differs from what is
    /// displayed — otherwise the chip would print the same words twice.
    private var showsSecondaryLine: Bool {
        (showsOriginal || expanded) && block.sourceText != block.displayText
    }

    /// Keeps the chip a single tight line per string; the canvas lets it grow
    /// horizontally so nothing is ever truncated.
    private var cornerRadius: CGFloat { max(fontSize * 0.35, 5) }

    /// Chosen from the brightness of the screenshot behind the label, so the
    /// chip stays readable over both dark and light interfaces regardless of
    /// the app's appearance.
    private var textColor: Color {
        block.prefersLightText ? .white : .black
    }

    /// A chip *replaces* the text underneath it, so its background is opaque:
    /// Liquid Glass samples what is behind it, which both destroys contrast
    /// against the original label and composites over the chip's own text when
    /// the canvas is rasterised for export. Glass is reserved for the app's
    /// chrome (toolbar, status bar, buttons) where it belongs.
    private var scrimColor: Color {
        block.prefersLightText ? .black : .white
    }

    private var chipTint: Color {
        switch block.state {
        case .failed: .red
        case .skipped: .gray
        default: isSelected ? .accentColor : scrimColor
        }
    }

    @ViewBuilder
    private var chipBackground: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(scrimColor.opacity(reduceTransparency ? 1 : 0.94))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(chipTint.opacity(chipTint == scrimColor ? 0 : 0.25))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(textColor.opacity(expanded ? 0.45 : 0.22), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.35), radius: expanded ? 6 : 2, y: 1)
    }

}

#Preview("Chip sizes") {
    VStack(alignment: .leading, spacing: 16) {
        ForEach([11, 14, 22] as [CGFloat], id: \.self) { size in
            OverlayChip(
                block: TextBlock(
                    sourceText: "Wiedergabe fortsetzen",
                    frame: .zero,
                    confidence: 0.99,
                    backgroundLuminance: 0.05,
                    sourceLanguage: .german,
                    translatedText: "Continue Watching",
                    state: .translated
                ),
                fontSize: size,
                showsOriginal: true,
                isSelected: false
            )
            .fixedSize()
        }
    }
    .padding(40)
    .background(.black)
}
