//
//  WritePathCharacterizationTests.swift
//  FCTCAttendanceKitTests
//
//  U13 characterization of the two write paths `EffectiveRuns` copies: the
//  legacy `SyncEngine.finish()` step, and the shared drain with the Apps Script
//  guest plan. The scenarios here are shared with `EffectiveRunsTests`, which
//  proves the overlay predicts them.
//
//  The shared "server" runs are what the real `guestAttendancePlan_` saved for
//  the same submissions in the fake Apps Script environment
//  (`apps-script/test/support/fakeAppsScript.js`), starting from the same run:
//  Col, one unnamed guest, 7.2 km.
//

import Foundation
import SwiftData
import Testing

@testable import FCTCAttendanceKit

// MARK: - Legacy finish()

@Suite("Effective runs: legacy finish() characterization")
@MainActor
struct LegacyFinishCharacterizationTests {
    @Test("finish() writes each confirmed submission into the cached run", arguments: legacyCases)
    func finish(_ scenario: LegacyCase) async throws {
        let (container, engine, transport) = try await legacyEngine([scenario.start])
        for submission in scenario.submissions {
            _ = try await engine.enqueue(submission)
            await transport.append(.response(writtenResponse))
        }
        await engine.drain()

        let rows = try ModelContext(container).fetch(FetchDescriptor<PendingSubmission>())
        #expect(rows.allSatisfy { $0.status == .done && $0.outcome == .committed })
        #expect(try cachedAttendance(container, row: scenario.start.rowIndex) == scenario.expected)
    }
}

// MARK: - Shared drain and guest plan

@Suite("Effective runs: shared drain characterization")
@MainActor
struct SharedDrainCharacterizationTests {
    @Test("The shared drain sends the guest allocation, then the refresh saves the plan's run",
          arguments: sharedCases)
    func drain(_ scenario: SharedCase) async throws {
        let (container, engine, transport) = try await sharedEngine()
        for step in scenario.steps {
            _ = try await engine.enqueue(draft: step.draft, mode: step.mode, deviceName: nil)
        }
        // Each write is confirmed, then its follow-up refresh returns the saved run.
        for (index, step) in scenario.steps.enumerated() {
            await transport.append(.response(writtenResponse))
            await transport.append(.response(try stateData(sharedState(step.server, revision: "r\(index + 1)"))))
        }
        await engine.drain()

        let writes = try await transport.requests
            .map { try JSONDecoder().decode(GuestJSON.self, from: $0) }
            .filter { $0["action"]?.string == "submitAttendance" }
        // The phone sends the allocation. The server derives the +1s from it.
        #expect(writes.map { $0["namedGuestIds"] }
            == scenario.steps.map { .array($0.draft.namedGuestIds.map(GuestJSON.string)) })
        #expect(writes.map { $0["unnamedGuests"]?.int } == scenario.steps.map(\.draft.unnamedGuests))
        #expect(writes.allSatisfy { $0["plusOnes"] == nil })
        #expect(try cachedAttendance(container, row: 23) == scenario.steps.last?.server)
    }

    @Test("A confirmed shared write leaves the cached run alone until a refresh lands")
    func confirmationWaitsForRefresh() async throws {
        let (container, engine, transport) = try await sharedEngine()
        _ = try await engine.enqueue(draft: namedAndUnnamed.draft, mode: namedAndUnnamed.mode, deviceName: nil)
        // The write is confirmed; its follow-up refresh finds no network.
        await transport.append(.response(writtenResponse))
        await engine.drain()

        let row = try #require(ModelContext(container).fetch(FetchDescriptor<PendingSubmission>()).first)
        #expect(row.status == .done)
        #expect(row.outcome == .committed)
        #expect(try cachedAttendance(container, row: 23) == sharedStart)
    }
}

// MARK: - Scenarios

/// The attendance fields a write changes. Overlay and cache are compared on
/// these alone: the cache also moves its revision, which the overlay cannot know.
struct RunAttendance: Hashable, Sendable, CustomStringConvertible {
    var attendees: [String]
    var plusOnes: Int
    var actualKm: Double?
    var namedGuestIds: [String]
    var unnamedGuests: Int

    /// A legacy run has no named guests; its snapshot counts every +1 as unnamed.
    init(_ attendees: [String], plusOnes: Int, actualKm: Double? = nil,
         named: [String] = [], unnamed: Int? = nil) {
        self.attendees = attendees
        self.plusOnes = plusOnes
        self.actualKm = actualKm
        self.namedGuestIds = named
        self.unnamedGuests = unnamed ?? plusOnes
    }

    init(_ run: RunSnapshot) {
        self.init(run.attendees, plusOnes: run.plusOnes, actualKm: run.actualKm,
                  named: run.namedGuestIds, unnamed: run.unnamedGuests)
    }

    var description: String {
        "\(attendees) +\(plusOnes) (named \(namedGuestIds.count), unnamed \(unnamedGuests)) \(actualKm.map { "\($0) km" } ?? "no km")"
    }
}

/// A cached legacy run, the submissions recorded against it (oldest first),
/// and the run `finish()` leaves in the cache after they sync.
struct LegacyCase: Sendable, CustomTestStringConvertible {
    let name: String
    let start: RunRecord
    let submissions: [AttendanceSubmission]
    let expected: RunAttendance
    var testDescription: String { name }
}

let legacyCases: [LegacyCase] = [
    LegacyCase(
        name: "merge adds to the attendees, keeps the larger +1s, sets the distance",
        start: legacyRun(42, "Fri, 25-Sep", attendees: ["Aaron", "Dan"], plusOnes: 1),
        submissions: [legacySubmission(["Col"], plusOnes: 0, actualKm: 5.5, .merge)],
        expected: RunAttendance(["Aaron", "Col", "Dan"], plusOnes: 1, actualKm: 5.5)
    ),
    LegacyCase(
        name: "overwrite replaces the attendees; nil +1s and distance keep the cache",
        start: legacyRun(42, "Fri, 25-Sep", attendees: ["Aaron", "Dan"], plusOnes: 2, actualKm: 6),
        submissions: [legacySubmission(["Col"], plusOnes: nil, actualKm: nil, .overwrite)],
        expected: RunAttendance(["Col"], plusOnes: 2, actualKm: 6)
    ),
    LegacyCase(
        name: "merge then overwrite on one run: the overwrite wins",
        start: legacyRun(42, "Fri, 25-Sep", attendees: ["Aaron"]),
        submissions: [
            legacySubmission(["Col"], plusOnes: 3, actualKm: nil, .merge),
            legacySubmission(["Dan"], plusOnes: 1, actualKm: nil, .overwrite),
        ],
        expected: RunAttendance(["Dan"], plusOnes: 1)
    ),
    LegacyCase(
        name: "overwrite then merge on one run: the merge adds to it",
        start: legacyRun(42, "Fri, 25-Sep", attendees: ["Aaron"]),
        submissions: [
            legacySubmission(["Dan"], plusOnes: 1, actualKm: nil, .overwrite),
            legacySubmission(["Col"], plusOnes: 3, actualKm: nil, .merge),
        ],
        expected: RunAttendance(["Col", "Dan"], plusOnes: 3)
    ),
]

/// Shared drafts recorded against run 23, each with the run the real guest plan
/// saved after it (oldest first).
struct SharedCase: Sendable, CustomTestStringConvertible {
    struct Step: Sendable {
        let draft: AttendanceDraft
        let mode: SubmissionMode
        let server: RunAttendance
    }

    let name: String
    let steps: [Step]
    var testDescription: String { name }
}

let contractGuestA = "00000001-1111-4111-8111-111111111111"
let contractGuestB = "00000002-1111-4111-8111-111111111111"
let contractRun23 = RunIdentity(spreadsheetId: "illustrative-workbook", seasonSheetId: 26,
                                runId: "00000067-2222-4222-8222-222222222222")

/// Run 23 before any write: the fake environment's first run.
let sharedStart = RunAttendance(["Col"], plusOnes: 1, actualKm: 7.2, unnamed: 1)

/// Merge two named guests and one unnamed: named ids union, unnamed keeps the
/// larger count (1), +1s = 2 named + 1 unnamed = 3. The distance stays.
let namedAndUnnamed = SharedCase.Step(
    draft: sharedDraft(["Col"], guests: [contractGuestA, contractGuestB], unnamed: 1, actualKm: nil),
    mode: .merge,
    server: RunAttendance(["Col"], plusOnes: 3, actualKm: 7.2, named: [contractGuestA, contractGuestB], unnamed: 1)
)

let sharedCases: [SharedCase] = [
    SharedCase(name: "2 named + 1 unnamed guests save 3 +1s", steps: [namedAndUnnamed]),
    SharedCase(name: "an overwrite then a merge on one run apply in order", steps: [
        // Overwrite replaces the attendees, the allocation and the distance.
        .init(draft: sharedDraft(["Toby"], guests: [], unnamed: 2, actualKm: 5), mode: .overwrite,
              server: RunAttendance(["Toby"], plusOnes: 2, actualKm: 5, unnamed: 2)),
        // Merge adds Col and guest A, and keeps the larger unnamed count (2).
        .init(draft: sharedDraft(["Col"], guests: [contractGuestA], unnamed: 0, actualKm: nil), mode: .merge,
              server: RunAttendance(["Col", "Toby"], plusOnes: 3, actualKm: 5, named: [contractGuestA], unnamed: 2)),
    ]),
]

// MARK: - Helpers

func legacyRun(_ row: Int, _ date: String, attendees: [String] = [], plusOnes: Int = 0,
               actualKm: Double? = nil) -> RunRecord {
    RunRecord(rowIndex: row, date: date, meet: "Il Lido", run: "Soft Sand", approxKm: 7,
              actualKm: actualKm, attendees: attendees, plusOnes: plusOnes)
}

func legacySubmission(_ attendees: [String], plusOnes: Int?, actualKm: Double?,
                      _ mode: SubmissionMode, row: Int = 42, date: String = "Fri, 25-Sep") -> AttendanceSubmission {
    AttendanceSubmission(rowIndex: row, expectedDate: date, expectedRun: "Soft Sand", attendees: attendees,
                         plusOnes: plusOnes, actualKm: actualKm, mode: mode, baseRevision: "rev-1")
}

/// A legacy sheet: no shared-guest capability, so runs match by row index.
func legacyState(_ runs: [RunRecord], revision: String = "rev-1") -> SheetState {
    SheetState(roster: [RosterEntry(name: "Aaron", colIndex: 6), RosterEntry(name: "Col", colIndex: 7),
                        RosterEntry(name: "Dan", colIndex: 8)],
               runs: runs, seasonYear: 2026, sheetRevision: revision)
}

func sharedDraft(_ attendees: [String], guests: [String], unnamed: Int, actualKm: Double?) -> AttendanceDraft {
    AttendanceDraft(
        rowIndex: 23, expectedDate: "Fri, 6-Jan", expectedRun: "Soft Sand",
        checks: Dictionary(uniqueKeysWithValues: attendees.map { ($0, CheckProvenance.manual) }),
        guests: guests.map { Guest(id: UUID(uuidString: $0)!, name: "Rene") },
        actualKm: actualKm, baseRevision: "sheet-before", runIdentity: contractRun23,
        endpointIdentity: configuredAPI.endpoint?.absoluteString, unnamedGuests: unnamed
    )
}

/// The contract workbook with run 23 set to `attendance`.
func sharedState(_ attendance: RunAttendance, revision: String) throws -> SheetState {
    var state = try JSONDecoder().decode(SheetState.self, from: guestStateResponse())
    guard let index = state.runs.firstIndex(where: { $0.identity == contractRun23 }) else {
        throw SheetAPIError.badPayload(message: "The contract fixture lost run 23.")
    }
    state.runs[index].attendees = attendance.attendees
    state.runs[index].plusOnes = attendance.plusOnes
    state.runs[index].actualKm = attendance.actualKm
    state.runs[index].namedGuestIds = attendance.namedGuestIds
    state.runs[index].unnamedGuests = attendance.unnamedGuests
    state.sheetRevision = revision
    return state
}

let writtenResponse = json(#"{"ok":true,"written":3,"sheetRevision":"rev-2"}"#)

/// A clock that moves one second on every read, so each engine timestamp
/// (queued, confirmed, refreshed) is strictly later than the one before.
actor TickingClock: SyncClock {
    private var instant = Date(timeIntervalSince1970: 1_790_000_000)

    func now() async -> Date {
        instant.addTimeInterval(1)
        return instant
    }

    func sleep(for seconds: TimeInterval) async throws {
        instant.addTimeInterval(seconds)
    }
}

/// An engine whose cache holds `runs` from a legacy sheet. The transport has
/// no further responses, so the network is off until a test appends one.
func legacyEngine(_ runs: [RunRecord]) async throws -> (ModelContainer, SyncEngine, StubTransport) {
    try await refreshedEngine(state: legacyState(runs))
}

/// An engine whose cache holds the contract workbook with run 23 at `sharedStart`.
func sharedEngine() async throws -> (ModelContainer, SyncEngine, StubTransport) {
    try await refreshedEngine(state: sharedState(sharedStart, revision: "r0"))
}

private func refreshedEngine(state: SheetState) async throws -> (ModelContainer, SyncEngine, StubTransport) {
    let container = try guestContainer()
    let transport = StubTransport([.response(try stateData(state))])
    let engine = SyncEngine(
        modelContainer: container,
        api: SheetAPI(config: configuredAPI, transport: transport),
        clock: TickingClock(),
        automaticallyDrains: false
    )
    _ = try await engine.refreshState()
    return (container, engine, transport)
}

/// The cached run at `row`, with no overlay.
@MainActor
func cachedAttendance(_ container: ModelContainer, row: Int) throws -> RunAttendance? {
    try ModelContext(container).fetch(FetchDescriptor<ScheduledRun>())
        .first { $0.rowIndex == row }
        .map { RunAttendance(RunSnapshot($0)) }
}
