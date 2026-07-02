// ParticipantPickerSheet.swift
// TranscriptStudio
// com.buildmind.ThoughtVault
//
// Multi-select picker over the people directory. Lets the user mark who is in an
// ad-hoc meeting (no calendar link) so the recording still carries a deelnemerslijst
// into the notule pipeline. Calendar attendees are resolved automatically at upload;
// this sheet only adds manual picks on top.

import SwiftUI

// MARK: - ParticipantPickerSheet

struct ParticipantPickerSheet: View {

    /// Directory person IDs selected for the current recording.
    @Binding var selectedIDs: [String]

    @Environment(\.dismiss) private var dismiss

    private let service = PersonDirectoryService.shared
    @State private var people: [PersonProfile] = []
    @State private var searchText: String = ""

    private var selected: Set<String> {
        get { Set(selectedIDs) }
    }

    private var filteredPeople: [PersonProfile] {
        guard !searchText.isEmpty else { return people }
        let query = searchText.lowercased()
        return people.filter { person in
            person.name.lowercased().contains(query)
            || person.aliases.contains { $0.lowercased().contains(query) }
            || person.organization.lowercased().contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: TS.Spacing.md) {
                Text("Deelnemers kiezen")
                    .font(TS.Font.title3Semibold)
                    .foregroundStyle(Color.labelPrimary)

                Text("Selecteer wie aanwezig is. Deze namen komen in de notule en acties kunnen aan hen worden gekoppeld.")
                    .font(TS.Font.footnote)
                    .foregroundStyle(Color.labelSecondary)

                if people.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .padding(TS.Spacing.lg)
            .frame(minWidth: 420, minHeight: 480)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gereed") { dismiss() }
                        .buttonStyle(PrimaryButtonStyle())
                }
            }
        }
        .onAppear { people = service.directoryPeople() }
    }

    // MARK: - List

    private var list: some View {
        List {
            if !searchText.isEmpty && filteredPeople.isEmpty {
                Text("Geen resultaten voor '\(searchText)'")
                    .font(TS.Font.footnote)
                    .foregroundStyle(Color.labelSecondary)
            } else {
                ForEach(filteredPeople) { person in
                    row(person)
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $searchText, prompt: "Zoeken...")
    }

    private func row(_ person: PersonProfile) -> some View {
        let isOn = selected.contains(person.id)
        return Button {
            toggle(person.id)
        } label: {
            HStack(spacing: TS.Spacing.sm) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isOn ? Color.brandPrimary : Color.labelTertiary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(person.name.isEmpty ? "Naamloos" : person.name)
                        .font(TS.Font.headline)
                        .foregroundStyle(Color.labelPrimary)
                        .lineLimit(1)

                    let subtitle = [person.role, person.organization]
                        .filter { !$0.isEmpty }
                        .joined(separator: " · ")
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(TS.Font.footnote)
                            .foregroundStyle(Color.labelSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.vertical, TS.Spacing.xs)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: TS.Spacing.md) {
            Image(systemName: "person.2")
                .font(.system(size: 40))
                .foregroundStyle(Color.labelTertiary)
            Text("Nog geen personen in de directory")
                .font(TS.Font.headline)
                .foregroundStyle(Color.labelPrimary)
            Text("Voeg eerst mensen toe via Instellingen → Mensen.")
                .font(TS.Font.footnote)
                .foregroundStyle(Color.labelSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(TS.Spacing.xl)
    }

    // MARK: - Toggle

    private func toggle(_ id: String) {
        if let idx = selectedIDs.firstIndex(of: id) {
            selectedIDs.remove(at: idx)
        } else {
            selectedIDs.append(id)
        }
    }
}
