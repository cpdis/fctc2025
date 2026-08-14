//
//  AttendanceSchema.swift
//  FCTCAttendanceKit
//
//  The single list of persistent models, so the app target never has to enumerate
//  them. Everything persisted here is a CACHE + OUTBOX; the Google Sheet remains the
//  canonical record (plan R1), and the whole store is reconstructible from `getState`.
//

import Foundation
import SwiftData

public enum AttendanceSchema {

    /// Every `@Model` type in this framework. Add new persistent models here.
    public static let models: [any PersistentModel.Type] = [
        Member.self,
        Run.self,
        PendingSubmission.self,
    ]

    /// Convenience for `ModelContainer(for:)`.
    public static var schema: Schema {
        Schema(models)
    }

    /// Bumped whenever a stored property changes shape. U3 owns any real migration
    /// plan; until then the cache is disposable and can simply be rebuilt.
    public static let version = "0.1.0"
}
