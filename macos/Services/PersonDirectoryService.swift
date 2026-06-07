// PersonDirectoryService.swift
// TranscriptStudio
// nl.prezent.TranscriptStudio
//
// On-device directory CRUD + seed dedup (D-11). Person data stays local; no network calls.
// Network IO lives in MicrosoftGraphService; this service only touches the ModelContainer.

import Foundation
import SwiftData

// MARK: - PersonDirectoryService

/// @MainActor service providing CRUD over the on-device people directory.
/// Directory entries are PersonProfiles with isSelf == false.
/// Contains no network calls (D-11, success criterion 4, grep-gated).
@MainActor
final class PersonDirectoryService {

    // MARK: - Shared instance

    /// Shared singleton backed by LocalTranscriptStore's ModelContainer.
    /// Views should use this instead of constructing new instances (WR-01).
    static let shared = PersonDirectoryService()

    // MARK: - Container

    private let _container: ModelContainer

    /// Production init: uses the shared LocalTranscriptStore container.
    init() {
        self._container = LocalTranscriptStore.shared.container
    }

    /// Test init: accepts an injected container so tests can use in-memory stores.
    init(container: ModelContainer) {
        self._container = container
    }

    private var context: ModelContext { _container.mainContext }

    // MARK: - Directory Fetch

    /// Returns all directory entries (isSelf == false), sorted by name.
    /// The self-profile (isSelf == true) is never included (Pitfall 5 / D-05).
    func directoryPeople() -> [PersonProfile] {
        let descriptor = FetchDescriptor<PersonProfile>(
            predicate: #Predicate { $0.isSelf == false },
            sortBy: [SortDescriptor(\.name)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Add

    /// Inserts a new directory person and persists immediately.
    func add(_ person: PersonProfile) throws {
        context.insert(person)
        try context.save()
    }

    // MARK: - Update

    /// Updates a directory person by ID. Bumps updatedAt.
    func update(_ person: PersonProfile) throws {
        person.updatedAt = Date()
        try context.save()
    }

    /// Convenience: update only the name field by ID.
    func updatePerson(id: String, name: String) throws {
        let descriptor = FetchDescriptor<PersonProfile>(
            predicate: #Predicate { $0.id == id }
        )
        guard let person = try context.fetch(descriptor).first else { return }
        person.name = name
        person.updatedAt = Date()
        try context.save()
    }

    // MARK: - Delete

    /// Deletes a directory person from the store.
    func delete(_ person: PersonProfile) {
        context.delete(person)
        try? context.save()
    }

    /// Deletes a directory person by ID.
    func deletePerson(id: String) throws {
        let descriptor = FetchDescriptor<PersonProfile>(
            predicate: #Predicate { $0.id == id }
        )
        guard let person = try context.fetch(descriptor).first else { return }
        context.delete(person)
        try context.save()
    }

    // MARK: - Seed Factory

    /// Builds a seed PersonProfile candidate. Does NOT auto-persist — the review
    /// sheet (plan 02-04) decides what to commit (D-07).
    func seedPerson(name: String, email: String?) -> PersonProfile {
        PersonProfile(
            name: name,
            emails: [email].compactMap { $0 },
            isSelf: false,
            isInternal: nil  // D-09: seeded entries are onbekend (nil)
        )
    }

    // MARK: - Dedup (D-10)

    /// Returns the subset of attendeeEmails that are genuinely new:
    /// not already in the directory (email match, case-insensitive),
    /// not in the self-profile emails,
    /// not equal to selfEmail.
    ///
    /// Caller resolves selfEmail from:
    ///   MicrosoftGraphService.shared.accountEmail ∪ CalendarService.microsoftAccountEmail ∪ self-profile emails
    /// (Open Item 3 resolved in plan 02-04).
    func newSeedCandidates(from attendeeEmails: [String], selfEmail: String?) -> [String] {
        // Build the known-email set from the directory
        let directoryEmails = Set(
            directoryPeople().flatMap { $0.emails }.map { $0.lowercased() }
        )

        // Add self-profile emails (the user's own email(s))
        let selfProfileEmails = Set(
            (LocalTranscriptStore.shared.fetchSelfProfile()?.emails ?? []).map { $0.lowercased() }
        )

        let knownEmails = directoryEmails.union(selfProfileEmails)

        // Self email from the caller (Graph account email / microsoftAccountEmail)
        let selfSet: Set<String> = selfEmail.map { [($0).lowercased()] }.map(Set.init) ?? []

        return attendeeEmails
            .map { $0.lowercased() }
            .filter { !knownEmails.contains($0) && !selfSet.contains($0) }
    }
}
