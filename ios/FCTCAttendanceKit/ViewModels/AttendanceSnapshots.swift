//
//  AttendanceSnapshots.swift
//  FCTCAttendanceKit
//
//  Sendable values that let MainActor view models consume SwiftData state without
//  sending live model objects across the SyncEngine actor boundary.
//

import Foundation

public struct RunSnapshot: Hashable, Sendable, Identifiable {
    public var id: Int { rowIndex }
    public var rowIndex: Int
    public var date: String
    public var scheduledAt: Date?
    public var meet: String
    public var run: String
    public var approxKm: Double?
    public var actualKm: Double?
    public var attendees: [String]
    public var plusOnes: Int
    public var cachedRevision: String?

    public init(
        rowIndex: Int,
        date: String,
        scheduledAt: Date?,
        meet: String,
        run: String,
        approxKm: Double? = nil,
        actualKm: Double? = nil,
        attendees: [String] = [],
        plusOnes: Int = 0,
        cachedRevision: String? = nil
    ) {
        self.rowIndex = rowIndex
        self.date = date
        self.scheduledAt = scheduledAt
        self.meet = meet
        self.run = run
        self.approxKm = approxKm
        self.actualKm = actualKm
        self.attendees = attendees
        self.plusOnes = plusOnes
        self.cachedRevision = cachedRevision
    }

    @MainActor
    public init(_ run: ScheduledRun) {
        self.init(
            rowIndex: run.rowIndex,
            date: run.date,
            scheduledAt: run.scheduledAt,
            meet: run.meet,
            run: run.run,
            approxKm: run.approxKm,
            actualKm: run.actualKm,
            attendees: run.attendees,
            plusOnes: run.plusOnes,
            cachedRevision: run.cachedRevision
        )
    }

    public var hasRecordedAttendance: Bool {
        !attendees.isEmpty || plusOnes > 0
    }

    public var detailLabel: String {
        let distance = approxKm.map {
            $0.formatted(.number.precision(.fractionLength(0...2)))
        }
        return [meet, run, distance.map { "\($0) km" }]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

}

public struct PendingSubmissionSnapshot: Hashable, Sendable, Identifiable {
    public var id: UUID
    public var rowIndex: Int
    public var expectedDate: String
    public var expectedRun: String
    public var attendees: [String]
    public var guestNames: [String]
    public var plusOnes: Int?
    public var actualKm: Double?
    public var mode: SubmissionMode
    public var status: SubmissionStatus
    public var createdAt: Date
    public var lastError: String?
    public var conflictReason: String?
    public var conflictMessage: String?
    public var conflictState: SheetState?

    public init(
        id: UUID,
        rowIndex: Int,
        expectedDate: String,
        expectedRun: String,
        attendees: [String],
        guestNames: [String] = [],
        plusOnes: Int?,
        actualKm: Double?,
        mode: SubmissionMode,
        status: SubmissionStatus,
        createdAt: Date,
        lastError: String? = nil,
        conflictReason: String? = nil,
        conflictMessage: String? = nil,
        conflictState: SheetState? = nil
    ) {
        self.id = id
        self.rowIndex = rowIndex
        self.expectedDate = expectedDate
        self.expectedRun = expectedRun
        self.attendees = attendees
        self.guestNames = guestNames
        self.plusOnes = plusOnes
        self.actualKm = actualKm
        self.mode = mode
        self.status = status
        self.createdAt = createdAt
        self.lastError = lastError
        self.conflictReason = conflictReason
        self.conflictMessage = conflictMessage
        self.conflictState = conflictState
    }

    @MainActor
    public init(_ pending: PendingSubmission) {
        self.init(
            id: pending.id,
            rowIndex: pending.rowIndex,
            expectedDate: pending.expectedDate,
            expectedRun: pending.expectedRun,
            attendees: pending.attendees,
            guestNames: pending.guestNames,
            plusOnes: pending.plusOnes,
            actualKm: pending.actualKm,
            mode: pending.mode,
            status: pending.status,
            createdAt: pending.createdAt,
            lastError: pending.lastError,
            conflictReason: pending.conflictReason,
            conflictMessage: pending.conflictMessage,
            conflictState: pending.conflictState
        )
    }

    public var isOutstanding: Bool { status != .done }
}

public struct AttendanceDiff: Hashable, Sendable {
    public var added: Int
    public var removed: Int

    public init(added: Int, removed: Int) {
        self.added = added
        self.removed = removed
    }

    public var summary: String {
        "Will add \(added), remove \(removed)"
    }
}

/// The complete writable-field comparison shown before resolving a conflict.
public struct ConflictDiff: Hashable, Sendable {
    public var attendance: AttendanceDiff
    public var localPlusOnes: Int?
    public var serverPlusOnes: Int
    public var localActualKm: Double?
    public var serverActualKm: Double?

    public init(
        attendance: AttendanceDiff,
        localPlusOnes: Int?,
        serverPlusOnes: Int,
        localActualKm: Double?,
        serverActualKm: Double?
    ) {
        self.attendance = attendance
        self.localPlusOnes = localPlusOnes
        self.serverPlusOnes = serverPlusOnes
        self.localActualKm = localActualKm
        self.serverActualKm = serverActualKm
    }

    /// Nil payload values mean "leave the sheet value unchanged".
    public var plusOnesChanged: Bool {
        localPlusOnes.map { $0 != serverPlusOnes } ?? false
    }

    public var actualKmChanged: Bool {
        localActualKm.map { $0 != serverActualKm } ?? false
    }
}
