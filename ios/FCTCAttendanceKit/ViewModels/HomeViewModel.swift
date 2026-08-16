//
//  HomeViewModel.swift
//  FCTCAttendanceKit
//

import Foundation
import Observation

@MainActor
@Observable
public final class HomeViewModel {
    public private(set) var thisWeekCount = 0
    public private(set) var unsyncedCount = 0
    public private(set) var conflictCount = 0
    public private(set) var todayRun: RunSnapshot?
    public private(set) var syncBanner: SyncBanner?
    public private(set) var isInitialLoading = false
    public private(set) var initialLoadFailed = false

    public var lastSyncMessage: String? { syncBanner?.message }

    @ObservationIgnored private var engine: any SyncEngineClient
    @ObservationIgnored private let eventMonitor = SyncEventMonitor()

    public init(engine: any SyncEngineClient) {
        self.engine = engine
        observeEvents()
    }

    public func replaceEngine(_ engine: any SyncEngineClient) {
        self.engine = engine
        observeEvents()
    }

    public func update(
        runs: [RunSnapshot],
        submissions: [PendingSubmissionSnapshot],
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
        unsyncedCount = submissions.filter(\.isOutstanding).count
        conflictCount = submissions.filter { $0.status == .conflict }.count
        todayRun = earliestToday
    }

    public func refresh(hasCachedState: Bool = true) async {
        if !hasCachedState {
            isInitialLoading = true
            initialLoadFailed = false
        }
        defer {
            if isInitialLoading { isInitialLoading = false }
        }
        do {
            _ = try await engine.refreshState()
            initialLoadFailed = false
            if syncBanner != nil { syncBanner = nil }
        } catch {
            if !hasCachedState { initialLoadFailed = true }
            syncBanner = Self.banner(for: error)
        }
    }

    public func retry(hasCachedState: Bool = true) async {
        if initialLoadFailed {
            await refresh(hasCachedState: hasCachedState)
            return
        }
        if syncBanner != nil { syncBanner = nil }
        await engine.drain()
    }

    private func observeEvents() {
        eventMonitor.start(engine: engine) { [weak self] event in
            guard let self else { return }
            switch event {
            case .written:
                syncBanner = SyncBanner(kind: .success, message: "Attendance synced.")
            case .conflict:
                syncBanner = SyncBanner(kind: .conflict, message: UserFacingError.conflict)
            case .parked(_, let message):
                syncBanner = SyncBanner(
                    kind: message == UserFacingError.offline ? .offline : .parked,
                    message: message
                )
            case .authenticationRequired:
                syncBanner = SyncBanner(kind: .authentication, message: UserFacingError.authentication)
            case .failed(_, let message), .serviceFailed(let message):
                syncBanner = SyncBanner(kind: .error, message: message)
            case .queued, .rosterRefreshed:
                break
            }
        }
    }

    private static func banner(for error: any Error) -> SyncBanner {
        let message = UserFacingError.sync(error)
        if let sheetError = error as? SheetAPIError {
            switch sheetError {
            case .network:
                return SyncBanner(kind: .offline, message: message)
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
