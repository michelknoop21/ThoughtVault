// DraftReviewSection.swift
// Collapsed warning block above the approved notule when local generation
// was rejected by the audit and only a draft was stored.

import SwiftUI

struct DraftReviewSection: View {
    let reason: String
    let draftHtml: String

    @State private var isExpanded = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: TS.Spacing.sm) {
                Text(reason)
                    .font(TS.Font.caption)
                    .foregroundStyle(Color.labelSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HTMLWebView(htmlContent: NotuleAudit.draftForReview(draftHtml), isDarkMode: colorScheme == .dark)
                    .frame(height: 280)
            }
            .padding(.top, TS.Spacing.xs)
        } label: {
            Label("Concept, niet gevalideerd", systemImage: "exclamationmark.triangle")
                .font(TS.Font.footnoteSemibold)
                .foregroundStyle(Color.statusWarning)
        }
        .padding(TS.Spacing.md)
        .background(Color.statusWarning.opacity(0.08), in: RoundedRectangle(cornerRadius: TS.Radius.md, style: .continuous))
        .padding(.horizontal, TS.Spacing.md)
        .padding(.top, TS.Spacing.sm)
    }
}
