//
//  HelpCenter.swift
//  TranslateUI
//

import Foundation
import Observation

/// Tracks which help topic the Help window should be showing.
///
/// The help book is a single `Window` scene rather than a `WindowGroup`, so
/// opening help "in context" is done by setting the selection here and then
/// asking for the window. That keeps one Help window rather than stacking up a
/// new one per topic.
@MainActor
@Observable
final class HelpCenter {
    /// The window identifier used by `openWindow`.
    static let windowID = "help"

    var selection: HelpTopic.ID?
    var searchText = ""

    init(selection: HelpTopic.ID? = HelpContent.topics.first?.id) {
        self.selection = selection
    }

    /// Prepares the window to show `id`, clearing any leftover search so the
    /// topic is actually visible in the list.
    func prepare(topic id: HelpTopic.ID) {
        searchText = ""
        selection = id
    }

    var selectedTopic: HelpTopic? {
        guard let selection else { return nil }
        return HelpContent.topic(id: selection)
    }

    /// Topics matching the current search.
    var visibleTopics: [HelpTopic] {
        HelpContent.search(searchText)
    }
}
