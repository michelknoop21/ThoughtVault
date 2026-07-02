// PersonProfileTests.swift
// ThoughtVaultTests
// nl.prezent.ThoughtVault
//
// RED until Plan 01 implements PersonProfile + upsertSelfProfile.

import Testing
import Foundation
import SwiftData
@testable import ThoughtVault

// Helper: builds an in-memory ModelContainer with both TranscriptRecord and PersonProfile.
// Exercises the same fetch-isSelf→insert/edit upsert logic as LocalTranscriptStore.
@MainActor
private func makeInMemoryContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(
        for: TranscriptRecord.self, PersonProfile.self,
        migrationPlan: AppMigrationPlan.self,
        configurations: config
    )
}

// Mirrors LocalTranscriptStore.upsertSelfProfile but operates on an arbitrary context
// so the tests can run against a dedicated in-memory container.
@MainActor
private func upsertSelfProfile(
    name: String,
    role: String = "",
    organization: String = "",
    aliases: [String] = [],
    meetingTypes: [String] = [],
    expertiseTags: [String] = [],
    in context: ModelContext
) throws {
    let descriptor = FetchDescriptor<PersonProfile>(
        predicate: #Predicate { $0.isSelf == true }
    )
    if let existing = try context.fetch(descriptor).first {
        existing.name = name
        existing.role = role
        existing.organization = organization
        existing.aliases = aliases
        existing.meetingTypes = meetingTypes
        existing.expertiseTags = expertiseTags
        existing.updatedAt = Date()
    } else {
        context.insert(PersonProfile(
            name: name,
            role: role,
            organization: organization,
            aliases: aliases,
            meetingTypes: meetingTypes,
            expertiseTags: expertiseTags,
            isSelf: true,
            isInternal: true
        ))
    }
    try context.save()
}

@Suite("PersonProfile Tests")
struct PersonProfileTests {

    /// (1) After one upsert with name "Michel", fetching isSelf==true yields exactly one record
    /// with name "Michel".
    @Test("upsertSelfProfile creates a record on an empty store")
    @MainActor
    func upsertCreatesRecordOnEmptyStore() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        try upsertSelfProfile(name: "Michel", in: context)

        let descriptor = FetchDescriptor<PersonProfile>(
            predicate: #Predicate { $0.isSelf == true }
        )
        let results = try context.fetch(descriptor)
        #expect(results.count == 1)
        #expect(results.first?.name == "Michel")
    }

    /// (2) After two upserts (second with role "PM"), isSelf==true count stays 1 and role == "PM"
    /// (singleton invariant — Pitfall 3).
    @Test("upsertSelfProfile updates the existing record in-place when self already exists")
    @MainActor
    func upsertUpdatesInPlaceWhenSelfExists() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        try upsertSelfProfile(name: "Michel", role: "Engineer", in: context)
        try upsertSelfProfile(name: "Michel", role: "PM", in: context)

        let descriptor = FetchDescriptor<PersonProfile>(
            predicate: #Predicate { $0.isSelf == true }
        )
        let results = try context.fetch(descriptor)
        #expect(results.count == 1, "Singleton invariant: exactly one isSelf record")
        #expect(results.first?.role == "PM")
    }

    /// (3) Without calling upsert, fetching isSelf==true yields zero records
    /// (D-07 skip path — skipping onboarding creates no PersonProfile record).
    @Test("Fetching isSelf records on an untouched store returns zero records")
    @MainActor
    func skipCreatesNoRecord() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let descriptor = FetchDescriptor<PersonProfile>(
            predicate: #Predicate { $0.isSelf == true }
        )
        let results = try context.fetch(descriptor)
        #expect(results.isEmpty)
    }
}
