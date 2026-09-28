//
//  DashboardStoreTests.swift
//  FCTCAttendanceKitTests
//
//  U17 — the Dashboard store rebuilds its model once per data change, never per
//  render (KTD10), and asks the engine for last season once (KTD13).
//

import Foundation
import Testing

@testable import FCTCAttendanceKit

@MainActor
@Suite("Dashboard store")
struct DashboardStoreTests {

    /// Two Wednesdays of 2026: Aaron runs both, Col the second.
    private func inputs(unsynced: Int = 0) -> DashboardInputs {
        let runs = [("2026-09-16", ["Aaron"]), ("2026-09-23", ["Aaron", "Col"])].map { iso, names in
            ClubRun(id: iso, date: ClubDate(iso: iso)!, season: 2026, run: "Lakes Loop", meet: "Filament",
                    actualKm: 10, attendees: names, plusOnes: 0)
        }
        return DashboardInputs(season: 2026, runs: runs, priors: nil, unsyncedCount: unsynced)
    }

    /// Last season: one Wednesday before this season's latest month and day.
    private let lastSeason = SheetState(
        runs: [RunRecord(rowIndex: 2, date: "Wed, 17-Sep", meet: "Filament", run: "Lakes Loop",
                         actualKm: 10, attendees: ["Aaron"])],
        seasonYear: 2025
    )

    @Test("The same fingerprint neither reads the inputs nor rebuilds")
    func sameFingerprint() {
        let store = DashboardStore(engine: LastSeasonClient(answers: []))
        var reads = 0
        store.update(fingerprint: "a") { reads += 1; return inputs() }
        let built = store.model
        store.update(fingerprint: "a") { reads += 1; return inputs(unsynced: 3) }
        store.update(fingerprint: "a") { reads += 1; return nil }

        #expect(reads == 1)
        #expect(store.model == built)
        #expect(store.model?.headline.runs == 2)
        #expect(store.unsyncedCount == 0)
    }

    @Test("A new fingerprint reads the inputs and rebuilds")
    func newFingerprint() {
        let store = DashboardStore(engine: LastSeasonClient(answers: []))
        store.update(fingerprint: "a") { inputs() }
        store.update(fingerprint: "b") { inputs(unsynced: 1) }
        #expect(store.unsyncedCount == 1)

        // A season with nothing cached has no model.
        store.update(fingerprint: "c") { nil }
        #expect(store.model == nil)
        #expect(store.unsyncedCount == 0)
    }

    @Test("Last season is asked once and adds the comparison")
    func lastSeasonOnce() async {
        let client = LastSeasonClient(answers: [.success(lastSeason)])
        let store = DashboardStore(engine: client)

        // Before the live season is cached, the engine has nothing to anchor on.
        await store.loadLastSeason()
        #expect(await client.asks == 0)

        store.update(fingerprint: "a") { inputs() }
        #expect(store.model?.progress == nil)
        await store.loadLastSeason()
        await store.loadLastSeason()

        #expect(await client.asks == 1)
        #expect(store.lastSeason == .loaded)
        #expect(store.model?.headline.vsPrevious?.year == 2025)
        #expect(store.model?.progress?.previous.points.count == 1)
    }

    @Test("A legacy endpoint has no last season, and it is not asked again")
    func unavailable() async {
        let client = LastSeasonClient(answers: [.success(nil)])
        let store = DashboardStore(engine: client)
        store.update(fingerprint: "a") { inputs() }
        await store.loadLastSeason()
        store.update(fingerprint: "b") { inputs() }
        await store.loadLastSeason()

        #expect(await client.asks == 1)
        #expect(store.lastSeason == .unavailable)
        #expect(store.model?.progress == nil)
    }

    @Test("Offline, last season is not downloaded until a retry succeeds")
    func notDownloadedThenRetry() async {
        let client = LastSeasonClient(answers: [.failure(URLError(.notConnectedToInternet)), .success(lastSeason)])
        let store = DashboardStore(engine: client)
        store.update(fingerprint: "a") { inputs() }
        await store.loadLastSeason()
        #expect(store.lastSeason == .notDownloaded)
        #expect(store.model?.progress == nil)

        await store.loadLastSeason()
        #expect(await client.asks == 2)
        #expect(store.lastSeason == .loaded)
        #expect(store.model?.progress != nil)
    }

    @Test("A new engine rebuilds from the next update and asks again")
    func replacedEngine() async {
        let store = DashboardStore(engine: LastSeasonClient(answers: [.success(lastSeason)]))
        store.update(fingerprint: "a") { inputs() }
        await store.loadLastSeason()
        #expect(store.lastSeason == .loaded)

        let replacement = LastSeasonClient(answers: [.success(nil)])
        store.replaceEngine(replacement)
        #expect(store.lastSeason == .loading)
        var reads = 0
        store.update(fingerprint: "a") { reads += 1; return inputs() }
        #expect(reads == 1)
        #expect(store.model?.progress == nil)

        await store.loadLastSeason()
        #expect(await replacement.asks == 1)
        #expect(store.lastSeason == .unavailable)
    }
}

/// Answers `previousSeasonSnapshot()` from a script and counts the questions.
private actor LastSeasonClient: SyncEngineClient {
    private var answers: [Result<SheetState?, any Error>]
    private(set) var asks = 0

    init(answers: [Result<SheetState?, any Error>]) {
        self.answers = answers
    }

    func previousSeasonSnapshot() async throws -> SheetState? {
        asks += 1
        return try answers.isEmpty ? nil : answers.removeFirst().get()
    }

    nonisolated var events: AsyncStream<SyncEvent> { AsyncStream { $0.finish() } }
    func refreshState() async throws -> SheetState { throw SheetAPIError.notImplemented }
    func enqueue(_ submission: AttendanceSubmission) async throws -> UUID { throw SheetAPIError.notImplemented }
    func enqueue(draft: AttendanceDraft, mode: SubmissionMode, deviceName: String?) async throws -> UUID {
        throw SheetAPIError.notImplemented
    }
    func drain() async {}
    func addMember(name: String) async throws -> AddMemberResult { throw SheetAPIError.notImplemented }
    func addRun(_ request: AddRunRequest) async throws -> AddRunResult { throw SheetAPIError.notImplemented }
    func resolveConflict(id: UUID, action: ConflictResolutionAction) async throws -> UUID? {
        throw SheetAPIError.notImplemented
    }
}
