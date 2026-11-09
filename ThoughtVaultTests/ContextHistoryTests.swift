// ContextHistoryTests.swift
// ThoughtVaultTests
//
// Version history for directory people and glossary entries.

import XCTest
import SwiftData
@testable import ThoughtVault

@MainActor
final class ContextHistoryTests: XCTestCase {
    private var dir: URL!
    private var savedURL: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("history-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        savedURL = ContextHistory.url
        ContextHistory.url = dir.appendingPathComponent("context-history.json")
    }

    override func tearDownWithError() throws {
        ContextHistory.url = savedURL
        try? FileManager.default.removeItem(at: dir)
    }

    func testRecordKeepsAtMost50PerItem() throws {
        try ContextHistory.record(kind: .term, itemId: "b", source: "handmatig", snapshot: ["ander"])
        for i in 0..<55 {
            try ContextHistory.record(kind: .person, itemId: "a", source: "handmatig", snapshot: [i])
        }
        let versions = ContextHistory.versions(kind: .person, itemId: "a")
        XCTAssertEqual(versions.count, ContextHistory.maxPerItem)
        XCTAssertEqual(versions.first?.snapshotJSON, "[54]", "newest first")
        XCTAssertEqual(versions.last?.snapshotJSON, "[5]", "the five oldest are dropped")
        XCTAssertEqual(ContextHistory.versions(kind: .term, itemId: "b").map(\.snapshotJSON), [#"["ander"]"#])
        XCTAssertTrue(ContextHistory.versions(kind: .term, itemId: "a").isEmpty, "kind is part of the key")
    }

    /// Runs through PersonDirectoryService with an injected in-memory container.
    func testRestoreCreatesNewVersionAndKeepsNewer() throws {
        let container = try ModelContainer(
            for: TranscriptRecord.self, PersonProfile.self,
            migrationPlan: AppMigrationPlan.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let service = PersonDirectoryService(container: container)
        let person = PersonProfile(name: "Anke Bakker", role: "v0")
        try service.add(person)
        for role in ["v1", "v2", "v3"] {
            try service.update(person, source: "handmatig") { $0.role = role; $0.responsibilities = [role] }
        }
        var versions = ContextHistory.versions(kind: .person, itemId: person.id)
        XCTAssertEqual(versions.count, 3)

        try service.restore(try XCTUnwrap(versions.last), to: person)

        XCTAssertEqual(person.role, "v0")
        XCTAssertEqual(person.responsibilities, [])
        versions = ContextHistory.versions(kind: .person, itemId: person.id)
        XCTAssertEqual(versions.count, 4)
        XCTAssertEqual(versions.first?.source, "herstel")
        XCTAssertEqual(versions.dropFirst().map(\.source), ["handmatig", "handmatig", "handmatig"])
        let kept = try JSONDecoder().decode(PersonSnapshot.self, from: Data(try XCTUnwrap(versions.first).snapshotJSON.utf8))
        XCTAssertEqual(kept.role, "v3", "the state from before the restore stays available")
        XCTAssertEqual(kept.responsibilities, ["v3"])
    }

    func testSaveRecordingTwiceKeepsFirstStateAndRestores() throws {
        let path = dir.appendingPathComponent("personal-corrections.json")
        var entry = PersonalCorrection(canonical: "Yinga", variants: ["Jengo"])
        try PersonalCorrections.saveRecording(entry, source: "handmatig", to: path)
        XCTAssertTrue(ContextHistory.versions(kind: .term, itemId: entry.id).isEmpty, "a new entry has no earlier version")

        entry.variants = ["Jengo", "Django"]
        try PersonalCorrections.saveRecording(entry, source: "handmatig", to: path)

        var versions = ContextHistory.versions(kind: .term, itemId: entry.id)
        XCTAssertEqual(versions.count, 1)
        let first = try JSONDecoder().decode(PersonalCorrection.self, from: Data(versions[0].snapshotJSON.utf8))
        XCTAssertEqual(first.variants, ["Jengo"])
        XCTAssertEqual(try PersonalCorrections.load(from: path).map(\.variants), [["Jengo", "Django"]])

        try PersonalCorrections.restore(versions[0], to: path)

        XCTAssertEqual(try PersonalCorrections.load(from: path).map(\.variants), [["Jengo"]])
        versions = ContextHistory.versions(kind: .term, itemId: entry.id)
        XCTAssertEqual(versions.map(\.source), ["herstel", "handmatig"])
    }

    func testDeletedTermCanBeRestored() throws {
        let path = dir.appendingPathComponent("personal-corrections.json")
        let keep = PersonalCorrection(canonical: "Prezent", variants: [])
        let entry = PersonalCorrection(canonical: "Yinga", variants: ["Jengo"], note: "Merknaam")
        try PersonalCorrections.saveRecording(keep, source: "handmatig", to: path)
        try PersonalCorrections.saveRecording(entry, source: "handmatig", to: path)

        try PersonalCorrections.delete(id: entry.id, source: "handmatig", to: path)

        XCTAssertEqual(try PersonalCorrections.load(from: path), [keep])
        let versions = ContextHistory.versions(kind: .term, itemId: entry.id)
        XCTAssertEqual(versions.count, 1)
        try PersonalCorrections.restore(versions[0], to: path)
        XCTAssertEqual(try PersonalCorrections.load(from: path), [keep, entry])
    }

    /// upsert merges a new entry into an existing one with the same term: the saved
    /// entry keeps the existing id, and its earlier state is recorded under that id.
    func testSaveRecordingMergeRecordsExistingEntry() throws {
        let path = dir.appendingPathComponent("personal-corrections.json")
        let first = PersonalCorrection(canonical: "Yinga", variants: ["Jengo"])
        let other = PersonalCorrection(canonical: "Prezent", variants: [])
        try PersonalCorrections.saveRecording(first, source: "handmatig", to: path)
        try PersonalCorrections.saveRecording(other, source: "handmatig", to: path)

        let saved = try PersonalCorrections.saveRecording(PersonalCorrection(canonical: "yinga", variants: ["Django"]), source: "gesprek:t1", to: path)

        XCTAssertEqual(saved.map(\.canonical), ["Prezent", "yinga"])
        XCTAssertEqual(saved.last?.id, first.id)
        XCTAssertEqual(saved.last?.variants, ["Jengo", "Django"])
        let versions = ContextHistory.versions(kind: .term, itemId: first.id)
        XCTAssertEqual(versions.map(\.source), ["gesprek:t1"])
        XCTAssertEqual(try JSONDecoder().decode(PersonalCorrection.self, from: Data(versions[0].snapshotJSON.utf8)), first)
        XCTAssertTrue(ContextHistory.versions(kind: .term, itemId: other.id).isEmpty)
    }

    func testPersonSnapshotRoundTrip() throws {
        let person = PersonProfile(name: "Bram", role: "PM", emails: ["b@x.nl"], isInternal: false)
        person.responsibilities = ["Planning"]
        let snapshot = PersonSnapshot(person)
        let other = PersonProfile()
        try JSONDecoder().decode(PersonSnapshot.self, from: JSONEncoder().encode(snapshot)).apply(to: other)
        XCTAssertEqual(PersonSnapshot(other), snapshot)
    }
}
