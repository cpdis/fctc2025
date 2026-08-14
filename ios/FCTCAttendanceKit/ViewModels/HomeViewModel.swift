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
    public private(set) var todayRun: RunSnapshot?
    public private(set) var lastSyncMessage: String?

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
        todayRun = earliestToday
    }

    public func refresh() async {
        do {
            _ = try await engine.refreshState()
            lastSyncMessage = nil
        } catch {
            lastSyncMessage = error.localizedDescription
        }
    }

    private func observeEvents() {
        eventMonitor.start(engine: engine) { [weak self] event in
            guard let self else { return }
            switch event {
            case .written:
                lastSyncMessage = "Attendance synced."
            case .conflict(_, _, let message, _), .parked(_, let message),
                 .failed(_, let message):
                lastSyncMessage = message
            case .queued, .rosterRefreshed:
                break
            }
        }
    }

    private static func ascending(_ lhs: RunSnapshot, _ rhs: RunSnapshot) -> Bool {
        (lhs.scheduledAt ?? .distantFuture, lhs.rowIndex)
            < (rhs.scheduledAt ?? .distantFuture, rhs.rowIndex)
    }
}
