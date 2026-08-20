//
//  FocusedActions.swift
//  TranslateUI
//

import SwiftUI

/// Actions the active scene publishes so the main menu can invoke them.
///
/// Copy and Export live in `ContentView` (they need the current screenshot and
/// display settings), but they also belong in the menu bar: menu commands give
/// them keyboard shortcuts, keep them reachable when the toolbar collapses into
/// its overflow popup, and make them discoverable.
extension FocusedValues {
    @Entry var copyTranslations: (() -> Void)?
    @Entry var exportAnnotatedImage: (() -> Void)?
}
