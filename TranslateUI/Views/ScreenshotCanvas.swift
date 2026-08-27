//
//  ScreenshotCanvas.swift
//  TranslateUI
//

import SwiftUI

/// Draws the screenshot and lays translated chips over the recognised text.
struct ScreenshotCanvas: View {
    let screenshot: Screenshot
    @Binding var selectedBlockID: TextBlock.ID?
    var editingBlockID: Binding<TextBlock.ID?> = .constant(nil)
    var showsOriginal: Bool = false
    var isInteractive: Bool = true
    var showsTranslations: Bool = true

    var body: some View {
        GeometryReader { proxy in
            let layout = Layout(imageSize: screenshot.pixelSize, container: proxy.size)

            ZStack(alignment: .topLeading) {
                Image(decorative: screenshot.cgImage, scale: 1, orientation: .up)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    // Interactive canvas: let the user drag the screenshot
                    // out into Finder/Mail/Notes. Skipped on the render-to-
                    // PNG path (`isInteractive = false`) so the exporter
                    // never picks up a drag session.
                    .modifier(CanvasDrag(screenshot: screenshot, enabled: isInteractive))

                if showsTranslations {
                    ForEach(screenshot.blocks) { block in
                        let frame = layout.rect(for: block.frame)
                        OverlayChip(
                            block: block,
                            fontSize: Self.fontSize(forLineHeight: frame.height),
                            showsOriginal: showsOriginal,
                            isSelected: selectedBlockID == block.id
                        )
                        // The recognised rect is a *minimum*: the chip grows to
                        // fit its text instead of clipping it, and stays centred
                        // on the label it replaces.
                        .frame(minWidth: frame.width, minHeight: frame.height, alignment: .leading)
                        .fixedSize()
                        // Gestures and the popover must be attached *before*
                        // `.position`, which otherwise expands the interactive
                        // area to the whole canvas.
                        .contentShape(.rect)
                        .onTapGesture(count: 2) {
                            guard isInteractive else { return }
                            selectedBlockID = block.id
                            editingBlockID.wrappedValue = block.id
                        }
                        .onTapGesture {
                            guard isInteractive else { return }
                            selectedBlockID = selectedBlockID == block.id ? nil : block.id
                        }
                        .contextMenu {
                            Button("Edit Translation…") {
                                selectedBlockID = block.id
                                editingBlockID.wrappedValue = block.id
                            }
                            if block.userText != nil {
                                Button("Use Machine Translation") {
                                    store?.resetTranslation(for: block.id, in: screenshot)
                                }
                            }
                        }
                        .popover(isPresented: editingBinding(for: block), arrowEdge: .bottom) {
                            TranslationEditor(screenshot: screenshot, block: block)
                        }
                        .help(hoverHelp(for: block))
                        .allowsHitTesting(isInteractive)
                        .position(x: frame.midX, y: frame.midY)
                    }
                }
            }
            .clipShape(.rect(cornerRadius: 10))
            .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        }
        .aspectRatio(screenshot.pixelSize.width / max(screenshot.pixelSize.height, 1), contentMode: .fit)
        .animation(.smooth, value: screenshot.blocks)
    }

    /// Optional so the canvas can also be rendered head-less for export and in
    /// tests, where no store is installed in the environment.
    @Environment(ScreenshotStore.self) private var store: ScreenshotStore?

    private func editingBinding(for block: TextBlock) -> Binding<Bool> {
        Binding(
            get: { editingBlockID.wrappedValue == block.id },
            set: { isPresented in
                if !isPresented, editingBlockID.wrappedValue == block.id {
                    editingBlockID.wrappedValue = nil
                }
            }
        )
    }

    private func hoverHelp(for block: TextBlock) -> String {
        if block.isGlossaryMatch {
            String(localized: "Remembered term — double-click to edit")
        } else if block.isManuallyEdited {
            String(localized: "Edited by you — double-click to change")
        } else {
            String(localized: "Double-click to correct this translation")
        }
    }

    /// Matches the chip's type size to the recognised line height so labels
    /// stay legible on both a scaled-down preview and a full-resolution export.
    static func fontSize(forLineHeight lineHeight: CGFloat) -> CGFloat {
        min(max(lineHeight * 0.62, 9), 48)
    }

    /// Maps image-pixel rectangles into the aspect-fitted view.
    private struct Layout {
        let scale: CGFloat
        let offset: CGSize

        init(imageSize: CGSize, container: CGSize) {
            guard imageSize.width > 0, imageSize.height > 0 else {
                scale = 1
                offset = .zero
                return
            }
            let fitted = min(container.width / imageSize.width, container.height / imageSize.height)
            scale = fitted
            offset = CGSize(
                width: (container.width - imageSize.width * fitted) / 2,
                height: (container.height - imageSize.height * fitted) / 2
            )
        }

        func rect(for imageRect: CGRect) -> CGRect {
            CGRect(
                x: imageRect.minX * scale + offset.width,
                y: imageRect.minY * scale + offset.height,
                width: imageRect.width * scale,
                height: imageRect.height * scale
            )
        }
    }
}

/// Conditionally applies `.draggable` to the screenshot image. Split into a
/// modifier so the exporter can turn dragging off with a single flag.
private struct CanvasDrag: ViewModifier {
    let screenshot: Screenshot
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.draggable(transfer)
        } else {
            content
        }
    }

    private var transfer: ScreenshotTransfer {
        ScreenshotTransfer.make(from: screenshot)
            ?? ScreenshotTransfer(name: screenshot.name, pngData: Data())
    }
}
