//
//  HomeViewModel.swift
//  FCTCAttendanceKit
//

import Foundation
import Observation

@MainActor
@Observable
public final class HomeViewModel {
    public private(set) var activeState: SheetState?
    public private(set) var thisWeekCount = 0
    public private(set) var unsyncedCount = 0
    public private(set) var conflictCount = 0
    public private(set) var todayRun: RunSnapshot?
    public private(set) var syncBanner: SyncBanner?
    public private(set) var isInitialLoading = false
    public private(set) var initialLoadFailed = false
    /// True while the engine drains, so the Unsynced tile can show real work.
    public private(set) var isSyncing = false

    public var lastSyncMessage: String? { syncBanner?.message }
    /// True when the banner shows a failed refresh (not a failed send), so the
    /// app refreshes again when it becomes active.
    public var refreshFailed: Bool { syncBanner != nil && bannerSource == .refresh }

    @ObservationIgnored private var engine: any SyncEngineClient
    @ObservationIgnored private let eventMonitor = SyncEventMonitor()
    @ObservationIgnored private var engineGeneration = 0
    @ObservationIgnored private var refreshGeneration = 0
    /// What set `syncBanner`: a refresh, or the outbox's sync events. Retry Now
    /// repeats the thing that failed.
    private enum BannerSource { case refresh, sync }
    @ObservationIgnored private var bannerSource: BannerSource?

    public init(engine: any SyncEngineClient) {
        self.engine = engine
        observeEvents()
    }

    public func replaceEngine(_ engine: any SyncEngineClient) {
        // Invalidate suspended work before publishing the replacement connection.
        // Its workbook and banners must never inherit the old engine's state.
        engineGeneration += 1
        refreshGeneration += 1
        self.engine = engine
        activeState = nil
        syncBanner = nil
        bannerSource = nil
        isInitialLoading = false
        initialLoadFailed = false
        isSyncing = false
        observeEvents()
    }

    public func update(
        runs: [RunSnapshot],
        submissions: [PendingSubmissionSnapshot],
        pendingGuestChanges: Int = 0,
        guestConflicts: Int = 0,
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        var weekCount = 0
        var earliestToday: RunSnapshot?
        for run in runs {
            guard let scheduledAt = run.scheduledAt else { continue }
            if calendar.isDate(scheduledAt, equalTo: now, toGranularity: .weekOfYear) {
                weekCount += 1
            }
            if calendar.isDate(scheduledAt, inSameDayAs: now),
               earliestToday.map({ Self.ascending(run, $0) }) ?? true {
                earliestToday = run
            }
        }
        thisWeekCount = weekCount
        unsyncedCount = submissions.filter(\.isOutstanding).count + pendingGuestChanges
        conflictCount = submissions.filter { $0.status == .conflict }.count + guestConflicts
        todayRun = earliestToday
    }

    public func refresh(hasCachedState: Bool = true) async {
        refreshGeneration += 1
        let requestGeneration = refreshGeneration
        let connectionGeneration = engineGeneration
        let engine = self.engine
        // The newest request owns both the result and its loading indicator.
        isInitialLoading = !hasCachedState
        if !hasCachedState {
            initialLoadFailed = false
        }
        defer {
            if requestGeneration == refreshGeneration && connectionGeneration == engineGeneration {
                isInitialLoading = false
            }
        }
        do {
            let state = try await engine.refreshState()
            guard requestGeneration == refreshGeneration, connectionGeneration == engineGeneration else { return }
            activeState = state
            initialLoadFailed = false
            if syncBanner != nil { syncBanner = nil }
            bannerSource = nil
        } catch {
            guard requestGeneration == refreshGeneration, connectionGeneration == engineGeneration else { return }
            // A cancelled refresh (its view went away mid-request: a tab switch
            // or a pushed screen) is not a failure. It surfaces as a transport
            // error, which would read as "offline". The next appearance refreshes.
            if Task.isCancelled { return }
            if !hasCachedState { initialLoadFailed = true }
            syncBanner = Self.banner(for: error, refreshing: true)
            bannerSource = .refresh
        }
    }

    /// Repeats what failed: a refresh after a failed refresh, else the outbox.
    public func retry(hasCachedState: Bool = true) async {
        if initialLoadFailed || bannerSource == .refresh {
            await refresh(hasCachedState: hasCachedState)
            return
        }
        if syncBanner != nil { syncBanner = nil }
        bannerSource = nil
        await engine.drain()
    }

    private func observeEvents() {
        let generation = engineGeneration
        eventMonitor.start(engine: engine) { [weak self] event in
            guard let self, generation == engineGeneration else { return }
            switch event {
            case .written:
                syncBanner = SyncBanner(kind: .success, message: "Attendance synced.")
                bannerSource = .sync
            case .conflict:
                syncBanner = SyncBanner(kind: .conflict, message: UserFacingError.conflict)
                bannerSource = .sync
            case .parked(_, let message):
                syncBanner = SyncBanner(
                    kind: message == UserFacingError.offline ? .offline : .parked,
                    message: message
                )
                bannerSource = .sync
            case .authenticationRequired:
                syncBanner = SyncBanner(kind: .authentication, message: UserFacingError.authentication)
                bannerSource = .sync
            case .failed(_, let message), .serviceFailed(let message):
                syncBanner = SyncBanner(kind: .error, message: message)
                bannerSource = .sync
            case .syncActivity(let isActive):
                isSyncing = isActive
            case .queued, .rosterRefreshed:
                break
            }
        }
    }

    /// - Parameter refreshing: a failed refresh, not a failed send: its
    ///   offline copy says what the phone shows instead of the outbox.
    private static func banner(for error: any Error, refreshing: Bool = false) -> SyncBanner {
        let message = UserFacingError.sync(error)
        if let sheetError = error as? SheetAPIError {
            switch sheetError {
            case .network, .requestNotSent:
                return SyncBanner(kind: .offline, message: refreshing ? UserFacingError.refreshOffline : message)
            case .busy:
                return SyncBanner(kind: .parked, message: message)
            case .badSecret:
                return SyncBanner(kind: .authentication, message: message)
            default:
                break
            }
        }
        return SyncBanner(kind: .error, message: message)
    }

    private static func ascending(_ lhs: RunSnapshot, _ rhs: RunSnapshot) -> Bool {
        (lhs.scheduledAt ?? .distantFuture, lhs.rowIndex)
            < (rhs.scheduledAt ?? .distantFuture, rhs.rowIndex)
    }
}
