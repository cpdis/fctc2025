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
}
