//
//  HelpContent.swift
//  TranslateUI
//

import Foundation

/// The in-app help book.
///
/// Content lives here as data so it can be searched and covered by tests. Topic
/// ids are referenced from the UI (banners, the empty state, Settings) to open
/// help in context, and `HelpContentTests` checks those references resolve.
nonisolated enum HelpContent {
    /// Stable ids for topics referenced from elsewhere in the app.
    enum ID {
        static let gettingStarted = "getting-started"
        static let languages = "languages"
        static let reading = "reading-translations"
        static let editing = "editing-and-glossary"
        static let exporting = "exporting"
        static let performance = "performance"
        static let troubleshooting = "troubleshooting"
        static let privacy = "privacy"
        static let shortcuts = "shortcuts"
    }

    static let topics: [HelpTopic] = [
        gettingStarted,
        languages,
        readingTranslations,
        editingAndGlossary,
        exporting,
        performance,
        troubleshooting,
        privacy,
        shortcuts
    ]

    static func topic(id: HelpTopic.ID) -> HelpTopic? {
        topics.first { $0.id == id }
    }

    /// Topics matching `query`, in book order. An empty query returns everything.
    static func search(_ query: String) -> [HelpTopic] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return topics }
        return topics.filter { $0.matches(trimmed) }
    }

    // MARK: - Topics

    static let gettingStarted = HelpTopic(
        id: ID.gettingStarted,
        title: String(localized: "Getting Started"),
        symbol: "sparkles",
        summary: String(localized: "Import a screenshot and read the translation."),
        keywords: ["import", "drag", "drop", "paste", "open", "begin", "first"],
        sections: [
            HelpSection(
                String(localized: "Import a screenshot"),
                [
                    .paragraph(
                        String(
                            localized:
                                "Translate UI reads German and Italian text in pictures of a TV or streaming-device interface and shows you the English."
                        )),
                    .step(String(localized: "Drag one or more image files onto the window.")),
                    .step(String(localized: "Or choose File ▸ Open Screenshots… (⌘O).")),
                    .step(
                        String(
                            localized:
                                "Or copy an image anywhere on your Mac and click Paste Screenshot.")),
                    .tip(
                        String(
                            localized:
                                "You can import a whole batch at once. Each screenshot is processed on its own, and the sidebar shows the progress of each."
                        ))
                ]
            ),
            HelpSection(
                String(localized: "What happens next"),
                [
                    .bullet(
                        String(localized: "Text is found in the image, shown as “Reading text…”.")),
                    .bullet(
                        String(
                            localized:
                                "Each line is identified as German, Italian or English. English is left alone.")
                    ),
                    .bullet(String(localized: "The rest is translated, shown as “Translating…”.")),
                    .bullet(
                        String(
                            localized:
                                "If Apple Intelligence is available, the wording is polished to match normal interface English — “Refining…”."
                        )),
                    .paragraph(
                        String(
                            localized:
                                "When a screenshot says “Ready”, everything on it has been dealt with."))
                ]
            )
        ]
    )

    static let languages = HelpTopic(
        id: ID.languages,
        title: String(localized: "Languages & Downloads"),
        symbol: "globe",
        summary: String(localized: "German and Italian packs, and what to do if one is missing."),
        keywords: [
            "german", "italian", "deutsch", "italiano", "download", "pack", "install",
            "unavailable", "unsupported", "system settings"
        ],
        sections: [
            HelpSection(
                String(localized: "Supported languages"),
                [
                    .paragraph(
                        String(
                            localized:
                                "German and Italian are translated into English. Lines already in English are passed through unchanged."
                        )),
                    .paragraph(
                        String(
                            localized:
                                "A screen can mix languages. Each line is identified separately, and the language of the screen as a whole is used to settle short labels that could be either."
                        ))
                ]
            ),
            HelpSection(
                String(localized: "Downloading a language"),
                [
                    .paragraph(
                        String(
                            localized:
                                "Translation runs on your Mac, so each language needs a one-off download the first time you use it."
                        )),
                    .step(
                        String(
                            localized:
                                "If a banner says a language needs downloading, click Download.")),
                    .step(String(localized: "macOS asks for confirmation and fetches the language.")),
                    .step(
                        String(
                            localized: "Translation continues by itself once the download finishes.")
                    ),
                    .tip(
                        String(
                            localized:
                                "You can also manage these in System Settings ▸ General ▸ Language & Region, under Translation Languages."
                        ))
                ]
            ),
            HelpSection(
                String(localized: "If a language isn’t available"),
                [
                    .paragraph(
                        String(
                            localized:
                                "Some Macs and regions can’t translate every pair. When that happens the affected lines are marked as skipped and left in the original language, so you can still read and copy them."
                        ))
                ]
            )
        ]
    )

    static let readingTranslations = HelpTopic(
        id: ID.reading,
        title: String(localized: "Reading Translations"),
        symbol: "rectangle.on.rectangle",
        summary: String(localized: "Overlay, side by side and list views."),
        keywords: [
            "overlay", "side by side", "list", "table", "inspector", "original", "chip", "view"
        ],
        sections: [
            HelpSection(
                String(localized: "Three ways to look at a screenshot"),
                [
                    .bullet(
                        String(
                            localized:
                                "Overlay places the English text on top of the original, in the same position.")
                    ),
                    .bullet(
                        String(
                            localized: "Side by Side shows the picture and a table of lines together.")
                    ),
                    .bullet(
                        String(localized: "Text List shows every line as a table you can sort and copy.")
                    ),
                    .paragraph(
                        String(
                            localized: "Switch between them with the control at the top of the window.")
                    )
                ]
            ),
            HelpSection(
                String(localized: "Showing the original text"),
                [
                    .paragraph(
                        String(
                            localized:
                                "Turn on Show Original to display the German or Italian underneath each translation. It’s useful when you want to check a term or quote the original wording."
                        )),
                    .tip(
                        String(
                            localized:
                                "Labels are sized to the text they cover, so a long German word may make its label wider than the original."
                        ))
                ]
            ),
            HelpSection(
                String(localized: "The text list"),
                [
                    .paragraph(
                        String(
                            localized:
                                "The panel on the right lists every line that was found, in reading order, with the language it was identified as and its current status."
                        )),
                    .bullet(String(localized: "A pencil marks a line you edited yourself.")),
                    .bullet(String(localized: "A bookmark marks a line that came from your glossary.")),
                    .bullet(String(localized: "Sparkles mark wording polished by Apple Intelligence."))
                ]
            )
        ]
    )

    static let editingAndGlossary = HelpTopic(
        id: ID.editing,
        title: String(localized: "Editing & the Glossary"),
        symbol: "character.book.closed",
        summary: String(localized: "Correct a translation once and reuse it everywhere."),
        keywords: [
            "edit", "correct", "glossary", "term", "remember", "consistent", "wording", "revert"
        ],
        sections: [
            HelpSection(
                String(localized: "Correcting a translation"),
                [
                    .step(String(localized: "Double-click a label on the picture, or select it in the list.")),
                    .step(String(localized: "Type the wording you want.")),
                    .step(
                        String(
                            localized:
                                "Tick Remember this term if the same label should always be translated that way."
                        )),
                    .paragraph(
                        String(
                            localized:
                                "Your wording always wins over the automatic translation, and is never overwritten later."
                        ))
                ]
            ),
            HelpSection(
                String(localized: "How the glossary works"),
                [
                    .paragraph(
                        String(
                            localized:
                                "A remembered term is applied to every screenshot you have open and to anything you import afterwards, so the same button is named the same way throughout."
                        )),
                    .paragraph(
                        String(
                            localized:
                                "Remembered terms are also given to Apple Intelligence when it polishes wording, so it follows your terminology instead of inventing its own."
                        )),
                    .bullet(
                        String(
                            localized:
                                "Manage your terms in Settings ▸ Glossary, where you can search and remove them."
                        )),
                    .bullet(
                        String(
                            localized:
                                "Removing a term reverts affected lines to the automatic translation.")),
                    .bullet(
                        String(
                            localized:
                                "Matching ignores capitalisation and surrounding spaces."))
                ]
            )
        ]
    )

    static let exporting = HelpTopic(
        id: ID.exporting,
        title: String(localized: "Copying & Exporting"),
        symbol: "square.and.arrow.up",
        summary: String(localized: "Get the text or an annotated picture out of the app."),
        keywords: ["copy", "export", "png", "image", "save", "share", "clipboard", "paste"],
        sections: [
            HelpSection(
                String(localized: "Copying the text"),
                [
                    .paragraph(
                        String(
                            localized:
                                "Edit ▸ Copy All Translations (⇧⌘C) copies every line of the selected screenshot in reading order."
                        )),
                    .tip(
                        String(
                            localized:
                                "With Show Original turned on, the copied text includes the original alongside each translation."
                        )),
                    .paragraph(
                        String(
                            localized: "You can also select and copy individual lines from the text list.")
                    )
                ]
            ),
            HelpSection(
                String(localized: "Exporting a picture"),
                [
                    .paragraph(
                        String(
                            localized:
                                "File ▸ Export Annotated Image… (⌘E) saves a PNG of the screenshot with the English text drawn onto it, at the original size."
                        )),
                    .paragraph(
                        String(
                            localized:
                                "What you see is what gets saved, so set the display mode and Show Original the way you want before exporting."
                        ))
                ]
            )
        ]
    )

    static let performance = HelpTopic(
        id: ID.performance,
        title: String(localized: "Speed & Quality"),
        symbol: "speedometer",
        summary: String(localized: "Settings that trade accuracy against time."),
        keywords: [
            "slow", "fast", "speed", "quality", "refinement", "apple intelligence", "confidence",
            "batch", "performance"
        ],
        sections: [
            HelpSection(
                String(localized: "If a batch is taking a long time"),
                [
                    .paragraph(
                        String(
                            localized:
                                "The polishing pass that improves wording is by far the slowest step, and it runs on each screenshot in turn. Importing a large batch with it switched on can take several minutes."
                        )),
                    .bullet(
                        String(
                            localized:
                                "Turn off Polish wording in Settings ▸ General for much faster results with slightly rougher English."
                        )),
                    .bullet(
                        String(
                            localized:
                                "Set Translation quality to Fastest for shorter waits on long menu descriptions."
                        ))
                ]
            ),
            HelpSection(
                String(localized: "Recognition confidence"),
                [
                    .paragraph(
                        String(
                            localized:
                                "The confidence setting decides how certain the app must be before it keeps a line of text. Raise it to drop noise from compression artefacts, lower it to catch faint or small text."
                        )),
                    .tip(
                        String(
                            localized:
                                "Changing it re-reads every screenshot you have open, so results stay consistent."
                        ))
                ]
            )
        ]
    )

    static let troubleshooting = HelpTopic(
        id: ID.troubleshooting,
        title: String(localized: "If Something Looks Wrong"),
        symbol: "wrench.and.screwdriver",
        summary: String(localized: "Missing text, wrong language, failed translations."),
        keywords: [
            "missing", "wrong", "failed", "error", "retry", "not translated", "blank", "problem",
            "stuck", "banner"
        ],
        sections: [
            HelpSection(
                String(localized: "Some text wasn’t found"),
                [
                    .bullet(
                        String(
                            localized:
                                "Very small or low-contrast text may fall below the confidence setting — try lowering it in Settings ▸ Recognition."
                        )),
                    .bullet(
                        String(
                            localized:
                                "Heavily compressed captures lose fine detail. A cleaner screenshot usually recognises much better."
                        )),
                    .bullet(String(localized: "Then choose Edit ▸ Re-analyze Screenshot (⌘R).")),
                ]
            ),
            HelpSection(
                String(localized: "A line was translated as the wrong language"),
                [
                    .paragraph(
                        String(
                            localized:
                                "Short labels are ambiguous — several words are spelled the same in German and Italian. The app uses the language of the screen as a whole to settle them, so a screenshot with more text on it is identified more reliably."
                        )),
                    .paragraph(
                        String(
                            localized:
                                "If a particular label is consistently wrong, correct it and tick Remember this term so it is always translated your way."
                        ))
                ]
            ),
            HelpSection(
                String(localized: "A translation failed"),
                [
                    .paragraph(
                        String(
                            localized:
                                "A banner appears above the screenshot with a Try Again button. You can also right-click a single line in the list and choose Retry Translation."
                        )),
                    .tip(
                        String(
                            localized:
                                "Failed lines are never remembered, so re-importing the same screenshot always gives it a fresh attempt."
                        ))
                ]
            )
        ]
    )

    static let privacy = HelpTopic(
        id: ID.privacy,
        title: String(localized: "Privacy"),
        symbol: "lock.shield",
        summary: String(localized: "Everything happens on this Mac."),
        keywords: ["privacy", "offline", "network", "internet", "cloud", "data", "cache"],
        sections: [
            HelpSection(
                String(localized: "Your screenshots stay here"),
                [
                    .paragraph(
                        String(
                            localized:
                                "Reading text, identifying the language, translating and polishing all run on this Mac using the features built into macOS. Your screenshots are never uploaded."
                        )),
                    .paragraph(
                        String(
                            localized:
                                "The only thing that goes over the network is the one-off language download, which macOS handles itself."
                        ))
                ]
            ),
            HelpSection(
                String(localized: "What is stored"),
                [
                    .bullet(
                        String(
                            localized:
                                "Results are cached on disk so re-importing a screenshot is instant. Clear this in Settings ▸ Recognition."
                        )),
                    .bullet(
                        String(
                            localized: "Your glossary is stored on disk so it survives quitting the app.")
                    ),
                    .bullet(
                        String(
                            localized:
                                "Imported screenshots themselves are not copied — the app reads the files you point it at."
                        ))
                ]
            )
        ]
    )

    static let shortcuts = HelpTopic(
        id: ID.shortcuts,
        title: String(localized: "Keyboard Shortcuts"),
        symbol: "keyboard",
        summary: String(localized: "Every shortcut in one place."),
        keywords: ["keyboard", "shortcut", "key", "command", "hotkey"],
        sections: [
            HelpSection(
                String(localized: "Screenshots"),
                [
                    .shortcut(keys: "⌘O", action: String(localized: "Open screenshots")),
                    .shortcut(keys: "⌘V", action: String(localized: "Paste a screenshot")),
                    .shortcut(keys: "⌘R", action: String(localized: "Re-analyze the selected screenshot"))
                ]
            ),
            HelpSection(
                String(localized: "Getting results out"),
                [
                    .shortcut(keys: "⇧⌘C", action: String(localized: "Copy all translations")),
                    .shortcut(keys: "⌘E", action: String(localized: "Export an annotated image"))
                ]
            ),
            HelpSection(
                String(localized: "App"),
                [
                    .shortcut(keys: "⌘,", action: String(localized: "Settings")),
                    .shortcut(keys: "⌘?", action: String(localized: "Translate UI Help"))
                ]
            )
        ]
    )
}
