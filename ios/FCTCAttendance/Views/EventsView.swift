//
//  EventsView.swift
//  FCTCAttendance
//
//  The Events tab (R22, R26): what's coming up, from the offline cache. It feeds
//  `EventsBoard` the active season's effective runs (the cache with the outbox
//  applied, KTD11), all-time priors (KTD12) and birthdays, and rebuilds it only
//  when an input changes or the Perth day turns (KTD10):
//
//    @Query rows ──> boardFingerprint (cheap, no JSON) ──changed──┐
//    clock ───────> now (moves only at Perth midnight) ──changed──┴─> rebuild()
//                                                                     └─> board
//
//  `rebuild()` is the only place that fetches and decodes the season cache, so
//  a render never does.
//

import FCTCAttendanceKit
import SwiftData
import SwiftUI
import UIKit

struct EventsView: View {
    let runtime: AppRuntime
    /// The Events tab's stack, owned by RootTabView so an engine swap can reset it.
    @Binding var path: NavigationPath

    @Query(sort: \ScheduledRun.rowIndex) private var cachedRuns: [ScheduledRun]
    @Query(sort: \Member.name) private var cachedMembers: [Member]
    /// Every outbox row, finished ones included: a confirmed shared row stays in
    /// the overlay until its season refreshes (KTD11).
    @Query(sort: \PendingSubmission.createdAt) private var cachedSubmissions: [PendingSubmission]
    @Query private var sheetCaches: [SharedSheetCache]
    @Environment(\.scenePhase) private var scenePhase

    /// The clock the board reads. It moves only when the Perth day changes, so
    /// This week and Birthdays turn over at midnight without a rebuild a minute.
    @State private var now = Date.now
    /// Nil until the first build, so no section flashes its empty state.
    @State private var board: EventsBoard?

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if let board {
                    ThisWeekSection(runs: board.thisWeek)
                    SpecialsSection(specials: board.specials)
                    MilestonesSection(candidates: board.milestones, emptyPhrase: runtime.milestoneEmptyPhrase)
                    BirthdaysSection(birthdays: board.birthdays)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Events")
        }
        .onChange(of: boardFingerprint, initial: true) { _, _ in rebuild() }
        .onChange(of: now) { _, _ in rebuild() }
        // Device midnight may differ from Perth midnight while travelling, so
        // poll while active. This never fetches sheet data.
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { date in
            if scenePhase == .active { advanceClock(to: date) }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            advanceClock(to: .now)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { advanceClock(to: .now) }
        }
    }

    /// Changes whenever a board input changes: a cached run (every cache write
    /// moves its revision), an outbox row's status, a season's refresh, the live
    /// state, or a member's cached total or birthday. It reads no JSON, so it is
    /// cheap to build per render; the board is not.
    private var boardFingerprint: String {
        let endpoint = runtime.config.endpoint?.absoluteString ?? ""
        let live = runtime.activeState.map { "\($0.spreadsheetId ?? ""):\($0.seasonSheetId ?? 0):\($0.sheetRevision)" }
        let runs = cachedRuns.map { "\($0.cacheKey):\($0.cachedRevision ?? ""):\($0.attendees.count):\($0.plusOnes)" }
        let outbox = cachedSubmissions.map { "\($0.id):\($0.stateRaw)" }
        let caches = sheetCaches.filter { $0.endpointIdentity == endpoint }
            .map { "\($0.key):\($0.refreshedAt.timeIntervalSinceReferenceDate)" }
        let members = cachedMembers.map {
            "\($0.name):\($0.lifetimeRuns):\($0.birthdayMonth ?? 0)-\($0.birthdayDay ?? 0)"
                + ":\($0.birthdayEndpointIdentity ?? ""):\($0.birthdaySeasonYear ?? 0)"
        }
        return ([endpoint, live ?? ""] + runs + outbox + caches + members).joined(separator: "|")
    }

    /// Moves the clock only across a Perth day boundary.
    private func advanceClock(to date: Date) {
        guard !BirthdayBoard.calendar.isDate(date, inSameDayAs: now) else { return }
        now = date
    }

    /// The one place the season cache is fetched and decoded.
    private func rebuild() {
        let endpoint = runtime.config.endpoint?.absoluteString
        let active = runtime.activeSheetCache
        let cached = runtime.activeRuns(in: cachedRuns).map(RunSnapshot.init)
        let effective = EffectiveRuns(
            cached: cached,
            submissions: cachedSubmissions.map(PendingSubmissionSnapshot.init),
            endpoint: endpoint,
            refreshedAt: active?.refreshedAt
        )
        board = EventsBoard(
            runs: effective.runs,
            priors: priors(state: active?.state, cached: cached),
            birthdays: birthdays(state: active?.state, cached: cached),
            now: now
        )
    }

    /// Lifetime runs before this season (KTD12): the server's totals for the
    /// current roster, less that same payload's runs. Before a `getState` with
    /// totals (a cold legacy launch), the members' cached totals stand in, less
    /// the cached season.
    private func priors(state: SheetState?, cached: [RunSnapshot]) -> LifetimePriors? {
        if let state, !state.lifetimeTotals.isEmpty { return LifetimePriors(rosterOf: state) }
        guard !cachedMembers.isEmpty else { return nil }
        return LifetimePriors(
            lifetimeTotals: cachedMembers.map { MemberTotal(name: $0.name, runs: $0.lifetimeRuns) },
            payload: cached.compactMap { ClubRun($0) }
        )
    }

    /// The active season's birthdays: live from the sheet state when it has
    /// them, else the members' cached copy for this endpoint and season. Nil
    /// means an older server that sends none, which has its own empty text.
    private func birthdays(state: SheetState?, cached: [RunSnapshot]) -> [MemberBirthday]? {
        if let birthdays = state?.birthdays { return birthdays }
        let endpoint = runtime.config.endpoint?.absoluteString
        let seasonYear = state?.seasonYear ?? cached.compactMap(\.seasonYear).max()
        let hasBirthdayCache = cachedMembers.contains {
            $0.birthdayEndpointIdentity != nil && $0.birthdayEndpointIdentity == endpoint
                && (seasonYear == nil || $0.birthdaySeasonYear == seasonYear)
        }
        guard hasBirthdayCache else { return nil }
        return cachedMembers.compactMap { $0.birthday(for: endpoint, seasonYear: seasonYear) }
    }
}
