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
}
