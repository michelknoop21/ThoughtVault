// PersonDirectoryServiceTests.swift
// ThoughtVaultTests
// nl.prezent.ThoughtVault
//
// RED until Plan 02-02 ships PersonDirectoryService + PersonProfile.emails.
// PersonDirectoryService does not exist yet → compile failure is the intended
// RED state that proves directory CRUD + dedup behavior is unimplemented.

import XCTest
import SwiftData
@testable import ThoughtVault

/// Helper: builds an in-memory ModelContainer for directory tests.
/// Mirrors makeInMemoryContainer() from PersonProfileTests.swift.
@MainActor
private func makeDirectoryContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(
        for: TranscriptRecord.self, PersonProfile.self,
        migrationPlan: AppMigrationPlan.self,
        configurations: config
    )
}

@MainActor
final class PersonDirectoryServiceTests: XCTestCase {

    // MARK: - Test 1: CRUD round-trip, isSelf entries never appear

    /// Insert one isSelf:false directory person + one isSelf:true self-profile,
    /// then assert directoryPeople() returns ONLY the non-self entry.
    /// Update name, assert persistence. Delete, assert empty.
    ///
    /// RED: PersonDirectoryService does not exist yet (Plan 02-02).
    func testDirectoryCrudRoundTripReturnsOnlyNonSelf() throws {
        let container = try makeDirectoryContainer()
        let context = container.mainContext

        // Seed self-profile (must never appear in directory)
        let selfProfile = PersonProfile(
            name: "Michel Knoop",
            role: "Product Owner",
            organization: "Prezent BV",
            isSelf: true,
            isInternal: true
        )
        context.insert(selfProfile)

        // Seed one directory person (isSelf: false)
        let dirPerson = PersonProfile(
            name: "Anke Bakker",
            role: "Designer",
            organization: "Prezent BV",
            isSelf: false,
            isInternal: true
        )
        context.insert(dirPerson)
        try context.save()

        // PersonDirectoryService does not exist yet — RED compile failure below
        let service = PersonDirectoryService(container: container)

        // (1) directoryPeople() returns only the non-self entry
        let people = service.directoryPeople()
        XCTAssertEqual(people.count, 1, "directory must not expose the self-profile")
        XCTAssertEqual(people.first?.name, "Anke Bakker")
        XCTAssertFalse(people.first?.isSelf ?? true, "directory entries must have isSelf == false")

        // (2) update name and assert persistence
        try service.updatePerson(id: dirPerson.id, name: "Anke B. Bakker")
        let afterUpdate = service.directoryPeople()
        XCTAssertEqual(afterUpdate.first?.name, "Anke B. Bakker")

        // (3) delete and assert empty
        try service.deletePerson(id: dirPerson.id)
        let afterDelete = service.directoryPeople()
        XCTAssertTrue(afterDelete.isEmpty, "directory must be empty after deleting the only entry")
    }

    // MARK: - Test 2: Dedup filters known and self emails (case-insensitive)

    /// Seed directory with a known person holding email "a@x.nl".
    /// Call newSeedCandidates(from:selfEmail:) with candidates ["A@X.NL", "new@x.nl", "self@x.nl"]
    /// and selfEmail "self@x.nl".
    /// Assert only "new@x.nl" survives (known email filtered case-insensitively, self filtered out).
    ///
    /// RED: PersonDirectoryService (and PersonProfile.emails) do not exist yet (Plan 02-02).
    func testDedupFiltersKnownAndSelfEmails() throws {
        let container = try makeDirectoryContainer()
        let context = container.mainContext

        // Seed a directory person with a known email
        // PersonProfile.emails does not exist yet → compile failure on this line (RED)
        let knownPerson = PersonProfile(
            name: "Anke Bakker",
            role: "Designer",
            organization: "Prezent BV",
            emails: ["a@x.nl"],
            isSelf: false,
            isInternal: true
        )
        context.insert(knownPerson)
        try context.save()

        let service = PersonDirectoryService(container: container)

        // Candidates: known email (uppercased), new email, self email
        let candidates = ["A@X.NL", "new@x.nl", "self@x.nl"]
        let result = service.newSeedCandidates(from: candidates, selfEmail: "self@x.nl")

        // Only the genuinely new address survives
        XCTAssertEqual(result, ["new@x.nl"], "only truly new, non-self email addresses must survive dedup")
    }
}
