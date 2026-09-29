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

    public init(season: Int, runs: [ClubRun], priors: LifetimePriors?, unsyncedCount: Int, listedSeasons: [Int] = []) {
        self.season = season
        self.runs = runs
        self.priors = priors
        self.unsyncedCount = unsyncedCount
        self.listedSeasons = listedSeasons
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
        /// An earlier season was picked and its snapshot is in flight.
        case loading
        /// The picked season's fetch failed with nothing cached.
        case notDownloaded
        /// The picked season's runs are in the model.
        case loaded
    }

    /// Every card's data. Nil until the shown season has runs.
    public private(set) var model: DashboardModel?
    /// The cards' "Includes N unsynced". Always 0 for an earlier season.
    public private(set) var unsyncedCount = 0
    public private(set) var lastSeason = LastSeason.loading
    /// The season the cards show; nil until the live season has inputs.
    public private(set) var shownSeason: Int?
    public private(set) var showing = Showing.live
    /// The menu's seasons, newest first: the live season and each listed season
    /// before it. Fewer than two means there is nothing to pick.
    public private(set) var seasons: [Int] = []

    @ObservationIgnored private var engine: any SyncEngineClient
    @ObservationIgnored private var fingerprint: String?
    @ObservationIgnored private var inputs: DashboardInputs?
    @ObservationIgnored private var previousRuns: [ClubRun]?
    /// A picked earlier season, or nil for the live one, and its runs once loaded.
    @ObservationIgnored private var picked: Int?
    @ObservationIgnored private var pickedRuns: [ClubRun]?
    @ObservationIgnored private var isLoadingPicked = false
    /// The live season that `lastSeason` and `previousRuns` answer for, set
    /// when the question is asked. Nil until the first question.
    @ObservationIgnored private var answeredSeason: Int?
    @ObservationIgnored private var isLoadingLastSeason = false
    /// Moves with every engine swap and live-season change, so an answer to
    /// an older question is dropped.
    @ObservationIgnored private var generation = 0

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
        } else if picked == nil, let season = self.inputs?.season, let answeredSeason, season != answeredSeason {
            forgetLastSeason()
        }
        rebuild()
    }

    /// Shows `year`: the live season, or an earlier listed one from its
    /// snapshot. The model is nil (`.loading`) until the snapshot lands.
    public func select(season year: Int) async {
        guard let live = inputs?.season, year != shownSeason else { return }
        forgetPicked()
        forgetLastSeason()
        if year != live {
            picked = year
            showing = .loading
        }
        rebuild()
        await load()
    }

    /// Loads what the shown season still needs: a picked season's snapshot,
    /// then its comparison. Call it after each `update`; it asks again after a
    /// failure and costs nothing once both are in.
    public func load() async {
        if picked != nil, pickedRuns == nil { await loadPickedSeason() }
        await loadLastSeason()
    }

    private func loadPickedSeason() async {
        guard let year = picked, !isLoadingPicked else { return }
        isLoadingPicked = true
        let generation = self.generation
        let result: Result<SheetState?, any Error>
        do {
            result = .success(try await engine.seasonSnapshot(year: year))
        } catch {
            result = .failure(error)
        }
        guard generation == self.generation, picked == year else { return }
        isLoadingPicked = false
        switch result {
        case .success(let state?):
            pickedRuns = state.runs.compactMap { ClubRun($0, season: state.seasonYear) }
            showing = .loaded
        case .success(nil):
            // No longer listed: back to the live season.
            forgetPicked()
        case .failure:
            showing = .notDownloaded
        }
        rebuild()
    }

    /// Asks the engine for last season. Call it after each `update`: it waits
    /// for the live season, retries a failed fetch and picks up a revalidated
    /// snapshot. It stops asking once the answer is `.unavailable`.
    public func loadLastSeason() async {
        guard let season = shownSeason, !isLoadingLastSeason, lastSeason != .unavailable else { return }
        // A picked season waits for its own runs before its comparison.
        if picked != nil, pickedRuns == nil { return }
        isLoadingLastSeason = true
        answeredSeason = season
        let generation = self.generation
        let result: Result<SheetState?, any Error>
        do {
            result = .success(try await engine.previousSeasonSnapshot(before: picked))
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

    /// Back to the live season.
    private func forgetPicked() {
        picked = nil
        pickedRuns = nil
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
            shownSeason = nil
            seasons = []
            return
        }
        seasons = Array(Set([inputs.season] + inputs.listedSeasons.filter { $0 < inputs.season })).sorted(by: >)
        guard let year = picked else {
            shownSeason = inputs.season
            model = DashboardModel(season: inputs.season, runs: inputs.runs, previous: previousRuns, priors: inputs.priors)
            unsyncedCount = inputs.unsyncedCount
            return
        }
        shownSeason = year
        unsyncedCount = 0
        guard let runs = pickedRuns else {
            model = nil
            return
        }
        model = DashboardModel(season: year, runs: runs, previous: previousRuns,
                               priors: inputs.priors?.rebased(live: inputs.runs, onto: runs))
    }
}
