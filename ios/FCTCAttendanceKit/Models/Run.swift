//
//  Run.swift
//  FCTCAttendanceKit
//
//  SwiftData cache of one scheduled run from the canonical sheet.
//


import Foundation
import SwiftData

@Model
public final class ScheduledRun {
    /// A 1-based sheet row coordinate.
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
    public var spreadsheetId: String?
    public var seasonSheetId: Int?
    public var runId: String?
    public var endpointIdentity: String?
    public var namedGuestIds: [String]?
    public var unnamedGuests: Int?
    public var seasonYear: Int?

    public init(
        rowIndex: Int,
        date: String,
        scheduledAt: Date? = nil,
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
}

extension ScheduledRun {
    public var identity: RunIdentity? {
        guard let spreadsheetId, let seasonSheetId, let runId else { return nil }
        return RunIdentity(spreadsheetId: spreadsheetId, seasonSheetId: seasonSheetId, runId: runId)
    }
    public var cacheKey: String { identity?.cacheKey ?? "legacy:\(rowIndex)" }

    public var displayLabel: String {
        "\(date) · \(runName)"
    }
}

/// A sheet row's attendance as every prompt reads it. The cached run, its
/// snapshot and the server's record all share one rule, so Home, catch-up,
/// the run picker and reminders can never disagree about a run.
///
///   attendees  +1s  Run cell                  recorded  cancelled  needs attendance
///   []         0    "River Loop"              no        no         yes
///   []         0    "River Loop (cancelled)"  no        yes        no
///   ["Dan"]    0    "River Loop (cancelled)"  yes       no         no
public protocol RunRowAttendance {
    var run: String { get }
    var attendees: [String] { get }
    var plusOnes: Int { get }
}

extension RunRowAttendance {
    /// A run is a row with at least one attendee or +1 (R2).
    public var hasRecordedAttendance: Bool { !attendees.isEmpty || plusOnes > 0 }

    /// Marked "(cancelled)" with nobody on it. A marked row with a runner is a
    /// normal run, so a marker typed by hand never takes credit away.
    public var isCancelled: Bool { RunLabel.cancellation(run).marked && !hasRecordedAttendance }

    /// Blank and not cancelled: the rows catch-up, reminders and Home ask about.
    public var needsAttendance: Bool { !hasRecordedAttendance && !isCancelled }

    /// The Run cell for display, without a cancelled marker ("River Loop").
    public var runName: String { RunLabel.cancellation(run).label }
}

extension ScheduledRun: RunRowAttendance {}

/// Source compatibility for U1 clients. New code should use `ScheduledRun`.
public typealias Run = ScheduledRun
