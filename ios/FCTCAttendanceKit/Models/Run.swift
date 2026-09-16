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

    public var hasRecordedAttendance: Bool {
        !attendees.isEmpty || plusOnes > 0
    }

    public var displayLabel: String {
        "\(date) · \(run)"
    }
}

/// Source compatibility for U1 clients. New code should use `ScheduledRun`.
public typealias Run = ScheduledRun
