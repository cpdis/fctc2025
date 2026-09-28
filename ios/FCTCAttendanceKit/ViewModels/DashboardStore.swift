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
//  Last season comes from the engine once, on the engine's actor (off the main
//  actor), and only after the live season is cached, because the engine anchors
//  "last season" on the newest cached one:
//
//    loadLastSeason() ──> engine.previousSeasonSnapshot()
//        state   -> .loaded         rebuild once with last season's runs
//        nil     -> .unavailable    legacy endpoint or no earlier season: hide it
//        throws  -> .notDownloaded  offline before it was ever fetched; the next
//                                   call (the next data change) tries again
//
//  A finished season never changes, so once the answer is loaded or unavailable
//  the store never asks again, until the engine is replaced.
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

    public init(season: Int, runs: [ClubRun], priors: LifetimePriors?, unsyncedCount: Int) {
        self.season = season
        self.runs = runs
        self.priors = priors
        self.unsyncedCount = unsyncedCount
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

    /// Every card's data. Nil until the active season has inputs.
    public private(set) var model: DashboardModel?
    /// The cards' "Includes N unsynced".
    public private(set) var unsyncedCount = 0
    public private(set) var lastSeason = LastSeason.loading

    @ObservationIgnored private var engine: any SyncEngineClient
    @ObservationIgnored private var fingerprint: String?
    @ObservationIgnored private var inputs: DashboardInputs?
    @ObservationIgnored private var previousRuns: [ClubRun]?
    @ObservationIgnored private var isLoadingLastSeason = false
    /// Moves with every engine swap, so a stale engine's answer is dropped.
    @ObservationIgnored private var engineGeneration = 0

    public init(engine: any SyncEngineClient) {
        self.engine = engine
    }

    /// A new connection: forget last season and rebuild on the next `update`,
    /// even when its fingerprint happens to match the old one.
    public func replaceEngine(_ engine: any SyncEngineClient) {
        engineGeneration += 1
        self.engine = engine
        fingerprint = nil
        previousRuns = nil
        isLoadingLastSeason = false
        lastSeason = .loading
    }

    /// Rebuilds the model when `fingerprint` differs from the last one. `inputs`
    /// runs only then; it may fetch and decode, so it must never run per render.
    /// It returns nil while the season has nothing cached.
    public func update(fingerprint: String, inputs: () -> DashboardInputs?) {
        guard fingerprint != self.fingerprint else { return }
        self.fingerprint = fingerprint
        self.inputs = inputs()
        rebuild()
    }

    /// Asks the engine for last season unless it already answered. Call it after
    /// each `update`: it waits for the live season, and retries a failed fetch.
    public func loadLastSeason() async {
        guard inputs != nil, !isLoadingLastSeason,
              lastSeason == .loading || lastSeason == .notDownloaded else { return }
        isLoadingLastSeason = true
        let generation = engineGeneration
        let result: Result<SheetState?, any Error>
        do {
            result = .success(try await engine.previousSeasonSnapshot())
        } catch {
            result = .failure(error)
        }
        guard generation == engineGeneration else { return }
        isLoadingLastSeason = false
        switch result {
        case .success(let state?):
            previousRuns = state.runs.compactMap { ClubRun($0, season: state.seasonYear) }
            lastSeason = .loaded
            rebuild()
        case .success(nil):
            lastSeason = .unavailable
        case .failure:
            lastSeason = .notDownloaded
        }
    }

    private func rebuild() {
        guard let inputs else {
            model = nil
            unsyncedCount = 0
            return
        }
        model = DashboardModel(season: inputs.season, runs: inputs.runs, previous: previousRuns, priors: inputs.priors)
        unsyncedCount = inputs.unsyncedCount
    }
}
