//
//  SheetAPI.swift
//  FCTCAttendanceKit
//
//  STUB (U1) — the typed client for the Apps Script Web App lands in U3.
//
//  Wire contract (FROZEN — see the plan's API table and packets/_conventions.md):
//    POST <webAppURL>, body { secret, action, ...payload }
//    → { ok: true, ... } | { ok: false, error, message }
//  Actions: getState, submitAttendance, addMember, addRun.
//
//  Only the protocol + the DTOs the contract names are declared here so U4/U6/U7 can
//  compile against a seam (and mock it) before U3 ships the URLSession implementation.
//

import Foundation

// MARK: - Wire DTOs

public struct RosterEntry: Codable, Hashable, Sendable {
    public var name: String
    public var colIndex: Int

    public init(name: String, colIndex: Int) {
        self.name = name
        self.colIndex = colIndex
    }
}

public struct RunRecord: Codable, Hashable, Sendable {
    public var rowIndex: Int
    public var date: String
    public var meet: String
    public var run: String
    public var approxKm: Double?
    public var actualKm: Double?
    public var attendees: [String]
    public var plusOnes: Int

    public init(
        rowIndex: Int,
        date: String,
        meet: String,
        run: String,
        approxKm: Double? = nil,
        actualKm: Double? = nil,
        attendees: [String] = [],
        plusOnes: Int = 0
    ) {
        self.rowIndex = rowIndex
        self.date = date
        self.meet = meet
        self.run = run
        self.approxKm = approxKm
        self.actualKm = actualKm
        self.attendees = attendees
        self.plusOnes = plusOnes
    }
}

/// `getState` response body.
public struct SheetState: Codable, Hashable, Sendable {
    public var roster: [RosterEntry]
    public var runs: [RunRecord]
    public var seasonYear: Int
    /// Stable hash of the header row + run-band cell values.
    public var sheetRevision: String

    public init(
        roster: [RosterEntry] = [],
        runs: [RunRecord] = [],
        seasonYear: Int = 0,
        sheetRevision: String = ""
    ) {
        self.roster = roster
        self.runs = runs
        self.seasonYear = seasonYear
        self.sheetRevision = sheetRevision
    }
}

/// `submitAttendance` request body (minus `secret`/`action`).
///
/// A value type on purpose: `PendingSubmission` is a SwiftData `@Model` (not
/// `Sendable`), so the outbox converts to this before anything crosses an async
/// boundary.
public struct AttendanceSubmission: Codable, Hashable, Sendable {
    public var rowIndex: Int
    public var expectedDate: String
    public var expectedRun: String
    public var attendees: [String]
    public var plusOnes: Int
    public var actualKm: Double?
    public var mode: SubmissionMode
    public var baseRevision: String?

    public init(
        rowIndex: Int,
        expectedDate: String,
        expectedRun: String,
        attendees: [String],
        plusOnes: Int,
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

    /// Snapshot an outbox row for sending. Guest names stay on-device (Q2): only the
    /// count travels.
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
}

/// `submitAttendance` outcome: the server either wrote, or refused with fresh state.
public enum SubmissionOutcome: Hashable, Sendable {
    case written(cells: Int)
    case conflict(reason: String, state: SheetState)
}

public enum SheetAPIError: Error, Sendable, Equatable {
    /// No endpoint URL / secret configured yet (Settings screen, U8).
    case notConfigured
    /// Transport failure — the caller should queue and retry (R9).
    case network(String)
    /// `{ ok: false, error, message }` from the script.
    case server(code: String, message: String)
    /// Response body did not match the contract.
    case decoding(String)
    /// U1 placeholder; removed when U3 lands.
    case notImplemented
}

// MARK: - Client seam

/// Typed client for the four actions. Implemented in U3; mocked everywhere else.
public protocol SheetAPI: Sendable {

    func getState() async throws -> SheetState

    func submitAttendance(
        _ submission: AttendanceSubmission
    ) async throws -> SubmissionOutcome

    func addMember(name: String) async throws -> [RosterEntry]

    func addRun(
        date: String,
        meet: String,
        run: String,
        approxKm: Double?
    ) async throws -> [RunRecord]
}

/// Endpoint + shared secret + device label. Populated from the Settings screen (U8);
/// never compiled in.
public struct SheetAPIConfiguration: Hashable, Sendable {
    public var endpoint: URL?
    public var secret: String
    public var deviceName: String?

    public var isConfigured: Bool { endpoint != nil && !secret.isEmpty }

    public init(endpoint: URL? = nil, secret: String = "", deviceName: String? = nil) {
        self.endpoint = endpoint
        self.secret = secret
        self.deviceName = deviceName
    }
}

/// Placeholder implementation so the app target links before U3. Every call throws
/// `.notImplemented`.
public struct UnimplementedSheetAPI: SheetAPI {

    public init() {}

    public func getState() async throws -> SheetState {
        throw SheetAPIError.notImplemented
    }

    public func submitAttendance(
        _ submission: AttendanceSubmission
    ) async throws -> SubmissionOutcome {
        throw SheetAPIError.notImplemented
    }

    public func addMember(name: String) async throws -> [RosterEntry] {
        throw SheetAPIError.notImplemented
    }

    public func addRun(
        date: String,
        meet: String,
        run: String,
        approxKm: Double?
    ) async throws -> [RunRecord] {
        throw SheetAPIError.notImplemented
    }
}
