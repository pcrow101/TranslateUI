//
//  HelpView.swift
//  TranslateUI
//

import SwiftUI

/// The in-app help book: searchable topic list with the selected page beside it.
struct HelpView: View {
    @Environment(HelpCenter.self) private var help

    var body: some View {
        @Bindable var help = help

        NavigationSplitView {
            List(help.visibleTopics, selection: $help.selection) { topic in
                NavigationLink(value: topic.id) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(topic.title)
                            Text(topic.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    } icon: {
                        Image(systemName: topic.symbol)
                            .foregroundStyle(.tint)
                    }
                    .padding(.vertical, 2)
                }
                .accessibilityIdentifier("help.topic")
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
            .accessibilityIdentifier("help.topicList")
            .overlay {
                if help.visibleTopics.isEmpty {
                    ContentUnavailableView.search(text: help.searchText)
                }
            }
        } detail: {
            detail
        }
        .searchable(
            text: $help.searchText,
            placement: .sidebar,
            prompt: Text("Search Help")
        )
        .navigationTitle("Translate UI Help")
        .frame(minWidth: 720, minHeight: 480)
    }

    @ViewBuilder
    private var detail: some View {
        if let topic = help.selectedTopic {
            HelpTopicView(topic: topic)
                .id(topic.id)
        } else {
            ContentUnavailableView(
                "Choose a Topic",
                systemImage: "questionmark.circle",
                description: Text("Pick a topic on the left, or search for what you need.")
            )
        }
    }
}

/// One rendered help page.
private struct HelpTopicView: View {
    let topic: HelpTopic

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                ForEach(topic.sections) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(section.title)
                            .font(.headline)

                        // Steps are numbered across the whole section.
                        let steps = section.blocks.filter(\.isStep)
                        ForEach(section.blocks) { block in
                            HelpBlockView(
                                block: block,
                                stepNumber: block.isStep
                                    ? (steps.firstIndex(of: block).map { $0 + 1 }) : nil
                            )
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .accessibilityIdentifier("help.topicDetail")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(topic.title, systemImage: topic.symbol)
                .font(.title2.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .accessibilityIdentifier("help.title")

            Text(topic.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

/// Renders a single block of help content.
private struct HelpBlockView: View {
    let block: HelpBlock
    let stepNumber: Int?

    var body: some View {
        switch block {
        case .paragraph(let text):
            Text(text)
                .fixedSize(horizontal: false, vertical: true)

        case .step(let text):
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(stepNumber ?? 1)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(.tint, in: .circle)
                Text(text)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 5))
                    .foregroundStyle(.tint)
                Text(text)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .shortcut(let keys, let action):
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(keys)
                    .font(.body.monospaced().weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: .rect(cornerRadius: 6))
                    .frame(minWidth: 62, alignment: .leading)
                Text(action)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .tip(let text):
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(.yellow)
                Text(text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: .rect(cornerRadius: 10))
        }
    }
}

extension HelpBlock {
    var isStep: Bool {
        if case .step = self { return true }
        return false
    }
}

#Preview {
    HelpView()
        .environment(HelpCenter())
        .frame(width: 900, height: 600)
}
