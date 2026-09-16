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

public enum AttendanceSchema {

    /// Every `@Model` type in this framework. Add new persistent models here.
    public static let models: [any PersistentModel.Type] = [
        Member.self,
        ScheduledRun.self,
        PendingSubmission.self,
        SharedSheetCache.self, CachedGuest.self, PendingGuestOperation.self,
        ProvisionalGuest.self, GuestRecoveryCandidate.self,
    ]

    /// Convenience for `ModelContainer(for:)`.
    public static var schema: Schema {
        Schema(models)
    }

    /// Optional additive fields permit lightweight migration from installed stores.
    /// The on-disk upgrade test verifies old submissions and names survive.
    public static let version = "0.3.0"
}
