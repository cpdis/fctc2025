//
//  EventsView.swift
//  FCTCAttendance
//
//  The Events tab (R22, R26): what's coming up, from the offline cache. It feeds
//  `EventsBoard` the `ActiveSeason` (effective runs and all-time priors) plus
//  birthdays, and rebuilds it only when an input changes or the Perth day
//  turns (KTD10):
//
//    @Query rows ──> ActiveSeason.fingerprint (cheap) ──changed──┐
//    clock ───────> now (moves only at Perth midnight) ─changed──┴─> rebuild()
//                                                                    └─> board
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

    /// Changes whenever a board input changes; cheap enough for every render.
    private var boardFingerprint: String {
        ActiveSeason.fingerprint(runtime: runtime, runs: cachedRuns, members: cachedMembers,
                                 submissions: cachedSubmissions, caches: sheetCaches)
    }

    /// Moves the clock only across a Perth day boundary.
    private func advanceClock(to date: Date) {
        guard !BirthdayBoard.calendar.isDate(date, inSameDayAs: now) else { return }
        now = date
    }

    /// The one place the season cache is fetched and decoded.
    private func rebuild() {
        let season = ActiveSeason(runtime: runtime, runs: cachedRuns, members: cachedMembers,
                                  submissions: cachedSubmissions)
        board = EventsBoard(
            runs: season.effective.runs,
            priors: season.priors,
            birthdays: birthdays(state: season.state, cached: season.cached),
            now: now
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
