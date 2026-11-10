// MigrationTests.swift
// ThoughtVaultTests
// nl.prezent.ThoughtVault
//
// RED until Plan 01 creates PersonProfile + AppMigrationPlan.

import XCTest
import SwiftData
@testable import ThoughtVault

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
    /// A real on-disk store with the V3 shape (PersonProfile without `responsibilities`)
    /// opens through the app's own container path: people intact, no move-aside.
    func testV3StoreWithPeopleOpensUnderV4() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("v3-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Local.store")

        try makeV3Store(at: url)

        let suite = "MigrationTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let container = LocalTranscriptStore.makeContainer(at: url, defaults: defaults)

        XCTAssertEqual(container.configurations.first?.url, url, "must be the on-disk store, not the in-memory fallback")
        let people = try ModelContext(container).fetch(FetchDescriptor<PersonProfile>(sortBy: [SortDescriptor(\.name)]))
        XCTAssertEqual(people.map(\.name), ["Anke Bakker", "Bram Visser"])
        XCTAssertEqual(people.map(\.responsibilities), [[], []])
        XCTAssertEqual(people.first?.emails, ["anke@voorbeeld.nl"])
        XCTAssertEqual(people.map(\.isInternal), [true, nil])
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertFalse(files.contains { $0.contains("incompatible") }, "store was moved aside: \(files)")
        XCTAssertFalse(defaults.bool(forKey: "localStoreOpenInProgress"))
    }

    /// The versioned plan itself also migrates a V3 store (distinct checksums per version).
    func testV3StoreOpensWithMigrationPlan() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("v3-plan-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Local.store")

        try makeV3Store(at: url)

        let container = try ModelContainer(
            for: TranscriptRecord.self, PersonProfile.self,
            migrationPlan: AppMigrationPlan.self,
            configurations: ModelConfiguration(url: url)
        )
        let people = try ModelContext(container).fetch(FetchDescriptor<PersonProfile>(sortBy: [SortDescriptor(\.name)]))
        XCTAssertEqual(people.map(\.name), ["Anke Bakker", "Bram Visser"])
        XCTAssertEqual(people.map(\.responsibilities), [[], []])
    }

    /// Writes two people with the frozen V3 model and releases the container.
    private func makeV3Store(at url: URL) throws {
        let schema = Schema(versionedSchema: AppSchemaV3.self)
        XCTAssertNil(schema.entitiesByName["PersonProfile"]?.attributesByName["responsibilities"], "V3 must be the frozen shape")
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
        let context = ModelContext(container)
        context.insert(AppSchemaV3.PersonProfile(name: "Anke Bakker", role: "Projectleider", emails: ["anke@voorbeeld.nl"], isInternal: true))
        context.insert(AppSchemaV3.PersonProfile(name: "Bram Visser"))
        try context.save()
    }

    /// Opens an on-disk store written by the model before `notuleDraftHtml` and
    /// `notuleReviewReason` existed (Fixtures/PreDraftFields.store), the same way
    /// LocalTranscriptStore opens the real store: implicit lightweight migration.
    func testV3StoreOpensWithDraftFields() throws {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "PreDraftFields", withExtension: "store"))
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "Local.store")
        try FileManager.default.copyItem(at: fixture, to: url)

        let container = try ModelContainer(for: TranscriptRecord.self, PersonProfile.self,
                                           configurations: ModelConfiguration(url: url))
        let record = try XCTUnwrap(try container.mainContext.fetch(FetchDescriptor<TranscriptRecord>()).first)
        XCTAssertEqual(record.id, "fixture-1")
        XCTAssertEqual(record.notuleHtml, "<p>Sam belt vrijdag.</p>")
        XCTAssertNil(record.notuleDraftHtml)
        XCTAssertNil(record.notuleReviewReason)
        XCTAssertNil(record.durationSeconds)

        record.notuleDraftHtml = "<p>Concept</p>"
        try container.mainContext.save()
    }
}
