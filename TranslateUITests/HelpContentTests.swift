//
//  HelpContentTests.swift
//  TranslateUITests
//

import Foundation
import Testing

@testable import TranslateUI

/// The help book is data, so its structure and search behaviour can be checked
/// without rendering anything.
@Suite("Help content")
struct HelpContentTests {

    // MARK: - Structure

    @Test("Every topic is complete")
    func topicsAreComplete() {
        #expect(!HelpContent.topics.isEmpty)

        for topic in HelpContent.topics {
            #expect(!topic.id.isEmpty, "a topic has no id")
            #expect(!topic.title.isEmpty, "\(topic.id) has no title")
            #expect(!topic.summary.isEmpty, "\(topic.id) has no summary")
            #expect(!topic.symbol.isEmpty, "\(topic.id) has no symbol")
            #expect(!topic.sections.isEmpty, "\(topic.id) has no sections")

            for section in topic.sections {
                #expect(!section.title.isEmpty, "\(topic.id) has an untitled section")
                #expect(!section.blocks.isEmpty, "\(topic.id)/\(section.title) is empty")
                for block in section.blocks {
                    #expect(
                        !block.searchText.trimmingCharacters(in: .whitespaces).isEmpty,
                        "\(topic.id)/\(section.title) has an empty block"
                    )
                }
            }
        }
    }

    @Test("Topic ids are unique")
    func idsAreUnique() {
        let ids = HelpContent.topics.map(\.id)
        #expect(Set(ids).count == ids.count, "duplicate topic ids: \(ids)")
    }

    @Test("Every declared id resolves to a topic")
    func declaredIDsResolve() {
        let declared = [
            HelpContent.ID.gettingStarted,
            HelpContent.ID.languages,
            HelpContent.ID.reading,
            HelpContent.ID.editing,
            HelpContent.ID.exporting,
            HelpContent.ID.performance,
            HelpContent.ID.troubleshooting,
            HelpContent.ID.privacy,
            HelpContent.ID.shortcuts
        ]

        for id in declared {
            #expect(HelpContent.topic(id: id) != nil, "\(id) has no topic")
        }
        #expect(declared.count == HelpContent.topics.count, "a topic isn't reachable by id")
    }

    @Test("Unknown ids return nothing")
    func unknownIDReturnsNil() {
        #expect(HelpContent.topic(id: "no-such-topic") == nil)
    }

    // MARK: - Contextual help

    @Test("Every alert points at a real help topic")
    func alertsHaveValidHelpTopics() {
        let alerts: [PipelineAlert] = [
            .languageUnsupported(.german),
            .languageUnsupported(.italian),
            .languageNeedsDownload(.german),
            .languageNeedsDownload(.italian),
            .translationsFailed(count: 3)
        ]

        for alert in alerts {
            #expect(
                HelpContent.topic(id: alert.helpTopic) != nil,
                "\(alert.id) points at missing topic \(alert.helpTopic)"
            )
        }
    }

    // MARK: - Search

    @Test("An empty search returns the whole book")
    func emptySearchReturnsEverything() {
        #expect(HelpContent.search("").count == HelpContent.topics.count)
        #expect(HelpContent.search("   ").count == HelpContent.topics.count)
    }

    @Test(
        "Searching finds the topic a user would expect",
        arguments: [
            ("italian", HelpContent.ID.languages),
            ("download", HelpContent.ID.languages),
            ("glossary", HelpContent.ID.editing),
            ("export", HelpContent.ID.exporting),
            ("shortcut", HelpContent.ID.shortcuts),
            ("privacy", HelpContent.ID.privacy),
            ("slow", HelpContent.ID.performance),
            ("failed", HelpContent.ID.troubleshooting),
            ("overlay", HelpContent.ID.reading),
            ("drag", HelpContent.ID.gettingStarted)
        ]
    )
    func searchFindsExpectedTopic(query: String, expected: HelpTopic.ID) {
        let results = HelpContent.search(query)
        #expect(
            results.contains { $0.id == expected },
            "“\(query)” didn't find \(expected); got \(results.map(\.id))"
        )
    }

    /// The Help UI test types this term and expects exactly one result, so the
    /// assumption is pinned here rather than left implicit.
    @Test("“shortcut” matches only the shortcuts topic")
    func shortcutSearchIsUnique() {
        let results = HelpContent.search("shortcut")
        #expect(results.map(\.id) == [HelpContent.ID.shortcuts], "got \(results.map(\.id))")
    }

    @Test("The number of topics is what the UI test expects")
    func topicCountIsStable() {
        #expect(HelpContent.topics.count == 9, "update HelpUITests.topicCount to match")
    }

    @Test("Search ignores capitalisation")
    func searchIsCaseInsensitive() {
        #expect(HelpContent.search("GLOSSARY").map(\.id) == HelpContent.search("glossary").map(\.id))
    }

    @Test("Extra words narrow the results")
    func multipleTermsNarrow() {
        let broad = HelpContent.search("language")
        let narrow = HelpContent.search("language download")

        #expect(!narrow.isEmpty)
        #expect(narrow.count <= broad.count, "adding a term should never widen the results")
    }

    @Test("Nonsense finds nothing")
    func unmatchedSearchIsEmpty() {
        #expect(HelpContent.search("zzzqqq").isEmpty)
    }

    @Test("Results stay in book order")
    func resultsKeepBookOrder() {
        let results = HelpContent.search("translation")
        let order = HelpContent.topics.map(\.id)
        let positions = results.compactMap { topic in order.firstIndex(of: topic.id) }

        #expect(positions == positions.sorted(), "search shouldn't reorder the book")
    }

    // MARK: - Shortcuts topic

    @Test("The shortcuts topic lists the app's real shortcuts")
    func shortcutsMatchTheApp() {
        let listed = HelpContent.shortcuts.sections
            .flatMap(\.blocks)
            .compactMap { block -> String? in
                if case .shortcut(let keys, _) = block { return keys }
                return nil
            }

        // These are the key equivalents actually registered in the menus.
        for expected in ["⌘O", "⌘R", "⇧⌘C", "⌘E", "⌘?"] {
            #expect(listed.contains(expected), "\(expected) is missing from the shortcuts topic")
        }
    }
}

@Suite("Help centre")
@MainActor
struct HelpCenterTests {

    @Test("Opens on the first topic by default")
    func defaultsToFirstTopic() {
        let help = HelpCenter()
        #expect(help.selection == HelpContent.topics.first?.id)
        #expect(help.selectedTopic != nil)
    }

    @Test("Preparing a topic selects it and clears the search")
    func prepareClearsSearch() {
        let help = HelpCenter()
        help.searchText = "glossary"

        help.prepare(topic: HelpContent.ID.privacy)

        #expect(help.selection == HelpContent.ID.privacy)
        #expect(help.searchText.isEmpty, "a stale search would hide the topic we just opened")
        #expect(help.selectedTopic?.id == HelpContent.ID.privacy)
    }

    @Test("Visible topics follow the search")
    func visibleTopicsFollowSearch() {
        let help = HelpCenter()
        #expect(help.visibleTopics.count == HelpContent.topics.count)

        help.searchText = "glossary"

        #expect(help.visibleTopics.contains { $0.id == HelpContent.ID.editing })
        #expect(help.visibleTopics.count < HelpContent.topics.count)
    }
}
