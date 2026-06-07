// SeedReviewSheet.swift
// TranscriptStudio
// nl.prezent.TranscriptStudio
//
// Per-person confirm sheet after recording stops with new calendar attendees.
// No auto-commit (D-07 / T-02-06): only confirmed (checked) entries are persisted.
// Unchecked or skipped entries are never written to the directory.

import SwiftUI

// MARK: - SeedCandidate

private struct SeedCandidate: Identifiable {
    let id = UUID()
    let email: String
    var isChecked: Bool = true

    /// Display name derived from the email prefix if no Graph displayName is available.
    var displayName: String {
        let prefix = email.components(separatedBy: "@").first ?? email
        return prefix
            .components(separatedBy: CharacterSet(charactersIn: "._-"))
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}

// MARK: - SeedReviewSheet

struct SeedReviewSheet: View {

    // MARK: - Input

    /// Deduplicated new attendee emails (self and known already excluded by caller).
    let candidates: [String]
    let onDismiss: () -> Void

    // MARK: - State

    @State private var rows: [SeedCandidate] = []
    @State private var isSaving: Bool = false
    @State private var saveError: String? = nil

    private var checkedCount: Int { rows.filter(\.isChecked).count }

    private var primaryButtonLabel: String {
        if checkedCount == 1 {
            return "Voeg 1 persoon toe"
        }
        return "Voeg \(checkedCount) personen toe"
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: TS.Spacing.lg) {
            // Header
            VStack(alignment: .leading, spacing: TS.Spacing.xs) {
                Text("Nieuwe deelnemers gevonden")
                    .font(TS.Font.title3Semibold)
                    .foregroundStyle(Color.labelPrimary)

                Text("\(candidates.count) deelnemers uit je agenda staan nog niet in je directory.")
                    .font(TS.Font.footnote)
                    .foregroundStyle(Color.labelSecondary)
            }

            // Per-person rows
            List {
                ForEach($rows) { $row in
                    HStack(spacing: TS.Spacing.sm) {
                        Toggle(isOn: $row.isChecked) {
                            EmptyView()
                        }
                        .toggleStyle(.checkbox)
                        .accessibilityLabel(row.displayName)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.displayName)
                                .font(TS.Font.headline)
                                .foregroundStyle(Color.labelPrimary)
                                .lineLimit(1)

                            Text(row.email)
                                .font(TS.Font.footnote)
                                .foregroundStyle(Color.labelSecondary)
                                .lineLimit(1)
                        }

                        Spacer()
                    }
                    .frame(minHeight: 48)
                    .padding(.vertical, TS.Spacing.xs)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        row.isChecked.toggle()
                    }
                }
            }
            .listStyle(.plain)
            .frame(minHeight: 120)

            // Save error feedback
            if let error = saveError {
                Text(error)
                    .font(TS.Font.caption)
                    .foregroundStyle(Color.statusError)
            }

            // Action buttons
            HStack(spacing: TS.Spacing.sm) {
                Button("Overslaan") {
                    // Skip: nothing persisted (D-07)
                    onDismiss()
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(isSaving)

                Spacer()

                Button {
                    saveSelected()
                } label: {
                    if isSaving {
                        HStack(spacing: TS.Spacing.xs) {
                            ProgressView()
                                .controlSize(.small)
                            Text(primaryButtonLabel)
                        }
                    } else {
                        Text(primaryButtonLabel)
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(checkedCount == 0 || isSaving)
            }
        }
        .padding(TS.Spacing.lg)
        .frame(minWidth: 400, minHeight: 300)
        .onAppear {
            rows = candidates.map { SeedCandidate(email: $0) }
        }
    }

    // MARK: - Save

    private func saveSelected() {
        isSaving = true
        let service = PersonDirectoryService()
        do {
            for row in rows where row.isChecked {
                // seedPerson builds a PersonProfile with isInternal = nil (D-09)
                let candidate = service.seedPerson(name: row.displayName, email: row.email)
                try service.add(candidate)
            }
        } catch {
            isSaving = false
            // Surface save error — sheet stays open so the user can retry or dismiss
            saveError = "Opslaan mislukt: \(error.localizedDescription)"
            return
        }
        isSaving = false
        onDismiss()
    }
}
