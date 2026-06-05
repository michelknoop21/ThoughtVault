// AppMigrationPlan.swift
// TranscriptStudio
// nl.prezent.TranscriptStudio
//
// VersionedSchema definitions and lightweight SchemaMigrationPlan for the
// local SwiftData store. V1 → V2 adds PersonProfile as a new @Model.
//
// Note on fresh installs: A brand-new install skips migration entirely —
// SwiftData creates the store with the current (V2) schema directly.
// The migration plan only fires when an existing V1 store is detected on disk.

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

// MARK: - AppMigrationPlan

/// Lightweight migration from V1 to V2.
/// Adding a new @Model type (PersonProfile) with no changes to the existing
/// TranscriptRecord schema qualifies for a lightweight (non-custom) stage.
enum AppMigrationPlan: SchemaMigrationPlan {
    nonisolated(unsafe) static var schemas: [any VersionedSchema.Type] = [AppSchemaV1.self, AppSchemaV2.self]
    nonisolated(unsafe) static var stages: [MigrationStage] = [v1ToV2]

    static let v1ToV2 = MigrationStage.lightweight(
        fromVersion: AppSchemaV1.self,
        toVersion: AppSchemaV2.self
    )
}
