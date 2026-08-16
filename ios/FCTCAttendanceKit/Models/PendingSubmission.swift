//
//  PendingSubmission.swift
//  FCTCAttendanceKit
//
//  Persistent outbox snapshot. Replays are safe because every sheet value is
//  absolute, not a delta.
//


import Foundation
import SwiftData

public enum SubmissionMode: String, Codable, Sendable, CaseIterable {
    case merge
    case overwrite
}

public enum SubmissionStatus: String, Codable, Sendable, CaseIterable {
    case queued
    case inFlight
    case conflict
    case done

    /// Compatibility spellings from the U1 placeholder.
    public static var sending: Self { .inFlight }
    public static var written: Self { .done }
    public static var conflicted: Self { .conflict }
}

@Model
public final class PendingSubmission {
    @Attribute(.unique) public var id: UUID

    // MARK: Frozen payload

    /// A 1-based sheet row coordinate.
    public var rowIndex: Int
    public var expectedDate: String
    public var expectedRun: String
    public var attendees: [String]
    public var actualKm: Double?
    public var baseRevision: String?
    public var guestNames: [String]
    public var plusOnesValue: Int?
    public var modeRaw: String

    // MARK: Outbox state

    public var stateRaw: String
    public var createdAt: Date
    public var lastAttemptAt: Date?
    public var attemptCount: Int
    public var lastError: String?
    public var deviceName: String?

    // A Codable DTO is stored as data because SwiftData cannot persist it directly.
    public var conflictReason: String?
    public var conflictMessage: String?
    public var conflictStateData: Data?

    public init(
        id: UUID = UUID(),
        rowIndex: Int,
        expectedDate: String,
        expectedRun: String,
        attendees: [String],
        guestNames: [String] = [],
        plusOnes: Int? = nil,
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
        self.plusOnesValue = plusOnes ?? guestNames.count
        self.actualKm = actualKm
        self.modeRaw = mode.rawValue
        self.stateRaw = status.rawValue
        self.baseRevision = baseRevision
        self.createdAt = createdAt
        self.lastAttemptAt = nil
        self.attemptCount = 0
        self.lastError = nil
        self.deviceName = deviceName
        self.conflictReason = nil
        self.conflictMessage = nil
        self.conflictStateData = nil
    }
}

extension PendingSubmission {
    public var mode: SubmissionMode {
        get { SubmissionMode(rawValue: modeRaw) ?? .merge }
        set { modeRaw = newValue.rawValue }
    }

    public var state: SubmissionStatus {
        get { SubmissionStatus(rawValue: stateRaw) ?? .queued }
        set { stateRaw = newValue.rawValue }
    }

    /// Compatibility spelling from the U1 model.
    public var status: SubmissionStatus {
        get { state }
        set { state = newValue }
    }

    public var plusOnes: Int? { plusOnesValue }

    public var isOutstanding: Bool { state != .done }

    public var conflictState: SheetState? {
        guard let conflictStateData else { return nil }
        return try? JSONDecoder().decode(SheetState.self, from: conflictStateData)
    }

    public func attachConflict(reason: String, message: String, state: SheetState) {
        conflictReason = reason
        conflictMessage = message
        conflictStateData = try? JSONEncoder().encode(state)
    }

    public func clearConflict() {
        conflictReason = nil
        conflictMessage = nil
        conflictStateData = nil
    }

    public static func from(
        draft: AttendanceDraft,
        mode: SubmissionMode = .merge,
        deviceName: String? = nil,
        createdAt: Date = .now
    ) -> PendingSubmission {
        PendingSubmission(
            rowIndex: draft.rowIndex,
            expectedDate: draft.expectedDate,
            expectedRun: draft.expectedRun,
            attendees: draft.attendees,
            guestNames: draft.guestNames,
            plusOnes: draft.plusOnes,
            actualKm: draft.actualKm,
            mode: mode,
            baseRevision: draft.baseRevision,
            createdAt: createdAt,
            deviceName: deviceName
        )
    }
}
