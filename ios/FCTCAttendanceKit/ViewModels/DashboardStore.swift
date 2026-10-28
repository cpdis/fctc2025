//
//  DashboardStore.swift
//  FCTCAttendanceKit
//
//  The Dashboard tab's observable state (KTD10, KTD13). The view hands the store
//  a cheap fingerprint of its inputs on every data change. The store reads the
//  inputs and rebuilds `DashboardModel` only when the fingerprint moved, so a
//  render never fetches, decodes or rebuilds anything:
//
//    fingerprint ──same──> nothing
//                └─new───> inputs() ──> DashboardModel(season, runs, last season, priors)
//
//  Last season comes from the engine, on the engine's actor (off the main
//  actor), and only after the live season is cached, because the engine anchors
//  "last season" on the newest cached one. The view asks after every data
//  change. The engine fetches at most once per app session and reads its cache
//  row after that, so a repeated answer costs no request and rebuilds nothing:
//
//    loadLastSeason() ──> engine.previousSeasonSnapshot(before:)
//        state   -> .loaded         rebuild when the runs changed, so a
//                                   revalidated snapshot replaces the cached one
//        nil     -> .unavailable    legacy endpoint or no earlier season: hide
//                                   it and stop asking
//        throws  -> .notDownloaded  offline before it was ever fetched; the next
//                                   call tries again. Loaded runs stay.
//
//  Each answer belongs to one shown season. When the live season changes (2027
//  goes live in January), the store forgets the answer, drops any answer still
//  in flight and asks again, so 2027 compares with 2026 and not with 2025. An
//  engine swap does the same.
//
//  The season menu (`select(season:)`) can show an earlier listed season. It
//  comes from a read-only snapshot (`engine.seasonSnapshot(year:)`, cached and
//  revalidated once per session like last season), compares with the season
//  before it, and keeps all-time totals as they are today
//  (`LifetimePriors.rebased`). The outbox overlays only the live season:
//
//    select(2025) ──> .loading ──> seasonSnapshot(2025) ──ok──> .loaded ──> model
//                                   │                          previousSeasonSnapshot(before: 2025)
//                                   └──throws──> .notDownloaded (load() tries again)
//
//  All time (first in the menu) joins the live season, outbox applied, with a
//  snapshot of every earlier listed season, and compares with nothing:
//
//    select(.allTime) ──> .loading ──> seasonSnapshot(2025), ... ──all ok──> .loaded
//                                       └──any throws──> .notDownloaded
//
//  Every view shows the live season's milestone shortlist, as the web does.
//
//  The runner screen's "Since first run" counts from each runner's first run in
//  any season, whatever view is shown (`FirstRuns`). `loadFirstRuns()` fetches
//  every earlier listed season once, through the same engine cache as the menu:
//
//    update ──────────> firstRuns over the live season (until the rest load)
//    loadFirstRuns() ─> seasonSnapshot(each earlier year) ─all ok─> firstRuns over every season
//                                                          └─throws─> live season only; call again
//

import Foundation
import Observation

/// What the Dashboard is built from: the active season with the outbox applied.
public struct DashboardInputs: Sendable {
    public var season: Int
    /// The season's effective runs (`EffectiveRuns.clubRuns`), in sheet order.
    public var runs: [ClubRun]
    /// Lifetime runs before this season, or nil without lifetime totals.
    public var priors: LifetimePriors?
    /// Queued submissions the overlay applied (`EffectiveRuns.unsyncedCount`).
    public var unsyncedCount: Int
    /// Every season year the live state lists (`SheetState.supportedSeasons`),
    /// the menu's source. Empty on a legacy endpoint.
    public var listedSeasons: [Int]
    /// The live sheet's member columns, for All time's Wall. Empty when unknown,
    /// which marks nobody as off the roster.
    public var roster: Set<String>

    public init(
        season: Int,
        runs: [ClubRun],
        priors: LifetimePriors?,
        unsyncedCount: Int,
        listedSeasons: [Int] = [],
        roster: [String] = []
    ) {
        self.season = season
        self.runs = runs
        self.priors = priors
        self.unsyncedCount = unsyncedCount
        self.listedSeasons = listedSeasons
        self.roster = Set(roster.map(ClubRun.memberName))
    }
}

@MainActor
@Observable
public final class DashboardStore {

    /// Where the Vs last year comparison stands.
    public enum LastSeason: Hashable, Sendable {
        /// Not asked yet, or the question is in flight.
        case loading
        /// Nothing to compare with: a legacy endpoint or no earlier season.
        case unavailable
        /// The fetch failed and nothing is cached, as when offline.
        case notDownloaded
        /// Last season's runs are in the model.
        case loaded
    }

    /// Where the shown season stands.
    public enum Showing: Hashable, Sendable {
        /// The live season (the default).
        case live
        /// An earlier season or All time was picked and a snapshot is in flight.
        case loading
        /// A snapshot it needs failed with nothing cached.
        case notDownloaded
        /// The picked view's runs are in the model.
        case loaded
    }

    /// Every card's data. Nil until the shown view has runs.
    public private(set) var model: DashboardModel?
    /// The cards' "Includes N unsynced": the live season's and All time's
    /// outbox overlay. Always 0 for an earlier season.
    public private(set) var unsyncedCount = 0
    public private(set) var lastSeason = LastSeason.loading
    /// What the cards show; nil until the live season has inputs.
    public private(set) var shown: DashboardPeriod?
    public private(set) var showing = Showing.live
    /// The menu's seasons, newest first: the live season and each listed season
    /// before it. Fewer than two means there is nothing to pick.
    public private(set) var seasons: [Int] = []
    /// Each runner's club days since their first run, by name, whatever view
    /// is shown. The live season alone until every earlier listed season has
    /// loaded (`loadFirstRuns()`), since a missing season would drop club days.
    public private(set) var firstRuns: [String: FirstRun] = [:]

    /// The season shown; nil for All time or before the live season loads.
    public var shownSeason: Int? {
        if case .season(let year) = shown { year } else { nil }
    }

    /// The menu, top to bottom: All time, then each season newest first. Empty
    /// while there is only one season (All time would repeat it).
    public var periods: [DashboardPeriod] {
        seasons.count > 1 ? [.allTime] + seasons.map(DashboardPeriod.season) : []
    }

    /// One earlier season as the menu needs it: its runs, and its sheet's
    /// member columns for All time's Wall.
    private struct Snapshot {
        let runs: [ClubRun]
        let roster: Set<String>

        init(_ state: SheetState) {
            runs = state.runs.compactMap { ClubRun($0, season: state.seasonYear) }
            roster = Set(state.roster.map { ClubRun.memberName($0.name) })
        }

        /// A season the live state no longer lists: All time leaves it out.
        init() {
            runs = []
            roster = []
        }
    }

    @ObservationIgnored private var engine: any SyncEngineClient
    @ObservationIgnored private var fingerprint: String?
    @ObservationIgnored private var inputs: DashboardInputs?
    @ObservationIgnored private var previousRuns: [ClubRun]?
    /// The picked view, or nil for the live season, and the earlier seasons'
    /// snapshots it has loaded.
    @ObservationIgnored private var picked: DashboardPeriod?
    @ObservationIgnored private var snapshots: [Int: Snapshot] = [:]
    @ObservationIgnored private var isLoadingPicked = false
    /// The live season that `lastSeason` and `previousRuns` answer for, set
    /// when the question is asked. Nil until the first question.
    @ObservationIgnored private var answeredSeason: Int?
    @ObservationIgnored private var isLoadingLastSeason = false
    /// Moves with every engine swap and live-season change, so an answer to
    /// an older question is dropped.
    @ObservationIgnored private var generation = 0
    /// Earlier listed seasons' runs for `firstRuns`, by year. A season the
    /// live state no longer lists is loaded as no runs.
    @ObservationIgnored private var history: [Int: [ClubRun]] = [:]
    @ObservationIgnored private var isLoadingHistory = false
    /// Moves with every engine swap and live-season change only: picking a
    /// view does not touch first runs.
    @ObservationIgnored private var historyGeneration = 0

    public init(engine: any SyncEngineClient) {
        self.engine = engine
    }

    /// A new connection: forget last season and rebuild on the next `update`,
    /// even when its fingerprint happens to match the old one.
    public func replaceEngine(_ engine: any SyncEngineClient) {
        self.engine = engine
        fingerprint = nil
        forgetPicked()
        forgetLastSeason()
        forgetHistory()
    }

    /// Rebuilds the model when `fingerprint` differs from the last one. `inputs`
    /// runs only then; it may fetch and decode, so it must never run per render.
    /// It returns nil while the season has nothing cached.
    public func update(fingerprint: String, inputs: () -> DashboardInputs?) {
        guard fingerprint != self.fingerprint else { return }
        self.fingerprint = fingerprint
        let liveBefore = self.inputs?.season
        self.inputs = inputs()
        // A new live season (January) returns the menu to it and needs its own
        // comparison.
        if let live = self.inputs?.season, let liveBefore, live != liveBefore {
            forgetPicked()
            forgetLastSeason()
            forgetHistory()
        } else if picked == nil, let season = self.inputs?.season, let answeredSeason, season != answeredSeason {
            forgetLastSeason()
        }
        rebuild()
        rebuildFirstRuns()
    }

    /// Shows `period`: the live season, an earlier listed one from its
    /// snapshot, or All time. The model is nil (`.loading`) until every
    /// snapshot it needs lands.
    public func select(_ period: DashboardPeriod) async {
        guard let live = inputs?.season, period != shown else { return }
        forgetPicked()
        forgetLastSeason()
        if period != .season(live) {
            picked = period
            showing = .loading
        }
        rebuild()
        await load()
    }

    /// Shows one season.
    public func select(season year: Int) async {
        await select(.season(year))
    }

    /// Loads what the shown view still needs: the picked view's snapshots,
    /// then a season's comparison. Call it after each `update`; it asks again
    /// after a failure and costs nothing once both are in.
    public func load() async {
        if !missingSnapshots.isEmpty { await loadPicked() }
        await loadLastSeason()
    }

    /// The earlier seasons the picked view needs and does not have yet.
    private var missingSnapshots: [Int] {
        guard let inputs else { return [] }
        let years: [Int] = switch picked {
        case .season(let year)?: [year]
        case .allTime?: earlierSeasons(inputs)
        case nil: []
        }
        return years.filter { snapshots[$0] == nil }
    }

    /// Every listed season before the live one, newest first.
    private func earlierSeasons(_ inputs: DashboardInputs) -> [Int] {
        Array(Set(inputs.listedSeasons.filter { $0 < inputs.season })).sorted(by: >)
    }

    /// Fetches the picked view's snapshots one at a time. Each comes from the
    /// engine's cache after its first fetch in a session.
    private func loadPicked() async {
        guard let period = picked, !isLoadingPicked else { return }
        isLoadingPicked = true
        let generation = self.generation
        for year in missingSnapshots {
            let result: Result<SheetState?, any Error>
            do {
                result = .success(try await engine.seasonSnapshot(year: year))
            } catch {
                result = .failure(error)
            }
            // A new pick, swap or live season started over; it owns the flags.
            guard generation == self.generation, picked == period else { return }
            switch result {
            case .success(let state?):
                snapshots[year] = Snapshot(state)
            case .success(nil):
                // No longer listed. One season goes back to the live one; All
                // time leaves it out.
                guard period == .allTime else {
                    forgetPicked()
                    rebuild()
                    return
                }
                snapshots[year] = Snapshot()
            case .failure:
                isLoadingPicked = false
                showing = .notDownloaded
                rebuild()
                return
            }
        }
        isLoadingPicked = false
        showing = .loaded
        rebuild()
    }

    /// Asks the engine for last season. Call it after each `update`: it waits
    /// for the live season, retries a failed fetch and picks up a revalidated
    /// snapshot. It stops asking once the answer is `.unavailable`.
    public func loadLastSeason() async {
        // All time compares with nothing (shownSeason is nil).
        guard let season = shownSeason, !isLoadingLastSeason, lastSeason != .unavailable else { return }
        // A picked season waits for its own runs before its comparison.
        guard missingSnapshots.isEmpty else { return }
        isLoadingLastSeason = true
        answeredSeason = season
        let generation = self.generation
        let pickedSeason: Int? = if case .season(let year)? = picked { year } else { nil }
        let result: Result<SheetState?, any Error>
        do {
            result = .success(try await engine.previousSeasonSnapshot(before: pickedSeason))
        } catch {
            result = .failure(error)
        }
        guard generation == self.generation else { return }
        isLoadingLastSeason = false
        switch result {
        case .success(let state?):
            let runs = state.runs.compactMap { ClubRun($0, season: state.seasonYear) }
            // Most answers repeat the cached row; only a change rebuilds.
            guard lastSeason != .loaded || runs != previousRuns else { return }
            previousRuns = runs
            lastSeason = .loaded
            rebuild()
        case .success(nil):
            lastSeason = .unavailable
            if previousRuns != nil {
                previousRuns = nil
                rebuild()
            }
        case .failure:
            // The engine throws only when nothing is cached. Keep what the
            // cards already show.
            if lastSeason != .loaded { lastSeason = .notDownloaded }
        }
    }

    /// Fetches every earlier listed season `firstRuns` still needs, one at a
    /// time; each comes from the engine's cache after its first fetch in a
    /// session. Call it after each `update`: it costs nothing once all are in,
    /// and a failure keeps the live-season counts until the next call.
    public func loadFirstRuns() async {
        guard let inputs, !isLoadingHistory else { return }
        let missing = earlierSeasons(inputs).filter { history[$0] == nil }
        guard !missing.isEmpty else { return }
        isLoadingHistory = true
        let generation = historyGeneration
        for year in missing {
            let state: SheetState?
            do {
                state = try await engine.seasonSnapshot(year: year)
            } catch {
                // A swap or a new live season started over; it owns the flag.
                guard generation == historyGeneration else { return }
                isLoadingHistory = false
                return
            }
            guard generation == historyGeneration else { return }
            history[year] = state.map { state in state.runs.compactMap { ClubRun($0, season: state.seasonYear) } } ?? []
        }
        isLoadingHistory = false
        rebuildFirstRuns()
    }

    /// First runs over every season once each earlier one has loaded, else
    /// over the live season alone. Runs before them are the lifetime totals
    /// less every run counted here.
    private func rebuildFirstRuns() {
        guard let inputs else {
            firstRuns = [:]
            return
        }
        let earlier = earlierSeasons(inputs)
        let runs = earlier.allSatisfy({ history[$0] != nil })
            ? inputs.runs + earlier.flatMap { history[$0] ?? [] }
            : inputs.runs
        firstRuns = FirstRuns.build(runs: runs, before: inputs.priors?.rebased(live: inputs.runs, onto: runs))
    }

    /// Drops the earlier seasons and any fetch still in flight.
    private func forgetHistory() {
        historyGeneration += 1
        history = [:]
        isLoadingHistory = false
    }

    /// Back to the live season.
    private func forgetPicked() {
        picked = nil
        snapshots = [:]
        isLoadingPicked = false
        showing = .live
    }

    /// Drops last season's answer and any question still in flight.
    private func forgetLastSeason() {
        generation += 1
        previousRuns = nil
        answeredSeason = nil
        isLoadingLastSeason = false
        lastSeason = .loading
    }

    private func rebuild() {
        guard let inputs else {
            model = nil
            unsyncedCount = 0
            shown = nil
            seasons = []
            return
        }
        seasons = [inputs.season] + earlierSeasons(inputs)
        // The live season's shortlist, so every view names the same people.
        let milestones = inputs.priors.map { MilestoneBoard.shortlist(priors: $0, season: inputs.runs) }
        switch picked {
        case nil:
            shown = .season(inputs.season)
            model = DashboardModel(season: inputs.season, runs: inputs.runs, previous: previousRuns,
                                   priors: inputs.priors, milestones: milestones)
            unsyncedCount = inputs.unsyncedCount
        case .season(let year)?:
            shown = .season(year)
            unsyncedCount = 0
            guard let runs = snapshots[year]?.runs else {
                model = nil
                return
            }
            model = DashboardModel(season: year, runs: runs, previous: previousRuns,
                                   priors: inputs.priors?.rebased(live: inputs.runs, onto: runs),
                                   milestones: milestones)
        case .allTime?:
            shown = .allTime
            // The live season carries the outbox, so its count stands.
            unsyncedCount = inputs.unsyncedCount
            guard missingSnapshots.isEmpty else {
                model = nil
                return
            }
            let earlier = earlierSeasons(inputs).compactMap { snapshots[$0] }
            let runs = inputs.runs + earlier.flatMap(\.runs)
            // An unknown roster (empty) marks nobody.
            var rosters: [Int: Set<String>] = [:]
            if !inputs.roster.isEmpty { rosters[inputs.season] = inputs.roster }
            for (year, snapshot) in snapshots where !snapshot.roster.isEmpty { rosters[year] = snapshot.roster }
            model = DashboardModel(allTime: runs, rosters: rosters,
                                   priors: inputs.priors?.rebased(live: inputs.runs, onto: runs),
                                   milestones: milestones)
        }
    }
}
