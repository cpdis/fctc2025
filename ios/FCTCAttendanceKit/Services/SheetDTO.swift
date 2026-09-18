//
//  SheetAPI.swift
//  FCTCAttendanceKit
//
//  Typed client for the frozen Apps Script JSON contract. The transport is a seam,
//  so service and outbox tests never touch the network.
//


import Foundation

// MARK: - Wire DTOs

public struct RosterEntry: Codable, Hashable, Sendable {
    public var name: String
    /// A 1-based sheet column coordinate.
    public var colIndex: Int

    public init(name: String, colIndex: Int) {
        self.name = name
        self.colIndex = colIndex
    }
}

public struct RunRecord: Codable, Hashable, Sendable {
    /// A 1-based sheet row coordinate.
    public var rowIndex: Int
    public var date: String
    public var meet: String
    public var run: String
    public var approxKm: Double?
    public var actualKm: Double?
    public var attendees: [String]
    public var plusOnes: Int
    public var spreadsheetId: String?
    public var seasonSheetId: Int?
    public var runId: String?
    public var namedGuestIds: [String]?
    public var unnamedGuests: Int?
    public var seasonYear: Int?
    public var identity: RunIdentity? {
        guard let spreadsheetId, let seasonSheetId, let runId else { return nil }
        return RunIdentity(spreadsheetId: spreadsheetId, seasonSheetId: seasonSheetId, runId: runId)
    }

    public init(
        rowIndex: Int,
        date: String,
        meet: String,
        run: String,
        approxKm: Double? = nil,
        actualKm: Double? = nil,
        attendees: [String] = [],
        plusOnes: Int = 0,
        identity: RunIdentity? = nil,
        namedGuestIds: [String]? = nil,
        unnamedGuests: Int? = nil,
        seasonYear: Int? = nil
    ) {
        self.rowIndex = rowIndex
        self.date = date
        self.meet = meet
        self.run = run
        self.approxKm = approxKm
        self.actualKm = actualKm
        self.attendees = attendees
        self.plusOnes = plusOnes
        self.spreadsheetId = identity?.spreadsheetId; self.seasonSheetId = identity?.seasonSheetId
        self.runId = identity?.runId; self.namedGuestIds = namedGuestIds
        self.unnamedGuests = unnamedGuests; self.seasonYear = seasonYear
    }
}

/// One member's lifetime run count, summed by the script across every season tab.
public struct MemberTotal: Codable, Hashable, Sendable {
    public var name: String
    public var runs: Int

    public init(name: String, runs: Int) {
        self.name = name
        self.runs = runs
    }
}

/// Explicit sheet identities let recovery select earlier seasons without guessing.
public struct SupportedSeason: Codable, Hashable, Sendable, Identifiable {
    public var seasonSheetId: Int
    public var seasonYear: Int
    public var id: Int { seasonSheetId }
    public init(seasonSheetId: Int, seasonYear: Int) {
        self.seasonSheetId = seasonSheetId; self.seasonYear = seasonYear
    }
}

public struct SheetState: Codable, Hashable, Sendable {
    public var roster: [RosterEntry]
    public var runs: [RunRecord]
    public var seasonYear: Int
    public var sheetRevision: String
    /// Lifetime runs per member. Decodes to empty when the deployed script predates
    /// the field, so a phone on an older build keeps working against a new script
    /// and a new build keeps working against an old one.
    public var lifetimeTotals: [MemberTotal]
    /// Nil means an older server; an empty array explicitly clears saved birthdays.
    public var birthdays: [MemberBirthday]?
    public var apiVersion: Int?
    public var capabilities: GuestCapabilities?
    public var spreadsheetId: String?
    public var seasonSheetId: Int?
    public var guests: [SharedGuest]?
    public var guestRevision: String?
    public var pendingOperationId: String?
    public var supportedSeasons: [SupportedSeason]?
    public var supportsSharedGuests: Bool { capabilities?.canWrite == true }

    public init(
        roster: [RosterEntry] = [],
        runs: [RunRecord] = [],
        seasonYear: Int = 0,
        sheetRevision: String = "",
        lifetimeTotals: [MemberTotal] = [],
        birthdays: [MemberBirthday]? = nil,
        apiVersion: Int? = nil, capabilities: GuestCapabilities? = nil,
        spreadsheetId: String? = nil, seasonSheetId: Int? = nil,
        guests: [SharedGuest]? = nil, guestRevision: String? = nil, pendingOperationId: String? = nil,
        supportedSeasons: [SupportedSeason]? = nil
    ) {
        self.supportedSeasons = supportedSeasons
        self.roster = roster
        self.runs = runs
        self.seasonYear = seasonYear
        self.sheetRevision = sheetRevision
        self.lifetimeTotals = lifetimeTotals
        self.birthdays = birthdays
        self.apiVersion = apiVersion; self.capabilities = capabilities
        self.spreadsheetId = spreadsheetId; self.seasonSheetId = seasonSheetId
        self.guests = guests; self.guestRevision = guestRevision; self.pendingOperationId = pendingOperationId
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        roster = try container.decodeIfPresent([RosterEntry].self, forKey: .roster) ?? []
        runs = try container.decodeIfPresent([RunRecord].self, forKey: .runs) ?? []
        seasonYear = try container.decodeIfPresent(Int.self, forKey: .seasonYear) ?? 0
        sheetRevision = try container.decodeIfPresent(String.self, forKey: .sheetRevision) ?? ""
        lifetimeTotals = try container.decodeIfPresent(
            [MemberTotal].self,
            forKey: .lifetimeTotals
        ) ?? []
        birthdays = try container.decodeIfPresent([MemberBirthday].self, forKey: .birthdays)
        apiVersion = try container.decodeIfPresent(Int.self, forKey: .apiVersion)
        capabilities = try container.decodeIfPresent(GuestCapabilities.self, forKey: .capabilities)
        spreadsheetId = try container.decodeIfPresent(String.self, forKey: .spreadsheetId)
        seasonSheetId = try container.decodeIfPresent(Int.self, forKey: .seasonSheetId)
        guests = try container.decodeIfPresent([SharedGuest].self, forKey: .guests)
        guestRevision = try container.decodeIfPresent(String.self, forKey: .guestRevision)
        pendingOperationId = try container.decodeIfPresent(String.self, forKey: .pendingOperationId)
        supportedSeasons = try container.decodeIfPresent([SupportedSeason].self, forKey: .supportedSeasons)
    }
}

/// The `submitAttendance` payload, without the common `secret` and `action` keys.
/// Nil numeric opinions encode as explicit JSON null values.
public struct AttendanceSubmission: Codable, Hashable, Sendable {
    public var rowIndex: Int
    public var expectedDate: String
    public var expectedRun: String
    public var attendees: [String]
    public var plusOnes: Int?
    public var actualKm: Double?
    public var mode: SubmissionMode
    public var baseRevision: String?

    public init(
        rowIndex: Int,
        expectedDate: String,
        expectedRun: String,
        attendees: [String],
        plusOnes: Int?,
        actualKm: Double? = nil,
        mode: SubmissionMode = .merge,
        baseRevision: String? = nil
    ) {
        self.rowIndex = rowIndex
        self.expectedDate = expectedDate
        self.expectedRun = expectedRun
        self.attendees = attendees
        self.plusOnes = plusOnes
        self.actualKm = actualKm
        self.mode = mode
        self.baseRevision = baseRevision
    }

    /// Snapshot a SwiftData row before it crosses an actor boundary.
    public init(_ pending: PendingSubmission) {
        self.init(
            rowIndex: pending.rowIndex,
            expectedDate: pending.expectedDate,
            expectedRun: pending.expectedRun,
            attendees: pending.attendees,
            plusOnes: pending.plusOnes,
            actualKm: pending.actualKm,
            mode: pending.mode,
            baseRevision: pending.baseRevision
        )
    }

    private enum CodingKeys: String, CodingKey {
        case rowIndex, expectedDate, expectedRun, attendees
        case plusOnes, actualKm, mode, baseRevision
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rowIndex, forKey: .rowIndex)
        try container.encode(expectedDate, forKey: .expectedDate)
        try container.encode(expectedRun, forKey: .expectedRun)
        try container.encode(attendees, forKey: .attendees)
        try container.encode(plusOnes, forKey: .plusOnes)
        try container.encode(actualKm, forKey: .actualKm)
        try container.encode(mode, forKey: .mode)
        try container.encode(baseRevision, forKey: .baseRevision)
    }
}

public struct AddRunRequest: Codable, Hashable, Sendable {
    public var date: String
    public var meet: String
    public var run: String
    public var approxKm: Double?

    public init(date: String, meet: String, run: String, approxKm: Double? = nil) {
        self.date = date
        self.meet = meet
        self.run = run
        self.approxKm = approxKm
    }

    private enum CodingKeys: String, CodingKey { case date, meet, run, approxKm }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(date, forKey: .date)
        try container.encode(meet, forKey: .meet)
        try container.encode(run, forKey: .run)
        try container.encode(approxKm, forKey: .approxKm)
    }
}

public struct AddMemberResult: Codable, Hashable, Sendable {
    public var roster: [RosterEntry]
    public var sheetRevision: String

    public init(roster: [RosterEntry], sheetRevision: String) {
        self.roster = roster
        self.sheetRevision = sheetRevision
    }
}

public struct AddRunResult: Codable, Hashable, Sendable {
    public var runs: [RunRecord]
    public var sheetRevision: String

    public init(runs: [RunRecord], sheetRevision: String) {
        self.runs = runs
        self.sheetRevision = sheetRevision
    }
}

public struct SheetConflict: Codable, Hashable, Sendable {
    public var reason: String
    public var message: String
    public var state: SheetState
}

public enum SubmissionOutcome: Hashable, Sendable {
    case written(cells: Int, sheetRevision: String)
    case conflict(reason: String, message: String, state: SheetState)
}
