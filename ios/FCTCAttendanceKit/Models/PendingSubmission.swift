//
//  PendingSubmission.swift
//  FCTCAttendanceKit
//
//  The outbox row (R9). A confirmed draft becomes one of these; `SyncEngine` drains
//  them with backoff and the Outbox screen shows them.
//
//  `submitAttendance` sends ABSOLUTE cell values (not deltas), so replaying a pending
//  submission is idempotent — that is what makes blind offline retry safe.
//

import Foundation
import SwiftData

/// Merge semantics when the target row already has marks (R8, resolved Q1:
/// overwrite may uncheck previously-recorded attendees — the dialog makes that
/// deliberate).
public enum SubmissionMode: String, Codable, Sendable, CaseIterable {
    case merge
    case overwrite
}

public enum SubmissionStatus: String, Codable, Sendable, CaseIterable {
    /// Waiting for its turn / for the network.
    case queued
    /// In flight right now.
    case sending
    /// Accepted by the sheet.
    case written
    /// Server reported a revision/row-identity conflict; needs the human.
    case conflicted
    /// Repeated failures; needs the human.
    case failed
}

@Model
public final class PendingSubmission {

    @Attribute(.unique) public var id: UUID

    // MARK: Payload (mirrors the frozen `submitAttendance` contract)

    public var rowIndex: Int
    public var expectedDate: String
    public var expectedRun: String
    public var attendees: [String]
    public var actualKm: Double?
    public var baseRevision: String?

    /// Guest NAMES are kept locally (resolved Q2); only `plusOnes` reaches the sheet.
    public var guestNames: [String]

    /// Stored as the raw string so SwiftData never trips over enum evolution.
    public var modeRaw: String
    public var statusRaw: String

    // MARK: Bookkeeping

    public var createdAt: Date
    public var lastAttemptAt: Date?
    public var attemptCount: Int
    public var lastError: String?
    /// Free-text device label carried for the audit trail (no per-user identity).
    public var deviceName: String?

    public init(
        id: UUID = UUID(),
        rowIndex: Int,
        expectedDate: String,
        expectedRun: String,
        attendees: [String],
        guestNames: [String] = [],
        actualKm: Double? = nil,
        mode: SubmissionMode = .merge,
        status: SubmissionStatus = .queued,
        baseRevision: String? = nil,
        createdAt: Date = .now,
        deviceName: String? = nil
    ) {
        self.id = id
        self.rowIndex = rowIndex
        self.expectedDate = expectedDate
        self.expectedRun = expectedRun
        self.attendees = attendees
        self.guestNames = guestNames
        self.actualKm = actualKm
        self.modeRaw = mode.rawValue
        self.statusRaw = status.rawValue
        self.baseRevision = baseRevision
        self.createdAt = createdAt
        self.lastAttemptAt = nil
        self.attemptCount = 0
        self.lastError = nil
        self.deviceName = deviceName
    }
}

extension PendingSubmission {

    public var mode: SubmissionMode {
        get { SubmissionMode(rawValue: modeRaw) ?? .merge }
        set { modeRaw = newValue.rawValue }
    }

    public var status: SubmissionStatus {
        get { SubmissionStatus(rawValue: statusRaw) ?? .queued }
        set { statusRaw = newValue.rawValue }
    }

    /// The count the sheet's `+1's` cell receives.
    public var plusOnes: Int { guestNames.count }

    /// Still owed to the sheet.
    public var isOutstanding: Bool {
        switch status {
        case .queued, .sending, .conflicted, .failed: true
        case .written: false
        }
    }

    /// Build the outbox row for a confirmed draft.
    public static func from(
        draft: AttendanceDraft,
        mode: SubmissionMode = .merge,
        deviceName: String? = nil
    ) -> PendingSubmission {
        PendingSubmission(
            rowIndex: draft.rowIndex,
            expectedDate: draft.expectedDate,
            expectedRun: draft.expectedRun,
            attendees: draft.attendees,
            guestNames: draft.guests.map(\.name),
            actualKm: draft.actualKm,
            mode: mode,
            baseRevision: draft.baseRevision,
            deviceName: deviceName
        )
    }
}
