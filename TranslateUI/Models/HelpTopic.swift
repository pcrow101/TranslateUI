//
//  HelpTopic.swift
//  TranslateUI
//

import Foundation

/// A single block of help content.
///
/// Modelled as data rather than hand-built views so the whole help book can be
/// searched, counted and tested without rendering anything.
nonisolated enum HelpBlock: Hashable, Sendable, Identifiable {
    case paragraph(String)
    /// A numbered instruction. Steps are numbered in the order they appear.
    case step(String)
    case bullet(String)
    /// A keyboard shortcut and what it does, e.g. `("⌘O", "Open screenshots")`.
    case shortcut(keys: String, action: String)
    /// A highlighted aside.
    case tip(String)

    var id: String {
        switch self {
        case .paragraph(let text): "p:\(text)"
        case .step(let text): "s:\(text)"
        case .bullet(let text): "b:\(text)"
        case .shortcut(let keys, let action): "k:\(keys):\(action)"
        case .tip(let text): "t:\(text)"
        }
    }

    /// The words this block contributes to search.
    var searchText: String {
        switch self {
        case .paragraph(let text), .step(let text), .bullet(let text), .tip(let text):
            text
        case .shortcut(let keys, let action):
            "\(keys) \(action)"
        }
    }
}

/// A named group of blocks within a topic.
nonisolated struct HelpSection: Hashable, Sendable, Identifiable {
    let title: String
    let blocks: [HelpBlock]

    var id: String { title }

    init(_ title: String, _ blocks: [HelpBlock]) {
        self.title = title
        self.blocks = blocks
    }

    var searchText: String {
        ([title] + blocks.map(\.searchText)).joined(separator: " ")
    }
}

/// One page of the in-app help book.
nonisolated struct HelpTopic: Hashable, Sendable, Identifiable {
    let id: String
    let title: String
    let symbol: String
    /// One-line description, shown under the title in the sidebar.
    let summary: String
    /// Extra terms a user might search for that don't appear in the prose.
    let keywords: [String]
    let sections: [HelpSection]

    init(
        id: String,
        title: String,
        symbol: String,
        summary: String,
        keywords: [String] = [],
        sections: [HelpSection]
    ) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.summary = summary
        self.keywords = keywords
        self.sections = sections
    }

    /// Everything a search should look at, lowercased once up front.
    var searchText: String {
        ([title, summary] + keywords + sections.map(\.searchText))
            .joined(separator: " ")
            .lowercased()
    }

    /// Whether this topic matches a user's query.
    ///
    /// Every whitespace-separated word must appear somewhere in the topic, so
    /// "italian glossary" narrows rather than widens the results.
    func matches(_ query: String) -> Bool {
        let terms = query.lowercased().split(whereSeparator: \.isWhitespace)
        guard !terms.isEmpty else { return true }
        let haystack = searchText
        return terms.allSatisfy { haystack.contains($0) }
    }
}
