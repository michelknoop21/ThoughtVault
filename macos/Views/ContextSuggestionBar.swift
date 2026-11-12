// ContextSuggestionBar.swift
// ThoughtVault
//
// Compact bar above the notule with the term and people suggestions from the
// context step. Each suggestion is accepted, applied or ignored here; handled
// suggestions disappear and the bar hides when none are left.

import SwiftUI

/// Pure text and merge rules of the suggestion bar (unit tested).
enum ContextSuggestionBarLogic {
    /// "2 termen, 1 persoon"; zero counts are left out.
    static func counter(terms: Int, people: Int) -> String {
        var parts: [String] = []
        if terms > 0 { parts.append(terms == 1 ? "1 term" : "\(terms) termen") }
        if people > 0 { parts.append(people == 1 ? "1 persoon" : "\(people) personen") }
        return parts.joined(separator: ", ")
    }

    /// "Is dit Jan de Vries of Jan Smit?"
    static func ambiguousQuestion(_ names: [String]) -> String {
        guard let last = names.last else { return "" }
        let head = names.dropLast()
        return "Is dit " + (head.isEmpty ? last : head.joined(separator: ", ") + " of " + last) + "?"
    }

    /// Role and organization only when the proposal has one; aliases appended
    /// case-insensitively, skipping the name and spellings already known.
    static func applyRemainder(_ s: PersonSuggestion, to snapshot: PersonSnapshot) -> PersonSnapshot {
        var result = snapshot
        let role = trim(s.role), organization = trim(s.organization)
        if !role.isEmpty { result.role = role }
        if !organization.isEmpty { result.organization = organization }
        var seen = Set(([snapshot.name] + snapshot.aliases).map { trim($0).lowercased() })
        result.aliases += s.heardAs.map(trim).filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
        return result
    }

    /// One line per change that applying the remainder would make.
    static func changeSummary(_ s: PersonSuggestion, current: PersonSnapshot) -> [String] {
        let next = applyRemainder(s, to: current)
        var lines: [String] = []
        if next.role != current.role { lines.append(change("Rol", current.role, next.role)) }
        if next.organization != current.organization { lines.append(change("Organisatie", current.organization, next.organization)) }
        let added = next.aliases.dropFirst(current.aliases.count)
        if !added.isEmpty { lines.append("Ook bekend als: " + added.joined(separator: ", ")) }
        return lines
    }

    private static func change(_ label: String, _ old: String, _ new: String) -> String {
        old.isEmpty ? "\(label): \(new)" : "\(label): \(old) → \(new)"
    }
    private static func trim(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
}

struct ContextSuggestionBar: View {
    let taskId: String
    /// Meeting type added to a person chosen from an ambiguous suggestion.
    let profileName: String
    /// Profile scope for a new glossary term (same default as "Woord corrigeren").
    let scope: String?
    let profiles: [Profile]
    /// Corrects this notule and, with remember, saves the term (TranscriptDetailView.applyWordCorrection).
    let applyCorrection: (PersonalCorrection, Bool) async throws -> Void

    @State private var set = ContextSuggestionSet()
    @State private var directory: [String: PersonProfile] = [:]
    @State private var expanded = false
    @State private var error = ""
    @State private var pendingTerm: TermSuggestion?
    @State private var addingPerson: PersonSuggestion?
    /// The DEBUG screenshot sample is shown read-only.
    @State private var isSample = false

    var body: some View {
        panel
            .task(id: taskId) { error = ""; reload() }
            .onReceive(NotificationCenter.default.publisher(for: .contextSuggestionsUpdated)) { note in
                if note.userInfo?["taskId"] as? String == taskId { reload() }
            }
            .sheet(item: $pendingTerm) { term in
                let entry = PersonalCorrection(canonical: term.canonical, variants: [term.heard], scope: scope,
                                               note: term.note.isEmpty ? nil : term.note)
                WordCorrectionSheet(entry: entry, profiles: profiles) { draft, remember in
                    try await applyCorrection(draft, remember)
                    finish(.term(term))
                }
            }
            .sheet(item: $addingPerson) { suggestion in
                // Removed as soon as the person exists, so closing the sheet early cannot leave it to be added twice.
                PersonEditView(person: nil, prefill: suggestion, prefillMeetingType: profileName, onAdded: { _ in finish(.person(suggestion)) }) { _ in
                    addingPerson = nil
                }
            }
    }

    @ViewBuilder private var panel: some View {
        if set.isEmpty && error.isEmpty {
            Color.clear.frame(height: 0)
        } else {
            VStack(alignment: .leading, spacing: TS.Spacing.sm) {
                if set.hasSuggestions { header }
                if expanded {
                    ForEach(set.terms, id: \.self) { term in Divider(); termRow(term) }
                    ForEach(set.people) { person in Divider(); personRow(person) }
                }
                if let skipped = set.skipped {
                    Text(skipped.notice).font(TS.Font.caption).foregroundStyle(Color.labelSecondary)
                }
                if !error.isEmpty {
                    Text(error).font(TS.Font.caption).foregroundStyle(Color.statusErrorText)
                }
            }
            .padding(.horizontal, TS.Spacing.md)
            .padding(.vertical, TS.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surfaceSecondary)
            .overlay(alignment: .bottom) { Divider() }
        }
    }

    private var header: some View {
        let counter = ContextSuggestionBarLogic.counter(terms: set.terms.count, people: set.people.count)
        return Button { withAnimation(TS.Animation.smooth) { expanded.toggle() } } label: {
            HStack(spacing: TS.Spacing.sm) {
                Image(systemName: "lightbulb").foregroundStyle(Color.brandPrimary)
                Text("Voorstellen").font(TS.Font.footnoteSemibold).foregroundStyle(Color.labelPrimary)
                Text(counter)
                    .font(TS.Font.footnote).foregroundStyle(Color.labelSecondary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(TS.Font.caption).foregroundStyle(Color.labelSecondary)
                    .rotationEffect(.degrees(expanded ? 180 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Voorstellen, " + counter)
        .accessibilityHint(expanded ? "Inklappen" : "Uitklappen")
    }

    // MARK: - Rows

    private func termRow(_ term: TermSuggestion) -> some View {
        row(title: "\(term.heard) → \(term.canonical)", detail: [term.note]) {
            Button("Toevoegen") { pendingTerm = term }.buttonStyle(.borderedProminent)
            ignoreButton(.term(term))
        }
    }

    /// Fewer than two candidates left in the directory: offered as a new person.
    @ViewBuilder private func personRow(_ s: PersonSuggestion) -> some View {
        let candidates = s.candidateIds.compactMap { directory[$0] }
        if let id = s.matchedPersonId {
            let current = directory[id]
            let summary = current.map { ContextSuggestionBarLogic.changeSummary(s, current: PersonSnapshot($0)) } ?? []
            row(title: current?.name ?? s.name, detail: summary) {
                Button("Bijwerken") { update(s) }.buttonStyle(.borderedProminent)
                ignoreButton(.person(s))
            }
        } else if candidates.count > 1 {
            row(title: ContextSuggestionBarLogic.ambiguousQuestion(candidates.map(\.name)), detail: [s.name]) {
                ForEach(candidates, id: \.id) { person in
                    Button(person.name) { choose(person.id, for: s) }.buttonStyle(.bordered)
                }
                Button(candidates.count > 2 ? "Geen van deze" : "Geen van beiden") { var new = s; new.candidateIds = []; replace(s, with: new) }
                    .buttonStyle(.bordered)
                ignoreButton(.person(s))
            }
        } else {
            let detail = [[s.role, s.organization].filter { !$0.isEmpty }.joined(separator: ", "),
                          s.responsibilities.isEmpty ? "" : "Taken: " + s.responsibilities.joined(separator: ", ")]
            row(title: s.name, detail: detail) {
                Button("Toevoegen") { addingPerson = s }.buttonStyle(.borderedProminent)
                ignoreButton(.person(s))
            }
        }
    }

    /// Title, secondary lines and buttons that stack when the row is too narrow.
    private func row<Buttons: View>(title: String, detail: [String], @ViewBuilder buttons: () -> Buttons) -> some View {
        let buttons = buttons()
        return VStack(alignment: .leading, spacing: TS.Spacing.xs) {
            Text(title).font(TS.Font.footnoteSemibold).foregroundStyle(Color.labelPrimary)
            ForEach(detail.filter { !$0.isEmpty }, id: \.self) { line in
                Text(line).font(TS.Font.caption).foregroundStyle(Color.labelSecondary)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: TS.Spacing.sm) { buttons }
                VStack(alignment: .leading, spacing: TS.Spacing.xs) { buttons }
            }
            #if os(iOS)
            .controlSize(.regular)
            #else
            .controlSize(.small)
            #endif
            .tint(Color.brandPrimary)
            .disabled(isSample)
            .padding(.top, TS.Spacing.xs)
        }
    }

    private func ignoreButton(_ item: ContextSuggestionItem) -> some View {
        Button("Negeren") { finish(item, dismiss: true) }.buttonStyle(.bordered)
    }

    // MARK: - Actions

    private func reload() {
        set = ContextSuggestions.load(taskId: taskId) ?? ContextSuggestionSet()
        isSample = false
        #if DEBUG
        if set.isEmpty, let sample = debugSample() { set = sample; isSample = true }
        #endif
        directory = set.people.isEmpty ? [:] : Dictionary(PersonDirectoryService.shared.directoryPeople().map { ($0.id, $0) },
                                                         uniquingKeysWith: { first, _ in first })
    }

    /// Removes a handled suggestion; `dismiss` also keeps it from being offered again.
    private func finish(_ item: ContextSuggestionItem, dismiss: Bool = false) {
        do {
            if dismiss { try ContextSuggestions.dismiss(key: ContextSuggestions.dismissKey(for: item)) }
            try ContextSuggestions.remove(taskId: taskId, item: item)
            error = ""
        } catch {
            self.error = "Voorstel verwerken mislukt: \(error.localizedDescription)"
        }
        reload()
    }

    private func replace(_ old: PersonSuggestion, with new: PersonSuggestion) {
        var next = set
        if let index = next.people.firstIndex(of: old) { next.people[index] = new }
        do { try ContextSuggestions.save(next, taskId: taskId); error = "" }
        catch { self.error = "Voorstel verwerken mislukt: \(error.localizedDescription)" }
        reload()
    }

    /// Applies a remainder to the matched person in place; the row showed the changes beforehand.
    private func update(_ s: PersonSuggestion) {
        guard let id = s.matchedPersonId, let person = directory[id] else {
            error = "Deze persoon staat niet meer in de personenlijst."
            return
        }
        do {
            try PersonDirectoryService.shared.update(person, source: "voorstel:\(taskId)") { p in
                ContextSuggestionBarLogic.applyRemainder(s, to: PersonSnapshot(p)).apply(to: p)
            }
            finish(.person(s))
        } catch {
            self.error = "Bijwerken mislukt: \(error.localizedDescription)"
        }
    }

    /// Fills in the chosen person; what still needs the user stays as a remainder row.
    private func choose(_ id: String, for s: PersonSuggestion) {
        do {
            if let rest = try PersonMatcher.autoApply(s, to: id, profileName: profileName, taskId: taskId) {
                replace(s, with: rest)
            } else {
                finish(.person(s))
            }
        } catch {
            self.error = "Koppelen mislukt: \(error.localizedDescription)"
        }
    }

    // MARK: - Screenshot hook

    #if DEBUG
    @MainActor private static var debugTaskId: String?

    /// `-TVDebugSuggestions YES` (or `expanded`) shows sample suggestions on the first notule
    /// opened, in memory only and read-only (buttons disabled). Debug builds only, never under tests. The remainder and
    /// ambiguous samples use the first two directory people when they exist.
    private func debugSample() -> ContextSuggestionSet? {
        let flag = UserDefaults.standard.string(forKey: "TVDebugSuggestions")
        guard !AppEnvironment.isRunningTests, flag == "YES" || flag == "expanded" else { return nil }
        if Self.debugTaskId == nil { Self.debugTaskId = taskId; expanded = flag == "expanded" }
        guard Self.debugTaskId == taskId else { return nil }
        let people = PersonDirectoryService.shared.directoryPeople()
        var sample = ContextSuggestionSet(
            terms: [TermSuggestion(heard: "Kuber netes", canonical: "Kubernetes", note: "Platform voor containerbeheer"),
                    TermSuggestion(heard: "Thought fold", canonical: "ThoughtVault", note: "")],
            people: [PersonSuggestion(name: "Sanne Bakker", role: "Projectleider", organization: "Gemeente Utrecht",
                                      responsibilities: ["Planning", "Subsidieaanvraag"], topics: ["Subsidie"],
                                      heardAs: ["Sanne Backer"], matchedPersonId: nil)])
        if let first = people.first {
            sample.people.append(PersonSuggestion(name: first.name, role: "Teamleider", organization: "", responsibilities: [],
                                                  topics: [], heardAs: ["\(first.name.split(separator: " ").first ?? "") V."], matchedPersonId: first.id))
        }
        if people.count > 1 {
            sample.people.append(PersonSuggestion(name: "Jan", role: "", organization: "", responsibilities: [], topics: [],
                                                  heardAs: [], matchedPersonId: nil, candidateIds: [people[0].id, people[1].id]))
        }
        return sample
    }
    #endif
}
