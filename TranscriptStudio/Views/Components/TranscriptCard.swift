// TranscriptCard.swift
// TranscriptStudio
// nl.prezent.TranscriptStudio
//
// Reusable card component for displaying transcript list items
// with title, date, preview, tags, duration, and completion badge.
// Uses the APIService.Transcript type which is the shared model across views.

import SwiftUI

// MARK: - TranscriptCard

struct TranscriptCard: View {

    let transcript: Transcript
    let onTap: () -> Void
    let onDelete: (() -> Void)?

    @State private var isHovered: Bool = false

    init(
        transcript: Transcript,
        onTap: @escaping () -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        self.transcript = transcript
        self.onTap = onTap
        self.onDelete = onDelete
    }

    var body: some View {
        Button(action: onTap) {
            cardContent
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .contextMenu {
            contextMenuItems
        }
    }

    // MARK: - Card Content

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: TS.Spacing.sm) {
            // Header row: title + completed badge
            HStack(alignment: .top, spacing: TS.Spacing.sm) {
                Text(transcript.title)
                    .font(TS.Font.headlineBold)
                    .foregroundStyle(Color.labelPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Static "Voltooid" badge
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                    Text("Voltooid")
                        .font(TS.Font.microSemibold)
                }
                .foregroundStyle(Color.statusSuccess)
                .padding(.horizontal, TS.Spacing.sm)
                .padding(.vertical, TS.Spacing.xs)
                .background(Color.statusSuccess.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: TS.Radius.xs))
            }

            // Date + duration row
            HStack(spacing: TS.Spacing.sm) {
                if let dateStr = transcript.createdAt {
                    Image(systemName: "calendar")
                        .font(TS.Font.caption)
                        .foregroundStyle(Color.labelTertiary)
                    Text(formattedDate(dateStr))
                        .font(TS.Font.captionMonospaced)
                        .foregroundStyle(Color.labelTertiary)
                }

                if let duration = transcript.duration {
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(TS.Font.caption)
                        Text(formattedDuration(duration))
                            .font(TS.Font.captionMonospaced)
                    }
                    .foregroundStyle(Color.labelTertiary)
                }
            }

            // Profile name chip (if present)
            if let profileName = transcript.profileName {
                HStack(spacing: 4) {
                    Image(systemName: "person.text.rectangle")
                        .font(.system(size: 10))
                    Text(profileName)
                        .font(TS.Font.micro)
                }
                .foregroundStyle(Color.brandSecondary)
                .padding(.horizontal, TS.Spacing.sm)
                .padding(.vertical, 2)
                .background(Color.brandSecondary.opacity(0.08))
                .clipShape(Capsule())
            }

            // Transcription preview
            if let preview = transcriptPreview {
                Text(preview)
                    .font(TS.Font.footnote)
                    .foregroundStyle(Color.labelSecondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }

            // Tags
            if !transcript.tags.isEmpty {
                tagsView
            }
        }
        .padding(TS.Spacing.md)
        .modernCard(isHovered: isHovered)
    }

    // MARK: - Tags

    private var tagsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: TS.Spacing.xs) {
                ForEach(transcript.tags, id: \.self) { tag in
                    Text(tag)
                        .font(TS.Font.microSemibold)
                        .foregroundStyle(Color.brandSecondary)
                        .padding(.horizontal, TS.Spacing.sm)
                        .padding(.vertical, 3)
                        .background(Color.brandSecondary.opacity(0.10))
                        .clipShape(Capsule())
                }
            }
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var contextMenuItems: some View {
        Button {
            onTap()
        } label: {
            Label("Openen", systemImage: "doc.richtext")
        }

        if let deleteAction = onDelete {
            Divider()
            Button(role: .destructive, action: deleteAction) {
                Label("Verwijderen", systemImage: "trash")
            }
        }
    }

    // MARK: - Formatting Helpers

    private func formattedDate(_ dateString: String) -> String {
        let parsedDate: Date? = {
            // Try ISO8601 with fractional seconds
            let isoFrac = ISO8601DateFormatter()
            isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = isoFrac.date(from: dateString) { return d }
            // Try standard ISO8601
            let iso = ISO8601DateFormatter()
            if let d = iso.date(from: dateString) { return d }
            // Fallback: "yyyy-MM-dd HH:mm:ss"
            let fallback = DateFormatter()
            fallback.dateFormat = "yyyy-MM-dd HH:mm:ss"
            fallback.locale = Locale(identifier: "en_US_POSIX")
            fallback.timeZone = TimeZone(identifier: "UTC")
            return fallback.date(from: dateString)
        }()
        guard let date = parsedDate else { return dateString }
        let df = DateFormatter()
        df.locale = Locale(identifier: "nl_NL")
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: date)
    }

    private var transcriptPreview: String? {
        guard let raw = transcript.rawTranscription, !raw.isEmpty else { return nil }
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(cleaned.prefix(200))
    }

    private func formattedDuration(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: TS.Spacing.md) {
            TranscriptCard(
                transcript: Transcript(
                    id: "1",
                    title: "Weeklymeeting Design & Engineering — Sprint Review",
                    rawTranscription: "Vandaag bespraken we de voortgang van sprint 24. Michel presenteerde de nieuwe transcriptie-feature.",
                    notuleHtml: "<h1>Notulen</h1>",
                    tags: ["sprint", "design", "engineering"],
                    createdAt: "2026-03-04T10:30:00.000Z",
                    duration: 2847,
                    profileName: "Zakelijk"
                ),
                onTap: {},
                onDelete: {}
            )

            TranscriptCard(
                transcript: Transcript(
                    id: "2",
                    title: "Klantgesprek Acme Corp",
                    rawTranscription: "Kennismaking met de nieuwe contactpersoon bij Acme.",
                    tags: ["klant", "acme"],
                    createdAt: "2026-03-03T14:00:00.000Z",
                    profileName: "Informeel"
                ),
                onTap: {}
            )
        }
        .padding()
    }
    .frame(width: 420, height: 500)
}
