// MigrationTests.swift
// TranscriptStudioTests
// nl.prezent.TranscriptStudio
//
// RED until Plan 01 creates PersonProfile + AppMigrationPlan.

import XCTest
import SwiftData
@testable import TranscriptStudio

@MainActor
final class MigrationTests: XCTestCase {

    /// Verifies that an existing TranscriptRecord survives the V1→V2 schema migration
    /// (adding PersonProfile as a new @Model). The in-memory container uses the real
    /// AppMigrationPlan so this test will fail to compile until Plan 01 ships those types.
    func testTranscriptRecordSurvivesV1ToV2Migration() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: TranscriptRecord.self, PersonProfile.self,
            migrationPlan: AppMigrationPlan.self,
            configurations: config
        )
        let context = container.mainContext

        // Seed one TranscriptRecord
        let seededId = UUID().uuidString
        let record = TranscriptRecord(
            id: seededId,
            taskId: seededId,
            title: "Migratie-test vergadering",
            tags: ["test"],
            createdAt: Date()
        )
        context.insert(record)
        try context.save()

        // Fetch back and assert survival
        let descriptor = FetchDescriptor<TranscriptRecord>()
        let fetched = try context.fetch(descriptor)

        XCTAssertEqual(fetched.count, 1, "Expected exactly one TranscriptRecord after migration")
        XCTAssertEqual(fetched.first?.id, seededId, "TranscriptRecord id must survive V1→V2 migration")
    }

    /// Verifies that an existing PersonProfile + TranscriptRecord both survive the V2→V3
    /// schema migration (isInternal: Bool → Bool?, emails: [String] added).
    ///
    /// RED until Plan 02-02 adds `emails: [String]` and changes `isInternal` to `Bool?` on
    /// PersonProfile and appends SchemaV3 + v2ToV3 to AppMigrationPlan.
    /// The `.emails` reference below will fail to compile against the current model —
    /// that compile failure IS the intended RED state proving the migration is unproven.
    func testPersonProfileSurvivesV2ToV3Migration() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: TranscriptRecord.self, PersonProfile.self,
            migrationPlan: AppMigrationPlan.self,
            configurations: config
        )
        let context = container.mainContext

        // Seed one PersonProfile (V2-style: isSelf + isInternal set)
        let person = PersonProfile(
            name: "Jan de Vries",
            role: "Projectmanager",
            organization: "Prezent BV",
            isSelf: true,
            isInternal: true
        )
        context.insert(person)

        // Seed one TranscriptRecord alongside
        let recordId = UUID().uuidString
        let record = TranscriptRecord(
            id: recordId,
            taskId: recordId,
            title: "Migratie V2→V3 vergadering",
            tags: ["migratie"],
            createdAt: Date()
        )
        context.insert(record)
        try context.save()

        // Fetch back through the same container (exercises the migration plan)
        let personDescriptor = FetchDescriptor<PersonProfile>(
            predicate: #Predicate { $0.isSelf == true }
        )
        let fetchedPeople = try context.fetch(personDescriptor)
        XCTAssertEqual(fetchedPeople.count, 1, "PersonProfile must survive V2→V3 migration")

        let fetchedPerson = try XCTUnwrap(fetchedPeople.first)

        // (a) PersonProfile still has isSelf == true
        XCTAssertTrue(fetchedPerson.isSelf, "isSelf must be preserved after V2→V3 migration")

        // (b) TranscriptRecord still exists
        let recordDescriptor = FetchDescriptor<TranscriptRecord>()
        let fetchedRecords = try context.fetch(recordDescriptor)
        XCTAssertEqual(fetchedRecords.count, 1, "TranscriptRecord must survive V2→V3 migration")

        // (c) The new emails collection materializes as empty for the pre-existing row (D-02).
        //     This line will not compile until Plan 02-02 adds `emails: [String]` — that is RED.
        XCTAssertEqual(fetchedPerson.emails, [], "emails must materialize as empty [] for a pre-existing row")

        // (d) isInternal preserves the stored Bool value as non-nil after Bool → Bool? relaxation (D-01).
        //     After 02-02 changes isInternal to Bool?, this assertion still passes (value = .some(true)).
        XCTAssertEqual(fetchedPerson.isInternal, true, "isInternal must be preserved as true after Bool→Bool? relaxation")
    }
}
