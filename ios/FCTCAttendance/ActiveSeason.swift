//
//  ActiveSeason.swift
//  FCTCAttendance
//
//  The active season as the Events and Dashboard tabs read it (R26): the cached
//  runs with the outbox applied (KTD11) and the lifetime priors (KTD12). Both
//  tabs rebuild their boards from it only when the fingerprint changes (KTD10):
//
//    @Query rows ──> ActiveSeason.fingerprint (cheap, no JSON) ──changed──┐
//                                                                         v
//                    ActiveSeason(...) ── fetches and decodes the cache ──> board
//
//  Building one reads the season cache, so build it once per data change and
//  never in a view body.
//

import FCTCAttendanceKit
import Foundation
import SwiftData

@MainActor
struct ActiveSeason {
    /// The active season's server state; nil before the first load.
    let state: SheetState?
    /// The season's cached runs, before the outbox.
    let cached: [RunSnapshot]
    /// The cached runs with the outbox applied.
    let effective: EffectiveRuns
    /// Lifetime runs before this season; nil without lifetime totals.
    let priors: LifetimePriors?

    init(runtime: AppRuntime, runs: [ScheduledRun], members: [Member], submissions: [PendingSubmission]) {
        let active = runtime.activeSheetCache
        let cached = runtime.activeRuns(in: runs).map(RunSnapshot.init)
        state = active?.state
        self.cached = cached
        effective = EffectiveRuns(
            cached: cached,
            submissions: submissions.map(PendingSubmissionSnapshot.init),
            endpoint: runtime.config.endpoint?.absoluteString,
            refreshedAt: active?.refreshedAt
        )
        priors = Self.priors(state: active?.state, cached: cached, members: members)
    }

    /// Changes whenever a tab input changes: a cached run (every cache write
    /// moves its revision), an outbox row's status, a season's refresh, the live
    /// state, or a member's cached total or birthday. It reads no JSON, so it is
    /// cheap to build per render; an `ActiveSeason` is not.
    ///
    /// - Parameter submissions: every outbox row, finished ones included. A
    ///   confirmed shared row stays in the overlay until its season refreshes.
    static func fingerprint(
        runtime: AppRuntime,
        runs: [ScheduledRun],
        members: [Member],
        submissions: [PendingSubmission],
        caches: [SharedSheetCache]
    ) -> String {
        let endpoint = runtime.config.endpoint?.absoluteString ?? ""
        let live = runtime.activeState.map { "\($0.spreadsheetId ?? ""):\($0.seasonSheetId ?? 0):\($0.sheetRevision)" }
        let runs = runs.map { "\($0.cacheKey):\($0.cachedRevision ?? ""):\($0.attendees.count):\($0.plusOnes)" }
        let outbox = submissions.map { "\($0.id):\($0.stateRaw)" }
        let caches = caches.filter { $0.endpointIdentity == endpoint }
            .map { "\($0.key):\($0.refreshedAt.timeIntervalSinceReferenceDate)" }
        let members = members.map {
            "\($0.name):\($0.lifetimeRuns):\($0.birthdayMonth ?? 0)-\($0.birthdayDay ?? 0)"
                + ":\($0.birthdayEndpointIdentity ?? ""):\($0.birthdaySeasonYear ?? 0)"
        }
        return ([endpoint, live ?? ""] + runs + outbox + caches + members).joined(separator: "|")
    }

    /// Lifetime runs before this season (KTD12): the server's totals for the
    /// current roster, less that same payload's runs. Before a `getState` with
    /// totals (a cold legacy launch), the members' cached totals stand in, less
    /// the cached season.
    private static func priors(state: SheetState?, cached: [RunSnapshot], members: [Member]) -> LifetimePriors? {
        if let state, !state.lifetimeTotals.isEmpty { return LifetimePriors(rosterOf: state) }
        guard !members.isEmpty else { return nil }
        return LifetimePriors(
            lifetimeTotals: members.map { MemberTotal(name: $0.name, runs: $0.lifetimeRuns) },
            payload: cached.compactMap { ClubRun($0) }
        )
    }
}
