//
//  ReadingOrderTests.swift
//  TranslateUITests
//

import CoreGraphics
import Foundation
import Testing

@testable import TranslateUI

@Suite("Reading order")
struct ReadingOrderTests {
    private func block(_ text: String, x: CGFloat, y: CGFloat, height: CGFloat = 24) -> TextBlock {
        TextBlock(
            sourceText: text,
            frame: CGRect(x: x, y: y, width: 120, height: height),
            confidence: 0.9
        )
    }

    @Test("Blocks are ordered top to bottom")
    func ordersVertically() {
        let blocks = [
            block("bottom", x: 0, y: 200),
            block("top", x: 0, y: 0),
            block("middle", x: 0, y: 100)
        ]

        #expect(blocks.inReadingOrder.map(\.sourceText) == ["top", "middle", "bottom"])
    }

    @Test("Blocks on the same line are ordered left to right")
    func ordersHorizontallyWithinALine() {
        let blocks = [
            block("right", x: 300, y: 10),
            block("left", x: 0, y: 12),
            block("centre", x: 150, y: 8)
        ]

        // All three sit within the tolerance of one another, so they form one line.
        #expect(blocks.inReadingOrder.map(\.sourceText) == ["left", "centre", "right"])
    }

    /// A large heading next to small body text used to make the comparator
    /// asymmetric, because the tolerance was keyed off `lhs` alone. That
    /// violates the strict weak ordering `sorted(by:)` requires, which makes
    /// the result depend on the input order.
    @Test("Comparator is antisymmetric for mixed text sizes")
    func comparatorIsAntisymmetric() {
        let small = block("small", x: 0, y: 0, height: 20)
        let heading = block("heading", x: 0, y: 40, height: 100)

        let forward = TextBlock.isOrderedBefore(small, heading)
        let backward = TextBlock.isOrderedBefore(heading, small)

        #expect(!(forward && backward), "both orderings can't be true at once")
        #expect(forward)
        #expect(!backward)
    }

    @Test("Ordering never contradicts itself across a whole page")
    func orderingIsConsistent() {
        let blocks = [
            block("title", x: 40, y: 0, height: 90),
            block("subtitle", x: 40, y: 70, height: 18),
            block("label", x: 400, y: 74, height: 20),
            block("body", x: 40, y: 160, height: 22),
            block("badge", x: 620, y: 12, height: 30)
        ]

        for lhs in blocks {
            for rhs in blocks where lhs.id != rhs.id {
                let forward = TextBlock.isOrderedBefore(lhs, rhs)
                let backward = TextBlock.isOrderedBefore(rhs, lhs)
                #expect(
                    !(forward && backward),
                    "\(lhs.sourceText) and \(rhs.sourceText) each claim to come first"
                )
            }
        }
    }

    @Test("Sorting the same blocks twice gives the same order")
    func orderingIsDeterministic() {
        let blocks = [
            block("a", x: 0, y: 0),
            block("b", x: 0, y: 0),
            block("c", x: 0, y: 0)
        ]

        let first = blocks.inReadingOrder.map(\.id)
        let second = blocks.reversed().inReadingOrder.map(\.id)

        #expect(first == second, "identical geometry must still sort deterministically")
    }

    @Test("Plain text export follows reading order")
    @MainActor
    func plainTextUsesReadingOrder() {
        let screenshot = TestFixtures.screenshot(blocks: [
            TestFixtures.block("Zweite", translated: "Second", y: 100),
            TestFixtures.block("Erste", translated: "First", y: 0)
        ])

        #expect(screenshot.plainText(showingOriginal: false) == "First\nSecond")
    }
}
