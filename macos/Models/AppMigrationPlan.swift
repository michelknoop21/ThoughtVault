// AppMigrationPlan.swift
// TranscriptStudio
// com.buildmind.ThoughtVault
//
// VersionedSchema definitions and lightweight SchemaMigrationPlan for the
// local SwiftData store. V1 → V2 adds PersonProfile as a new @Model.
// V2 → V3 adds emails: [String] (additive) and relaxes isInternal: Bool → Bool?.
//
// Note on fresh installs: A brand-new install skips migration entirely —
// SwiftData creates the store with the current (V3) schema directly.
// The migration plan only fires when an existing V1 or V2 store is detected on disk.

import SwiftData

// MARK: - AppSchemaV1

/// Schema version 1: only TranscriptRecord.
enum AppSchemaV1: VersionedSchema {
    nonisolated(unsafe) static var versionIdentifier = Schema.Version(1, 0, 0)
    nonisolated(unsafe) static var models: [any PersistentModel.Type] = [TranscriptRecord.self]
}

// MARK: - AppSchemaV2

/// Schema version 2: TranscriptRecord + PersonProfile (additive, lightweight-safe).
/// Both model types must be listed here — omitting either causes schema conflicts.
enum AppSchemaV2: VersionedSchema {
    nonisolated(unsafe) static var versionIdentifier = Schema.Version(2, 0, 0)
    nonisolated(unsafe) static var models: [any PersistentModel.Type] = [TranscriptRecord.self, PersonProfile.self]
}

// MARK: - AppSchemaV3

/// Schema version 3: adds emails: [String] to PersonProfile (additive, D-02)
/// and relaxes isInternal: Bool → Bool? (relaxing change, D-01).
/// Both changes are lightweight-migration eligible — no custom stage needed.
enum AppSchemaV3: VersionedSchema {
    nonisolated(unsafe) static var versionIdentifier = Schema.Version(3, 0, 0)
    nonisolated(unsafe) static var models: [any PersistentModel.Type] = [TranscriptRecord.self, PersonProfile.self]
}

// MARK: - AppMigrationPlan

/// Lightweight migrations: V1 → V2 → V3.
/// - V1→V2: adds PersonProfile as a new @Model (no existing TranscriptRecord changes).
/// - V2→V3: adds emails: [String] (materializes as [] for existing rows) + Bool → Bool?
///   relaxation (existing isInternal value preserved as non-nil).
/// No custom stages — both transitions are lightweight-eligible.
enum AppMigrationPlan: SchemaMigrationPlan {
    nonisolated(unsafe) static var schemas: [any VersionedSchema.Type] = [AppSchemaV1.self, AppSchemaV2.self, AppSchemaV3.self]
    nonisolated(unsafe) static var stages: [MigrationStage] = [v1ToV2, v2ToV3]

    static let v1ToV2 = MigrationStage.lightweight(
        fromVersion: AppSchemaV1.self,
        toVersion: AppSchemaV2.self
    )

    static let v2ToV3 = MigrationStage.lightweight(
        fromVersion: AppSchemaV2.self,
        toVersion: AppSchemaV3.self
    )
}
