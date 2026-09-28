//
//  EffectiveRunsTests.swift
//  FCTCAttendanceKitTests
//
//  U13: effective runs = the cached season plus the outbox (KTD11, R26, AE8).
//  The overlay must equal the cache after the same submissions sync, on both
//  write paths (`WritePathCharacterizationTests` pins those paths), and the
//  streaks and totals must include it offline.
//

import Foundation
import SwiftData
import Testing

@testable import FCTCAttendanceKit

// MARK: - Overlay against the write paths

@Suite("Effective runs: overlay")
@MainActor
struct EffectiveRunsOverlayTests {
    @Test("The overlay shows what finish() will write, before any sync", arguments: legacyCases)
    func legacyOverlay(_ scenario: LegacyCase) async throws {
        let (container, engine, transport) = try await legacyEngine([scenario.start])
        for submission in scenario.submissions { _ = try await engine.enqueue(submission) }

        let offline = try effectiveRuns(container)
        #expect(offline.runs.map(RunAttendance.init) == [scenario.expected])
        #expect(offline.unsyncedCount == scenario.submissions.count)

        // After sync the cache alone shows the same run.
        for _ in scenario.submissions { await transport.append(.response(writtenResponse)) }
        await engine.drain()
        let synced = try effectiveRuns(container)
        #expect(synced.runs.map(RunAttendance.init) == offline.runs.map(RunAttendance.init))
        #expect(synced.unsyncedCount == 0)
    }

    @Test("The overlay shows what the guest plan will save, before any sync", arguments: sharedCases)
    func sharedOverlay(_ scenario: SharedCase) async throws {
        let (container, engine, transport) = try await sharedEngine()
        for step in scenario.steps {
            _ = try await engine.enqueue(draft: step.draft, mode: step.mode, deviceName: nil)
        }

        let offline = try effectiveRuns(container)
        #expect(attendance(of: contractRun23, in: offline) == scenario.steps.last?.server)
        #expect(offline.unsyncedCount == scenario.steps.count)

        for (index, step) in scenario.steps.enumerated() {
            await transport.append(.response(writtenResponse))
            await transport.append(.response(try stateData(sharedState(step.server, revision: "r\(index + 1)"))))
        }
        await engine.drain()
        let synced = try effectiveRuns(container)
        #expect(synced.runs.map(RunAttendance.init) == offline.runs.map(RunAttendance.init))
        #expect(synced.unsyncedCount == 0)
    }

    @Test("AE8: a pending overwrite for today adds Aaron; his streak and totals include it offline")
    func ae8() async throws {
        // Two weeks of club days Aaron and Dan made, Dan's Saturday Pub Run
        // (a special), and today's Monday run, still blank in the cache.
        let clubDays = ["Mon, 14-Sep", "Wed, 16-Sep", "Fri, 18-Sep", "Mon, 21-Sep", "Wed, 23-Sep", "Fri, 25-Sep"]
        let runs = clubDays.enumerated().map { legacyRun(10 + $0, $1, attendees: ["Aaron", "Dan"]) }
            + [legacyRun(16, "Sat, 26-Sep", attendees: ["Dan"]), legacyRun(17, "Mon, 28-Sep")]
        let (container, engine, _) = try await legacyEngine(runs)
        _ = try await engine.enqueue(legacySubmission(["Aaron", "Col"], plusOnes: 1, actualKm: 6, .overwrite,
                                                      row: 17, date: "Mon, 28-Sep"))
        // The network is off: the drain parks the row.
        await engine.drain()
        #expect(try ModelContext(container).fetch(FetchDescriptor<PendingSubmission>()).first?.status == .queued)

        let evening = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 19)))
        let members = ["Aaron", "Col", "Dan"]
        let cached = MemberStats.calculateAll(members: members, runs: try storeInputs(container).cached, now: evening)
        #expect(cached["Aaron"]?.attendanceCount == 6)
        #expect(cached["Aaron"]?.currentStreak == 6)

        let effective = try effectiveRuns(container)
        #expect(effective.unsyncedCount == 1)
        let stats = MemberStats.calculateAll(members: members, runs: effective.runs, now: evening)
        #expect(stats["Aaron"]?.attendanceCount == 7)
        #expect(stats["Aaron"]?.streakLabel == "7 club days in a row")
        #expect(stats["Col"]?.currentStreak == 1)
        // Today is a club day now, and Dan missed it.
        #expect(stats["Dan"]?.currentStreak == 0)

        let dashboard = DashboardModel(season: 2026, runs: effective.clubRuns)
        #expect(dashboard.headline.runs == 8)
        #expect(dashboard.leaderboard.byRuns.first { $0.name == "Aaron" }?.runs == 7)
    }

    @Test("A conflicted submission is ignored; the confirmed server state replaces the overlay once")
    func conflict() async throws {
        let (container, engine, transport) = try await legacyEngine([legacyRun(42, "Fri, 25-Sep", attendees: ["Aaron"])])
        let id = try await engine.enqueue(legacySubmission(["Aaron", "Col"], plusOnes: nil, actualKm: nil, .overwrite))
        #expect(try effectiveRuns(container).runs.map(\.attendees) == [["Aaron", "Col"]])

        // Another phone added Dan first, so the overwrite conflicts and waits.
        let moved = legacyState([legacyRun(42, "Fri, 25-Sep", attendees: ["Aaron", "Dan"])], revision: "rev-2")
        await transport.append(.response(try staleRevision(moved)))
        await engine.drain()
        var effective = try effectiveRuns(container)
        #expect(effective.runs.map(\.attendees) == [["Aaron", "Dan"]])
        #expect(effective.unsyncedCount == 0)

        // The organiser merges instead. The replacement shows at once...
        _ = try await engine.resolveConflict(id: id, action: .merge)
        effective = try effectiveRuns(container)
        #expect(effective.runs.map(\.attendees) == [["Aaron", "Col", "Dan"]])
        #expect(effective.unsyncedCount == 1)

        // ...and once confirmed, the cache shows it exactly once.
        await transport.append(.response(writtenResponse))
        await engine.drain()
        effective = try effectiveRuns(container)
        #expect(effective.runs.map(\.attendees) == [["Aaron", "Col", "Dan"]])
        #expect(effective.unsyncedCount == 0)
        let stats = MemberStats.calculateAll(members: ["Aaron", "Col", "Dan"], runs: effective.runs, now: .distantFuture)
        #expect(stats.mapValues(\.attendanceCount) == ["Aaron": 1, "Col": 1, "Dan": 1])
    }

    @Test("A confirmed shared write whose refresh fails still counts until a later refresh succeeds")
    func sharedRefreshFailure() async throws {
        let (container, engine, transport) = try await sharedEngine()
        _ = try await engine.enqueue(draft: namedAndUnnamed.draft, mode: namedAndUnnamed.mode, deviceName: nil)
        // Confirmed; the follow-up refresh finds no network.
        await transport.append(.response(writtenResponse))
        await engine.drain()
        let row = try #require(ModelContext(container).fetch(FetchDescriptor<PendingSubmission>()).first)
        let cache = try #require(ModelContext(container).fetch(FetchDescriptor<SharedSheetCache>()).first)
        #expect(row.outcome == .committed)
        #expect(try #require(row.lastAttemptAt) > cache.refreshedAt)

        // 2 named + 1 unnamed guests: 3 +1s. Synced, so not unsynced.
        var effective = try effectiveRuns(container)
        #expect(attendance(of: contractRun23, in: effective)?.plusOnes == 3)
        #expect(attendance(of: contractRun23, in: effective) == namedAndUnnamed.server)
        #expect(effective.unsyncedCount == 0)

        await #expect(throws: (any Error).self) { try await engine.refreshState() }
        effective = try effectiveRuns(container)
        #expect(attendance(of: contractRun23, in: effective) == namedAndUnnamed.server)

        // A later refresh lands and the sheet wins, though another phone has
        // since removed guest B.
        let later = RunAttendance(["Col"], plusOnes: 2, actualKm: 7.2, named: [contractGuestA], unnamed: 1)
        await transport.append(.response(try stateData(sharedState(later, revision: "r2"))))
        _ = try await engine.refreshState()
        effective = try effectiveRuns(container)
        #expect(attendance(of: contractRun23, in: effective) == later)
    }

    /// The overlay keys on the confirmation, not the send: a refresh between
    /// the two may predate the server's write.
    @Test("A write its receipt confirms after a refresh still counts until a refresh lands after it")
    func receiptAfterRefresh() async throws {
        let (container, engine, transport) = try await sharedEngine()
        let id = try await engine.enqueue(draft: namedAndUnnamed.draft, mode: namedAndUnnamed.mode, deviceName: nil)
        // The response is lost, and a refresh lands before the write shows.
        await transport.append(.failure(.ambiguousTimeout))
        await engine.drain()
        await transport.append(.response(try stateData(sharedState(sharedStart, revision: "r0"))))
        _ = try await engine.refreshState()
        #expect(try effectiveRuns(container).unsyncedCount == 1)

        // The receipt confirms the write; its follow-up refresh fails.
        let row = try #require(ModelContext(container).fetch(FetchDescriptor<PendingSubmission>()).first)
        let operation = try JSONDecoder().decode(SharedGuestOperation.self, from: try #require(row.sharedOperationData))
        let receipt = GuestJSON.object(["ok": .bool(true), "operation": .object([
            "operationId": .string(id.uuidString.lowercased()), "requestDigest": .string(operation.digest),
            "status": .string("completed"), "response": .object(["ok": .bool(true), "sheetRevision": .string("r1")]),
        ])])
        await transport.append(.response(try JSONEncoder().encode(receipt)))
        await engine.drain()

        let effective = try effectiveRuns(container)
        #expect(try ModelContext(container).fetch(FetchDescriptor<PendingSubmission>()).first?.outcome == .committed)
        #expect(attendance(of: contractRun23, in: effective) == namedAndUnnamed.server)
        #expect(effective.unsyncedCount == 0)
    }
}

// MARK: - Overlay rules

@Suite("Effective runs: rules")
struct EffectiveRunsRuleTests {
    private let legacy = snapshot(legacyRun(42, "Fri, 25-Sep", attendees: ["Aaron"]))

    @Test("Replaying a confirmed shared write on a run that already shows it counts nothing twice")
    func idempotentReplay() {
        let saved = namedAndUnnamed.server
        let cached = snapshot(RunRecord(
            rowIndex: 23, date: "Fri, 6-Jan", meet: "Example beach", run: "Soft Sand", actualKm: saved.actualKm,
            attendees: saved.attendees, plusOnes: saved.plusOnes, identity: contractRun23,
            namedGuestIds: saved.namedGuestIds, unnamedGuests: saved.unnamedGuests
        ))
        // The cache was refreshed before the confirmation yet already shows the write.
        let row = outboxRow(["Col"], .merge, status: .done, outcome: .committed, createdAt: 1, row: 23,
                            identity: contractRun23, named: [contractGuestA, contractGuestB], unnamed: 1,
                            lastAttemptAt: 3)
        let effective = EffectiveRuns(cached: [cached], submissions: [row], endpoint: testEndpoint,
                                      refreshedAt: Date(timeIntervalSince1970: 2))
        #expect(effective.runs == [cached])
        #expect(effective.unsyncedCount == 0)
    }

    @Test("Conflicts, closed rows and legacy confirmations never apply")
    func closedRows() {
        let rows = [
            outboxRow(["Col"], .overwrite, status: .conflict, createdAt: 1),
            outboxRow(["Dan"], .merge, status: .done, outcome: .discarded, createdAt: 2),
            outboxRow(["Col"], .merge, status: .done, outcome: .superseded, createdAt: 3),
            // `finish()` already wrote a confirmed legacy row into the cache.
            outboxRow(["Dan"], .merge, status: .done, outcome: .committed, createdAt: 4, lastAttemptAt: 5),
        ]
        let effective = EffectiveRuns(cached: [legacy], submissions: rows, endpoint: testEndpoint, refreshedAt: nil)
        #expect(effective.runs == [legacy])
        #expect(effective.unsyncedCount == 0)
    }

    @Test("Rows for another endpoint or run, or without a guest allocation, are ignored and not counted")
    func unmatchedRows() {
        let shared = snapshot(RunRecord(
            rowIndex: 23, date: "Fri, 6-Jan", meet: "Example beach", run: "Soft Sand",
            attendees: ["Col"], plusOnes: 1, identity: contractRun23, namedGuestIds: [], unnamedGuests: 1
        ))
        let rows = [
            outboxRow(["Col"], .merge, createdAt: 1, endpoint: "https://example.com/other"),
            outboxRow(["Col"], .merge, createdAt: 2, endpoint: nil),
            outboxRow(["Dan"], .merge, createdAt: 3, row: 99),
            outboxRow(["Dan"], .merge, createdAt: 4, row: 23, identity: contractRun23, named: nil, unnamed: 0),
        ]
        let effective = EffectiveRuns(cached: [legacy, shared], submissions: rows, endpoint: testEndpoint, refreshedAt: nil)
        #expect(effective.runs == [legacy, shared])
        #expect(effective.unsyncedCount == 0)
    }

    @Test("Rows apply in creation order, whatever order they arrive in")
    func creationOrder() {
        let rows = [
            outboxRow(["Col"], .merge, createdAt: 2, plusOnes: 3),
            outboxRow(["Dan"], .overwrite, createdAt: 1, plusOnes: 1),
        ]
        let effective = EffectiveRuns(cached: [legacy], submissions: rows, endpoint: testEndpoint, refreshedAt: nil)
        #expect(effective.runs.map(RunAttendance.init) == [RunAttendance(["Col", "Dan"], plusOnes: 3)])
        #expect(effective.unsyncedCount == 2)
    }
}

private let testEndpoint = configuredAPI.endpoint?.absoluteString

/// The store as a screen reads it: the season's cached runs (`RunCacheScope`),
/// the outbox and the season's last refresh.
@MainActor
private func storeInputs(_ container: ModelContainer) throws
    -> (cached: [RunSnapshot], submissions: [PendingSubmissionSnapshot], refreshedAt: Date?) {
    let context = ModelContext(container)
    let cache = try context.fetch(FetchDescriptor<SharedSheetCache>()).first { $0.endpointIdentity == testEndpoint }
    let runs = try context.fetch(FetchDescriptor<ScheduledRun>(sortBy: [SortDescriptor(\.rowIndex)]))
        .map(RunSnapshot.init)
    return (RunCacheScope.runs(runs, endpoint: testEndpoint, state: cache?.state),
            try context.fetch(FetchDescriptor<PendingSubmission>()).map(PendingSubmissionSnapshot.init),
            cache?.refreshedAt)
}

/// The season's effective runs, built from the store as `ChecklistView` builds them.
@MainActor
private func effectiveRuns(_ container: ModelContainer) throws -> EffectiveRuns {
    let store = try storeInputs(container)
    return EffectiveRuns(cached: store.cached, submissions: store.submissions,
                         endpoint: testEndpoint, refreshedAt: store.refreshedAt)
}

private func attendance(of identity: RunIdentity, in effective: EffectiveRuns) -> RunAttendance? {
    effective.runs.first { $0.runIdentity == identity }.map(RunAttendance.init)
}

/// A legacy `stale_revision` conflict carrying the sheet's current state.
private func staleRevision(_ state: SheetState) throws -> Data {
    try JSONEncoder().encode(GuestJSON.object(["ok": .bool(true), "conflict": .object([
        "reason": .string("stale_revision"), "message": .string("The sheet changed."),
        "state": try GuestJSON.value(state),
    ])]))
}

/// A cached run as the store snapshots it, for the pure rule tests.
private func snapshot(_ record: RunRecord) -> RunSnapshot {
    RunSnapshot(
        rowIndex: record.rowIndex, date: record.date, scheduledAt: nil, meet: record.meet, run: record.run,
        approxKm: record.approxKm, actualKm: record.actualKm, attendees: record.attendees, plusOnes: record.plusOnes,
        runIdentity: record.identity, endpointIdentity: testEndpoint,
        namedGuestIds: record.namedGuestIds ?? [], unnamedGuests: record.unnamedGuests, seasonYear: 2026
    )
}

/// An outbox row for the pure rule tests. Times are seconds since 1970.
private func outboxRow(
    _ attendees: [String], _ mode: SubmissionMode,
    status: SubmissionStatus = .queued, outcome: SubmissionDisposition? = nil,
    createdAt: TimeInterval, row: Int = 42, plusOnes: Int? = nil,
    identity: RunIdentity? = nil, named: [String]? = nil, unnamed: Int? = nil,
    endpoint: String? = testEndpoint, lastAttemptAt: TimeInterval? = nil
) -> PendingSubmissionSnapshot {
    PendingSubmissionSnapshot(
        id: UUID(), rowIndex: row, expectedDate: "Fri, 25-Sep", expectedRun: "Soft Sand", attendees: attendees,
        plusOnes: plusOnes, actualKm: nil, mode: mode, status: status,
        createdAt: Date(timeIntervalSince1970: createdAt), outcome: outcome,
        runIdentity: identity, namedGuestIds: named, unnamedGuests: unnamed,
        endpointIdentity: endpoint, lastAttemptAt: lastAttemptAt.map(Date.init(timeIntervalSince1970:))
    )
}
