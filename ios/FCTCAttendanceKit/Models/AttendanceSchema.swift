//
//  AttendanceSchema.swift
//  FCTCAttendanceKit
//
//  The single list of persistent models, so the app target never has to enumerate
//  them. Everything persisted here is a CACHE + OUTBOX; the Google Sheet remains the
//  canonical record. Queued work and local recovery evidence must never be discarded.
//

import Foundation
import SwiftData

/// The first versioned snapshot of the models (build 10). Earlier builds wrote
/// unversioned stores; SwiftData still upgrades those in place with a lightweight
/// migration, which `GuestMigrationTests` proves against the captured fixtures.
///
/// Before the next schema change: freeze this list (nested copies of the models as
/// they are now), add `AttendanceSchemaV2`, and add a stage to the plan below.
public enum AttendanceSchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(0, 3, 0)

    /// Every `@Model` type in this framework. Add new persistent models here.
    public static let models: [any PersistentModel.Type] = [
        Member.self,
        ScheduledRun.self,
        PendingSubmission.self,
        SharedSheetCache.self, CachedGuest.self, PendingGuestOperation.self,
        ProvisionalGuest.self, GuestRecoveryCandidate.self,
    ]
}

/// One schema and no stages yet. The plan exists so the next version is a new
/// stage, not a first-time retrofit on stores already in people's hands.
public enum AttendanceMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [AttendanceSchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}

public enum AttendanceSchema {

    /// The current models. Always the latest versioned schema.
    public static var models: [any PersistentModel.Type] { AttendanceSchemaV1.models }

    /// Convenience for `ModelContainer(for:)` and test containers.
    public static var schema: Schema {
        Schema(versionedSchema: AttendanceSchemaV1.self)
    }

    /// The app's on-disk store. Both options are explicit so that a later
    /// entitlement cannot change them: an iCloud entitlement under `.automatic`
    /// would turn on sync against the `.unique` attributes, and a second App Group
    /// could move the store. `.automatic` already resolved to this group, so the
    /// store path does not change.
    public static func appStoreConfiguration() -> ModelConfiguration {
        ModelConfiguration(
            "FCTCAttendance",
            schema: schema,
            isStoredInMemoryOnly: false,
            groupContainer: .identifier(AppGroupConstants.identifier),
            cloudKitDatabase: .none
        )
    }

    /// Opens a container through the migration plan. Use this for every store
    /// that holds real data, so new stages always run.
    public static func makeContainer(_ configuration: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(
            for: schema,
            migrationPlan: AttendanceMigrationPlan.self,
            configurations: configuration
        )
    }
}
