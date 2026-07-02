// PeopleDirectoryView.swift
// TranscriptStudio
// com.buildmind.ThoughtVault
//
// Searchable directory list for managing people (isSelf == false).
// B-01 / B-02 — add, edit, delete with tri-state intern/extern status.

import SwiftUI

// MARK: - PeopleDirectoryView

struct PeopleDirectoryView: View {

    // MARK: - State

    private let service = PersonDirectoryService.shared
    @State private var people: [PersonProfile] = []
    @State private var searchText: String = ""
    @State private var isLoading: Bool = true
    @State private var loadError: String? = nil

    @State private var showAddSheet = false
    @State private var personToEdit: PersonProfile? = nil
    @State private var personToDelete: PersonProfile? = nil
    @State private var showDeleteConfirmation = false

    // MARK: - Computed

    private var filteredPeople: [PersonProfile] {
        guard !searchText.isEmpty else { return people }
        let query = searchText.lowercased()
        return people.filter { person in
            person.name.lowercased().contains(query)
            || person.aliases.contains { $0.lowercased().contains(query) }
            || person.emails.contains { $0.lowercased().contains(query) }
        }
    }

    // MARK: - Body

    var body: some View {
        Group {
            if isLoading {
                loadingView
            } else if let error = loadError {
                errorView(message: error)
            } else if people.isEmpty {
                emptyStateView
            } else {
                directoryListView
            }
        }
        .searchable(text: $searchText, prompt: "Zoeken...")
        .navigationTitle("Mensen")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddSheet = true
                } label: {
                    Label("Persoon toevoegen", systemImage: "plus")
                }
                .help("Persoon toevoegen")
            }
        }
        .onAppear {
            loadPeople()
        }
        .sheet(isPresented: $showAddSheet, onDismiss: loadPeople) {
            PersonEditView(person: nil, onSave: { _ in
                showAddSheet = false
                loadPeople()
            })
        }
        .sheet(item: $personToEdit, onDismiss: loadPeople) { person in
            PersonEditView(person: person, onSave: { _ in
                personToEdit = nil
                loadPeople()
            })
        }
        .confirmationDialog(
            deleteDialogTitle,
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Verwijderen", role: .destructive) {
                if let person = personToDelete {
                    do {
                        try service.delete(person)
                        loadPeople()
                    } catch {
                        loadError = "Verwijderen mislukt: \(error.localizedDescription)"
                    }
                }
                personToDelete = nil
            }
            Button("Annuleren", role: .cancel) {
                personToDelete = nil
            }
        }
    }

    // MARK: - Delete Dialog Title

    private var deleteDialogTitle: String {
        if let name = personToDelete?.name, !name.isEmpty {
            return "Verwijder \(name)?"
        }
        return "Verwijder persoon?"
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack {
            ProgressView()
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error View

    private func errorView(message: String) -> some View {
        VStack(spacing: TS.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(Color.statusError)
            Text(message)
                .font(TS.Font.body)
                .foregroundStyle(Color.labelSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(TS.Spacing.lg)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: TS.Spacing.md) {
            Image(systemName: "person.2")
                .font(.system(size: 48))
                .foregroundStyle(Color.labelTertiary)

            Text("Nog geen personen toegevoegd")
                .font(TS.Font.headline)
                .foregroundStyle(Color.labelPrimary)

            Text("Voeg collega's en bekende externen toe zodat TranscriptStudio actiepunten aan hen kan koppelen.")
                .font(TS.Font.footnote)
                .foregroundStyle(Color.labelSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            Button {
                showAddSheet = true
            } label: {
                Text("Persoon toevoegen")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(TS.Spacing.xl)
    }

    // MARK: - Directory List

    private var directoryListView: some View {
        List {
            if !searchText.isEmpty && filteredPeople.isEmpty {
                noSearchResultsView
            } else {
                ForEach(filteredPeople) { person in
                    personRow(person)
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - No Search Results

    private var noSearchResultsView: some View {
        HStack {
            Spacer()
            Text("Geen resultaten voor '\(searchText)'")
                .font(TS.Font.footnote)
                .foregroundStyle(Color.labelSecondary)
                .padding(.vertical, TS.Spacing.md)
            Spacer()
        }
    }

    // MARK: - Person Row

    private func personRow(_ person: PersonProfile) -> some View {
        HStack(spacing: TS.Spacing.sm) {
            // Status dot
            Circle()
                .fill(statusColor(for: person.isInternal))
                .frame(width: 8, height: 8)
                .padding(.top, 2)
                .accessibilityHidden(true)

            // Name + role/organisation
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
            .frame(maxWidth: .infinity, alignment: .leading)

            // Status tag — text, not colour alone (WCAG 1.4.1); also gives VoiceOver
            // the intern/extern meaning the colour dot can't convey.
            Text(statusText(for: person.isInternal))
                .font(TS.Font.caption)
                .foregroundStyle(statusColor(for: person.isInternal))
                .padding(.horizontal, TS.Spacing.sm)
                .padding(.vertical, 2)
                .background(Capsule().fill(statusColor(for: person.isInternal).opacity(0.12)))

            // Trailing actions
            HStack(spacing: TS.Spacing.xs) {
                Button {
                    personToEdit = person
                } label: {
                    Image(systemName: "pencil")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.labelSecondary)
                .accessibilityLabel("Bewerk \(person.name)")
                .help("Bewerk \(person.name)")

                Button {
                    personToDelete = person
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.statusError)
                .accessibilityLabel("Verwijder \(person.name)")
                .help("Verwijder \(person.name)")
            }
        }
        .padding(.horizontal, TS.Spacing.md)
        .padding(.vertical, TS.Spacing.sm)
    }

    // MARK: - Status Color

    private func statusColor(for isInternal: Bool?) -> Color {
        switch isInternal {
        case true:  return Color.brandAccent   // Intern — green
        case false: return Color.brandSecondary // Extern — blue
        case nil:   return Color.labelTertiary  // Onbekend — gray
        }
    }

    private func statusText(for isInternal: Bool?) -> String {
        switch isInternal {
        case true:  return "Intern"
        case false: return "Extern"
        case nil:   return "Onbekend"
        }
    }

    // MARK: - Load

    private func loadPeople() {
        isLoading = false
        people = service.directoryPeople()
        loadError = nil
    }
}
