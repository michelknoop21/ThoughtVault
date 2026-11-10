// AppMigrationPlan.swift
// ThoughtVault
// com.buildmind.ThoughtVault
//
// VersionedSchema definitions and lightweight SchemaMigrationPlan for the
// local SwiftData store. V1 → V2 adds PersonProfile as a new @Model.
// V2 → V3 adds emails: [String] (additive) and relaxes isInternal: Bool → Bool?.
// V3 → V4 adds responsibilities: [String] (additive).
//
// The app opens its store WITHOUT this plan (see LocalTranscriptStore.makeContainer):
// SwiftData's inferred lightweight migration covers every step above. The plan is
// used by tests and documents the schema history.
//
// Each version must have a distinct checksum, so V2 and V3 list frozen copies of
// PersonProfile as it was then; V4 lists the live types. Listing the live types in
// more than one version gives "Duplicate version checksums detected", an
// uncatchable CoreData exception during migration. When PersonProfile changes,
// freeze the current shape into the latest version and add a new one.
// TranscriptRecord is not frozen: every version here lists the live type.

import Foundation
import SwiftData

// MARK: - AppSchemaV1

/// Schema version 1: only TranscriptRecord.
enum AppSchemaV1: VersionedSchema {
    nonisolated(unsafe) static var versionIdentifier = Schema.Version(1, 0, 0)
    nonisolated(unsafe) static var models: [any PersistentModel.Type] = [TranscriptRecord.self]
}

// MARK: - AppSchemaV2

/// Schema version 2: TranscriptRecord + PersonProfile (additive, lightweight-safe).
enum AppSchemaV2: VersionedSchema {
    nonisolated(unsafe) static var versionIdentifier = Schema.Version(2, 0, 0)
    nonisolated(unsafe) static var models: [any PersistentModel.Type] = [TranscriptRecord.self, AppSchemaV2.PersonProfile.self]

    /// PersonProfile as shipped in V2 (frozen).
    @Model
    final class PersonProfile {
        @Attribute(.unique) var id: String
        var name: String
        var role: String
        var organization: String
        var aliases: [String]
        var meetingTypes: [String]
        var expertiseTags: [String]
        var isSelf: Bool
        var isInternal: Bool
        var createdAt: Date
        var updatedAt: Date

        init(id: String = UUID().uuidString, name: String = "", isSelf: Bool = false, isInternal: Bool = true) {
            self.id = id
            self.name = name
            self.role = ""
            self.organization = ""
            self.aliases = []
            self.meetingTypes = []
            self.expertiseTags = []
            self.isSelf = isSelf
            self.isInternal = isInternal
            self.createdAt = Date()
            self.updatedAt = Date()
        }
    }
}

// MARK: - AppSchemaV3

/// Schema version 3: adds emails: [String] to PersonProfile (additive, D-02)
/// and relaxes isInternal: Bool → Bool? (relaxing change, D-01).
enum AppSchemaV3: VersionedSchema {
    nonisolated(unsafe) static var versionIdentifier = Schema.Version(3, 0, 0)
    nonisolated(unsafe) static var models: [any PersistentModel.Type] = [TranscriptRecord.self, AppSchemaV3.PersonProfile.self]

    /// PersonProfile as shipped in V3 (frozen): no responsibilities yet.
    @Model
    final class PersonProfile {
        @Attribute(.unique) var id: String
        var name: String
        var role: String
        var organization: String
        var aliases: [String]
        var meetingTypes: [String]
        var expertiseTags: [String]
        var emails: [String]
        var isSelf: Bool
        var isInternal: Bool?
        var createdAt: Date
        var updatedAt: Date

        init(id: String = UUID().uuidString, name: String = "", role: String = "", emails: [String] = [], isSelf: Bool = false, isInternal: Bool? = nil) {
            self.id = id
            self.name = name
            self.role = role
            self.organization = ""
            self.aliases = []
            self.meetingTypes = []
            self.expertiseTags = []
            self.emails = emails
            self.isSelf = isSelf
            self.isInternal = isInternal
            self.createdAt = Date()
            self.updatedAt = Date()
        }
    }
}

// MARK: - AppSchemaV4

/// Schema version 4: adds responsibilities: [String] to PersonProfile (additive).
/// Lists the live model types.
enum AppSchemaV4: VersionedSchema {
    nonisolated(unsafe) static var versionIdentifier = Schema.Version(4, 0, 0)
    nonisolated(unsafe) static var models: [any PersistentModel.Type] = [TranscriptRecord.self, PersonProfile.self]
}

// MARK: - AppMigrationPlan

/// Lightweight migrations: V1 → V2 → V3 → V4.
/// - V1→V2: adds PersonProfile as a new @Model (no existing TranscriptRecord changes).
/// - V2→V3: adds emails: [String] (materializes as [] for existing rows) + Bool → Bool?
///   relaxation (existing isInternal value preserved as non-nil).
/// - V3→V4: adds responsibilities: [String] (materializes as [] for existing rows).
/// No custom stages: every transition is lightweight-eligible.
enum AppMigrationPlan: SchemaMigrationPlan {
    nonisolated(unsafe) static var schemas: [any VersionedSchema.Type] = [AppSchemaV1.self, AppSchemaV2.self, AppSchemaV3.self, AppSchemaV4.self]
    nonisolated(unsafe) static var stages: [MigrationStage] = [v1ToV2, v2ToV3, v3ToV4]

    static let v1ToV2 = MigrationStage.lightweight(
        fromVersion: AppSchemaV1.self,
        toVersion: AppSchemaV2.self
    )

    static let v2ToV3 = MigrationStage.lightweight(
        fromVersion: AppSchemaV2.self,
        toVersion: AppSchemaV3.self
    )

    static let v3ToV4 = MigrationStage.lightweight(
        fromVersion: AppSchemaV3.self,
        toVersion: AppSchemaV4.self
    )
}
