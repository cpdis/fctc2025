//
//  SeasonSnapshotTests.swift
//  FCTCAttendanceKitTests
//
//  U14: last season is a read-only snapshot for the Dashboard's "Vs last year"
//  card. Fetching it must never disturb the live season: no reconcile, no
//  `latestState`, no reminders, and a cold engine must keep writing to the live tab.
//  A cached row is fetched again once per engine (app session), and serves
//  offline when that fetch fails.
//

import Foundation
import SwiftData
import Testing

@testable import FCTCAttendanceKit

@Suite("Previous-season snapshot", .serialized)
struct SeasonSnapshotTests {
    @Test("Fetching last season leaves members, runs, guests, reminders and the live season alone")
    func readOnly() async throws {
        let container = try guestContainer()
        let transport = StubTransport([.response(try stateData(liveSeason())), .response(try stateData(lastSeason()))])
        let reminders = RecordingReminders()
        let engine = snapshotEngine(container, transport, reminders: reminders)
        _ = try await engine.refreshState()
        let before = try footprint(container)

        let snapshot = try #require(try await engine.previousSeasonSnapshot())

        #expect(snapshot.seasonSheetId == 25)
        #expect(snapshot.runs.map(\.runId) == [lastSeasonRunId])
        let request = try JSONDecoder().decode(GuestJSON.self, from: #require(await transport.requests.last))
        #expect(request["action"]?.string == "getState")
        #expect(request["seasonSheetId"]?.int == 25)
        #expect(try footprint(container) == before)
        #expect(await reminders.reconciledSeasons == [26])
        #expect(await engine.latestState?.seasonSheetId == 26)
        #expect(try await engine.currentSharedState()?.seasonSheetId == 26)
        let rows = try ModelContext(container).fetch(FetchDescriptor<SharedSheetCache>())
        #expect(Set(rows.map(\.seasonSheetId)) == [25, 26])
    }

    @Test("A cold engine returns the live season after the snapshot, so an offline run lands in the live tab")
    func coldEngine() async throws {
        let container = try guestContainer()
        let warm = snapshotEngine(container, StubTransport([.response(try stateData(liveSeason())), .response(try stateData(lastSeason()))]))
        _ = try await warm.refreshState()
        _ = try await warm.previousSeasonSnapshot()
        // The snapshot is the most recent refresh. Newest-refresh-wins would pick it.
        let rows = try ModelContext(container).fetch(FetchDescriptor<SharedSheetCache>())
        let snapshotRow = try #require(rows.first { $0.seasonSheetId == 25 })
        let liveRow = try #require(rows.first { $0.seasonSheetId == 26 })
        #expect(snapshotRow.refreshedAt > liveRow.refreshedAt)

        let offline = StubTransport()
        let cold = snapshotEngine(container, offline)
        #expect(await cold.latestState == nil)
        #expect(try await cold.currentSharedState()?.seasonSheetId == 26)
        await #expect(throws: (any Error).self) {
            try await cold.addRun(AddRunRequest(date: "Fri, 13-Jan", meet: "Example beach", run: "Tempo"))
        }
        let operation = try #require(ModelContext(container).fetch(FetchDescriptor<PendingGuestOperation>()).first?.operation)
        #expect(operation.action == "addRun")
        #expect(operation.request["seasonSheetId"]?.int == 26)
        #expect(operation.request["spreadsheetId"]?.string == "illustrative-workbook")
        let sent = try JSONDecoder().decode(GuestJSON.self, from: #require(await offline.requests.first))
        #expect(sent["seasonSheetId"]?.int == 26)
    }

    @Test("The first call on an engine fetches last season again, even with a row cached; later calls read it")
    func revalidatedOncePerSession() async throws {
        let container = try guestContainer()
        // An earlier session cached last season while it still had one run.
        let earlier = snapshotEngine(container, StubTransport([.response(try stateData(liveSeason())),
                                                               .response(try stateData(lastSeason()))]))
        _ = try await earlier.refreshState()
        _ = try await earlier.previousSeasonSnapshot()

        // This session: the sheet has since gained a run for last season.
        let final = try finalLastSeason()
        let transport = StubTransport([.response(try stateData(liveSeason())), .response(try stateData(final))])
        let reminders = RecordingReminders()
        let engine = snapshotEngine(container, transport, reminders: reminders)
        _ = try await engine.refreshState()
        let before = try footprint(container)

        let first = try await engine.previousSeasonSnapshot()
        let second = try await engine.previousSeasonSnapshot()
        #expect(first == final)
        #expect(second == final)
        #expect(await transport.requestCount == 2)
        let request = try JSONDecoder().decode(GuestJSON.self, from: #require(await transport.requests.last))
        #expect(request["seasonSheetId"]?.int == 25)
        #expect(try snapshotRow(container)?.state == final)
        // The live season, the caches it owns and the reminders stay as they were.
        #expect(try footprint(container) == before)
        #expect(await reminders.reconciledSeasons == [26])
        #expect(await engine.latestState?.seasonSheetId == 26)
    }

    @Test("When the fetch fails, the cached row serves and the next call tries again", arguments: Failure.allCases)
    func cachedRowServesOffline(_ failure: Failure) async throws {
        let container = try guestContainer()
        let warm = snapshotEngine(container, StubTransport([.response(try stateData(liveSeason())),
                                                            .response(try stateData(lastSeason()))]))
        _ = try await warm.refreshState()
        let cached = try await warm.previousSeasonSnapshot()
        let cachedRow = try #require(try snapshotRow(container))
        let cachedAt = cachedRow.refreshedAt

        // A relaunch: the new engine has not fetched last season yet.
        let transport = StubTransport([failureStep(failure, live: try stateData(liveSeason()))])
        let cold = snapshotEngine(container, transport)
        #expect(try await cold.previousSeasonSnapshot() == cached)
        #expect(await transport.requestCount == 1)
        #expect(try snapshotRow(container)?.refreshedAt == cachedAt)
        #expect(try snapshotRow(container)?.state == cached)

        // Back online, the next call fetches, and the one after reads the row.
        let final = try finalLastSeason()
        await transport.append(.response(try stateData(final)))
        #expect(try await cold.previousSeasonSnapshot() == final)
        #expect(try await cold.previousSeasonSnapshot() == final)
        #expect(await transport.requestCount == 2)
    }

    /// Colin lists the 2027 tab before he makes it the active season, and an
    /// organiser opens it in Guest recovery (a refresh by season). It is the
    /// highest year and the newest refresh, yet 2026 stays the live season on a
    /// cold launch until a live refresh answers with 2027.
    @Test("A tab opened by season never outranks the live season on a cold launch")
    func futureSeasonTab() async throws {
        let container = try guestContainer()
        var live = try liveSeason()
        live.supportedSeasons?.append(SupportedSeason(seasonSheetId: 27, seasonYear: 2027))
        var next = live
        next.seasonSheetId = 27; next.seasonYear = 2027; next.sheetRevision = "season-2027"; next.runs = []
        let warm = snapshotEngine(container, StubTransport([.response(try stateData(live)), .response(try stateData(next)),
                                                            .response(try stateData(next))]))
        _ = try await warm.refreshState()
        _ = try await warm.refreshState(seasonSheetId: 27)
        #expect(try await snapshotEngine(container, StubTransport()).currentSharedState()?.seasonSheetId == 26)

        // The server now calls 2027 live.
        _ = try await warm.refreshState()
        #expect(try await snapshotEngine(container, StubTransport()).currentSharedState()?.seasonSheetId == 27)
    }

    @Test("Before any live refresh stamps a row, the highest season year is live")
    func unstampedRows() throws {
        let context = ModelContext(try guestContainer())
        let endpoint = try #require(testEndpointIdentity)
        let older = try SharedSheetCache(endpointIdentity: endpoint, state: try lastSeason(),
                                         refreshedAt: Date(timeIntervalSince1970: 200))
        let newer = try SharedSheetCache(endpointIdentity: endpoint, state: try liveSeason(),
                                         refreshedAt: Date(timeIntervalSince1970: 100))
        context.insert(older); context.insert(newer)
        #expect(SharedSheetCache.live(in: [older, newer], endpoint: endpoint)?.state.seasonSheetId == 26)
        older.liveAt = Date(timeIntervalSince1970: 300)
        #expect(SharedSheetCache.live(in: [older, newer], endpoint: endpoint)?.state.seasonSheetId == 25)
        #expect(SharedSheetCache.live(in: [older, newer], endpoint: "https://example.com/other") == nil)
    }

    @Test("Historic navigation does not move the snapshot off the live season's predecessor")
    func historicNavigation() async throws {
        let container = try guestContainer()
        let transport = StubTransport([.response(try stateData(liveSeason())), .response(try stateData(lastSeason())),
                                       .response(try stateData(lastSeason()))])
        let engine = snapshotEngine(container, transport)
        _ = try await engine.refreshState()
        _ = try await engine.refreshState(seasonSheetId: 25)
        // `latestState` now points at 2025; the snapshot still anchors on 2026.
        let snapshot = try await engine.previousSeasonSnapshot()
        #expect(snapshot?.seasonSheetId == 25)
        let request = try JSONDecoder().decode(GuestJSON.self, from: #require(await transport.requests.last))
        #expect(request["seasonSheetId"]?.int == 25)
        #expect(await transport.requestCount == 3)
    }

    enum Unavailable: String, CaseIterable, Sendable { case legacy, unlisted, onlyNewer }

    @Test("Without an earlier listed season the snapshot is unavailable and makes no request", arguments: Unavailable.allCases)
    func unavailable(_ endpoint: Unavailable) async throws {
        let container = try guestContainer()
        var live = try liveSeason()
        switch endpoint {
        case .legacy: break
        case .unlisted: live.supportedSeasons = nil
        // A season created ahead of time is newer, not "last year".
        case .onlyNewer: live.supportedSeasons = [SupportedSeason(seasonSheetId: 26, seasonYear: 2026), SupportedSeason(seasonSheetId: 27, seasonYear: 2027)]
        }
        let transport = StubTransport([.response(endpoint == .legacy ? stateResponse : try stateData(live))])
        let engine = snapshotEngine(container, transport)
        _ = try await engine.refreshState()

        #expect(try await engine.previousSeasonSnapshot() == nil)
        #expect(await transport.requestCount == 1)
        let rows = try ModelContext(container).fetch(FetchDescriptor<SharedSheetCache>())
        #expect(rows.allSatisfy { $0.seasonSheetId == 26 })
    }

    enum Failure: String, CaseIterable, Sendable { case offline, rejected, wrongSeason }

    @Test("A failed snapshot leaves no row behind and the next call tries again", arguments: Failure.allCases)
    func failure(_ failure: Failure) async throws {
        let container = try guestContainer()
        let live = try stateData(liveSeason())
        let step = failureStep(failure, live: live)
        let transport = StubTransport([.response(live), step])
        let engine = snapshotEngine(container, transport)
        _ = try await engine.refreshState()
        let before = try footprint(container)

        await #expect(throws: (any Error).self) { try await engine.previousSeasonSnapshot() }
        let rows = try ModelContext(container).fetch(FetchDescriptor<SharedSheetCache>())
        #expect(rows.map(\.seasonSheetId) == [26])
        #expect(try footprint(container) == before)

        await transport.append(.response(try stateData(lastSeason())))
        #expect(try await engine.previousSeasonSnapshot()?.seasonSheetId == 25)
        #expect(await transport.requestCount == 3)
    }
}

// MARK: - Fixtures

private let lastSeasonRunId = "00000099-2222-4222-8222-222222222222"

/// The contract's live 2026 season, listing 2025 as an earlier season.
private func liveSeason() throws -> SheetState {
    var state = try JSONDecoder().decode(SheetState.self, from: guestStateResponse())
    state.supportedSeasons = [SupportedSeason(seasonSheetId: 25, seasonYear: 2025), SupportedSeason(seasonSheetId: 26, seasonYear: 2026)]
    return state
}

/// Last season differs in every field a reconcile would write: roster, totals,
/// runs and guests. Any leak into the live cache shows up in `footprint`.
private func lastSeason() throws -> SheetState {
    var state = try liveSeason()
    state.seasonSheetId = 25; state.seasonYear = 2025; state.sheetRevision = "season-2025"
    state.roster.append(RosterEntry(name: "Former", colIndex: 8))
    state.lifetimeTotals = [MemberTotal(name: "Col", runs: 999)]
    state.birthdays = [MemberBirthday(name: "Col", month: 1, day: 2)]
    state.guests = [SharedGuest(guestId: "00000009-1111-4111-8111-111111111111", displayName: "Old guest")]
    state.runs = [RunRecord(rowIndex: 23, date: "Fri, 3-Jan", meet: "Beach", run: "Trail",
        identity: RunIdentity(spreadsheetId: "illustrative-workbook", seasonSheetId: 25, runId: lastSeasonRunId),
        namedGuestIds: [], unnamedGuests: 0, seasonYear: 2025)]
    return state
}

/// Last season as the sheet holds it after it ended: one more run than the
/// row cached while it was live.
private func finalLastSeason() throws -> SheetState {
    var state = try lastSeason()
    state.sheetRevision = "season-2025-final"
    state.runs.append(RunRecord(rowIndex: 24, date: "Wed, 31-Dec", meet: "Beach", run: "Trail",
        identity: RunIdentity(spreadsheetId: "illustrative-workbook", seasonSheetId: 25,
                              runId: "00000098-2222-4222-8222-222222222222"),
        namedGuestIds: [], unnamedGuests: 0, seasonYear: 2025))
    return state
}

/// One failed answer to last season's `getState`.
private func failureStep(_ failure: SeasonSnapshotTests.Failure, live: Data) -> StubTransport.Step {
    switch failure {
    case .offline: .failure(.offline)
    case .rejected: .response(json("{\"ok\":false,\"error\":\"bad_secret\",\"message\":\"Rejected\"}"))
    // The server answered, but with the live season instead of last season.
    case .wrongSeason: .response(live)
    }
}

/// The endpoint identity the snapshot engines write their cache rows under.
private let testEndpointIdentity = configuredAPI.endpoint?.absoluteString

/// Last season's cache row.
private func snapshotRow(_ container: ModelContainer) throws -> SharedSheetCache? {
    try ModelContext(container).fetch(FetchDescriptor<SharedSheetCache>()).first { $0.seasonSheetId == 25 }
}

/// Everything a live refresh owns. The snapshot must leave all of it untouched.
private struct Footprint: Equatable {
    var members: [String]
    var runs: [String]
    var guests: [String]
    var liveCache: Data?
}

private func footprint(_ container: ModelContainer) throws -> Footprint {
    let context = ModelContext(container)
    return Footprint(
        members: try context.fetch(FetchDescriptor<Member>()).map {
            "\($0.name)|\($0.colIndex)|\($0.lifetimeRuns)|\($0.isNew)|\(String(describing: $0.birthdayMonth))"
        }.sorted(),
        runs: try context.fetch(FetchDescriptor<ScheduledRun>()).map {
            "\($0.cacheKey)|\($0.attendees)|\($0.plusOnes)|\($0.cachedRevision ?? "")"
        }.sorted(),
        guests: try context.fetch(FetchDescriptor<CachedGuest>()).map(\.key).sorted(),
        liveCache: try context.fetch(FetchDescriptor<SharedSheetCache>()).first { $0.seasonSheetId == 26 }?.stateData
    )
}

private func snapshotEngine(
    _ container: ModelContainer,
    _ transport: any HTTPTransport,
    reminders: any RunReminderScheduling = NoopRunReminderScheduler()
) -> SyncEngine {
    SyncEngine(modelContainer: container, api: SheetAPI(config: configuredAPI, transport: transport),
               clock: SteppingClock(), automaticallyDrains: false, runReminderScheduler: reminders)
}

/// Each reading is a minute later, so the snapshot row is always refreshed
/// after the live row, as it is in the app.
private actor SteppingClock: SyncClock {
    private var instant = Date(timeIntervalSince1970: 1_700_000_000)
    func now() async -> Date {
        instant.addTimeInterval(60)
        return instant
    }
    func sleep(for seconds: TimeInterval) async throws {}
}

private actor RecordingReminders: RunReminderScheduling {
    private(set) var reconciledSeasons: [Int?] = []
    func reconcile(state: SheetState, now: Date) async -> RunReminderReconcileResult {
        reconciledSeasons.append(state.seasonSheetId)
        return .scheduled(0)
    }
}
