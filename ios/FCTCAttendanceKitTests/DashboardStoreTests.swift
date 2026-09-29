//
//  DashboardStoreTests.swift
//  FCTCAttendanceKitTests
//
//  U17 — the Dashboard store rebuilds its model once per data change, never per
//  render (KTD10). It asks the engine for last season after each data change,
//  keeps each answer to the live season it was asked for, and rebuilds only
//  when the answer changed (KTD13).
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

    /// January 2027: the new live season's first Wednesday.
    private func inputs2027() -> DashboardInputs {
        let run = ClubRun(id: "2027-01-06", date: ClubDate(iso: "2027-01-06")!, season: 2027, run: "Lakes Loop",
                          meet: "Filament", actualKm: 10, attendees: ["Aaron"], plusOnes: 0)
        return DashboardInputs(season: 2027, runs: [run], priors: nil, unsyncedCount: 0)
    }

    /// 2027's last season: 2026, with one early-January Wednesday.
    private let season2026 = SheetState(
        runs: [RunRecord(rowIndex: 2, date: "Wed, 7-Jan", meet: "Filament", run: "Lakes Loop",
                         actualKm: 10, attendees: ["Aaron"])],
        seasonYear: 2026
    )

    /// 2026 is live and lists 2024 and 2025 (and a 2027 tab not live yet).
    private func inputsWithSeasons() -> DashboardInputs {
        var live = inputs()
        live.listedSeasons = [2024, 2025, 2026, 2027]
        live.priors = LifetimePriors(lifetimeTotals: [MemberTotal(name: "Aaron", runs: 150), MemberTotal(name: "Col", runs: 60)],
                                     payload: live.runs)
        live.unsyncedCount = 2
        return live
    }

    @Test("The menu offers the live season and each listed season before it, newest first")
    func seasonMenu() {
        let store = DashboardStore(engine: LastSeasonClient(answers: []))
        store.update(fingerprint: "a") { inputsWithSeasons() }
        #expect(store.seasons == [2026, 2025, 2024])
        #expect(store.shownSeason == 2026)
        #expect(store.showing == .live)
    }

    @Test("Picking 2025 shows its snapshot, compares with 2024, and keeps all-time as today")
    func pickEarlierSeason() async throws {
        let client = LastSeasonClient(answers: [.success(nil), .success(nil)], seasonAnswers: [.success(lastSeason)])
        let store = DashboardStore(engine: client)
        store.update(fingerprint: "a") { inputsWithSeasons() }
        let liveAllTime = try #require(store.model?.runners["Aaron"]?.allTime)

        await store.select(season: 2025)

        #expect(await client.seasonAsks == [2025])
        #expect(await client.befores.last == 2025)
        #expect(store.showing == .loaded)
        #expect(store.shownSeason == 2025)
        #expect(store.model?.season == 2025)
        #expect(store.model?.runs.count == 1)
        #expect(store.unsyncedCount == 0)
        #expect(store.model?.runners["Aaron"]?.allTime == liveAllTime)

        await store.select(season: 2026)
        #expect(store.showing == .live)
        #expect(store.model?.season == 2026)
        #expect(store.unsyncedCount == 2)
    }

    @Test("A picked season that cannot download says so, and load() tries again")
    func pickedSeasonOffline() async {
        let client = LastSeasonClient(answers: [.success(nil)],
                                      seasonAnswers: [.failure(SheetAPIError.network("Offline")), .success(lastSeason)])
        let store = DashboardStore(engine: client)
        store.update(fingerprint: "a") { inputsWithSeasons() }

        await store.select(season: 2025)
        #expect(store.showing == .notDownloaded)
        #expect(store.model == nil)

        await store.load()
        #expect(store.showing == .loaded)
        #expect(store.model?.season == 2025)
    }

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

    @Test("Last season adds the comparison, a revalidated snapshot replaces it and a failure keeps it")
    func lastSeasonRevalidated() async {
        var revalidated = lastSeason
        revalidated.runs.append(RunRecord(rowIndex: 3, date: "Wed, 24-Sep", meet: "Filament", run: "Lakes Loop",
                                          actualKm: 10, attendees: ["Aaron", "Col"]))
        let client = LastSeasonClient(answers: [
            .success(lastSeason), .success(lastSeason), .success(revalidated),
            .failure(URLError(.notConnectedToInternet)),
        ])
        let store = DashboardStore(engine: client)

        // Before the live season is cached, the engine has nothing to anchor on.
        await store.loadLastSeason()
        #expect(await client.asks == 0)

        store.update(fingerprint: "a") { inputs() }
        #expect(store.model?.progress == nil)
        await store.loadLastSeason()
        #expect(store.lastSeason == .loaded)
        #expect(store.model?.headline.vsPrevious?.year == 2025)
        #expect(store.model?.progress?.previous.points.count == 1)

        // The engine repeats its cached row: the model stays as it is.
        let built = store.model
        await store.loadLastSeason()
        #expect(store.model == built)

        // The engine revalidated the row: its answer replaces the old one.
        await store.loadLastSeason()
        #expect(store.model?.progress?.previous.points.count == 2)

        // A later failure keeps the comparison the cards show.
        await store.loadLastSeason()
        #expect(await client.asks == 4)
        #expect(store.lastSeason == .loaded)
        #expect(store.model?.progress?.previous.points.count == 2)
    }

    @Test("A new live season forgets last season's answer and loads its own predecessor")
    func seasonChange() async {
        let client = LastSeasonClient(answers: [.success(lastSeason), .success(season2026)])
        let store = DashboardStore(engine: client)
        store.update(fingerprint: "a") { inputs() }
        await store.loadLastSeason()
        #expect(store.model?.headline.vsPrevious?.year == 2025)

        // January: 2027 goes live. 2025 is two seasons back, so it goes at once.
        store.update(fingerprint: "b") { inputs2027() }
        #expect(store.lastSeason == .loading)
        #expect(store.model?.season == 2027)
        #expect(store.model?.progress == nil)

        await store.loadLastSeason()
        #expect(await client.asks == 2)
        #expect(store.lastSeason == .loaded)
        #expect(store.model?.headline.vsPrevious?.year == 2026)
        #expect(store.model?.progress?.previous.year == 2026)
    }

    @Test("An answer still in flight for the old live season is dropped")
    func inFlightOldSeason() async {
        let client = LastSeasonClient(answers: [.success(lastSeason), .success(season2026)])
        let store = DashboardStore(engine: client)
        store.update(fingerprint: "a") { inputs() }
        await client.holdNext()
        let asking = Task { await store.loadLastSeason() }
        await client.waitUntilHeld()

        // 2027 goes live while 2026's question is still out.
        store.update(fingerprint: "b") { inputs2027() }
        await client.release()
        await asking.value
        #expect(store.lastSeason == .loading)
        #expect(store.model?.progress == nil)

        await store.loadLastSeason()
        #expect(await client.asks == 2)
        #expect(store.model?.headline.vsPrevious?.year == 2026)
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

/// Answers `previousSeasonSnapshot(before:)` from a script and counts the
/// questions; `seasonSnapshot(year:)` answers from its own script.
/// It can hold one answer until the test releases it, so the answer lands
/// after the store moved on. No timing sleeps.
private actor LastSeasonClient: SyncEngineClient {
    private var answers: [Result<SheetState?, any Error>]
    private(set) var asks = 0
    /// The `before` year of each last-season question, in order.
    private(set) var befores: [Int?] = []
    private var seasonAnswers: [Result<SheetState?, any Error>]
    private(set) var seasonAsks: [Int] = []
    private var holdsNext = false
    private var held: CheckedContinuation<Void, Never>?
    private var heldStarted: CheckedContinuation<Void, Never>?

    init(answers: [Result<SheetState?, any Error>], seasonAnswers: [Result<SheetState?, any Error>] = []) {
        self.answers = answers
        self.seasonAnswers = seasonAnswers
    }

    func seasonSnapshot(year: Int) async throws -> SheetState? {
        seasonAsks.append(year)
        return try (seasonAnswers.isEmpty ? .success(nil) : seasonAnswers.removeFirst()).get()
    }

    func previousSeasonSnapshot(before year: Int?) async throws -> SheetState? {
        asks += 1
        befores.append(year)
        let answer: Result<SheetState?, any Error> = answers.isEmpty ? .success(nil) : answers.removeFirst()
        if holdsNext {
            holdsNext = false
            await withCheckedContinuation { continuation in
                held = continuation
                heldStarted?.resume()
                heldStarted = nil
            }
        }
        return try answer.get()
    }

    func holdNext() { holdsNext = true }
    func waitUntilHeld() async {
        guard held == nil else { return }
        await withCheckedContinuation { heldStarted = $0 }
    }
    func release() {
        held?.resume()
        held = nil
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
