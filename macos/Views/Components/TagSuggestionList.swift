// TagSuggestionList.swift
// ThoughtVault
// com.buildmind.ThoughtVault
//
// Clickable list of existing tags shown under a tag input field, filtered on
// the typed prefix and excluding tags already assigned. Call sites keep their
// own field styling; this only renders the suggestions.

import SwiftUI

struct TagSuggestionList: View {

    let allTags: [String]
    let currentTags: [String]
    let query: String
    let onSelect: (String) -> Void

    private static let maxVisible = 6

    private var matches: [String] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return allTags
            .filter { !currentTags.contains($0) }
            .filter { q.isEmpty || $0.lowercased().hasPrefix(q) }
            .prefix(Self.maxVisible)
            .map { $0 }
    }

    var body: some View {
        if !matches.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(matches, id: \.self) { tag in
                    Button {
                        onSelect(tag)
                    } label: {
                        HStack(spacing: TS.Spacing.xs) {
                            Image(systemName: "tag")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.brandSecondary)
                            Text(tag)
                                .font(TS.Font.captionMedium)
                                .foregroundStyle(Color.labelPrimary)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, TS.Spacing.sm)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .accessibilityLabel("Bestaande tags")
        }
    }
}
