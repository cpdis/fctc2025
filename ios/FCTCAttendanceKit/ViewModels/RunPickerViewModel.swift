//
//  RunPickerViewModel.swift
//  FCTCAttendanceKit
//

import Foundation
import Observation

public enum RunSectionKind: String, CaseIterable, Sendable {
    case today = "Today"
    case thisWeek = "This Week"
    case later = "Later"
    case past = "Past"
}

public struct RunSection: Hashable, Sendable, Identifiable {
    public var id: String { title }
    public var kind: RunSectionKind
    /// The header text. Matches `kind.rawValue` except for the past scope's
    /// month grouping ("December", "November", ...).
    public var title: String
    public var runs: [RunSnapshot]

    public init(kind: RunSectionKind, title: String? = nil, runs: [RunSnapshot]) {
        self.kind = kind
        self.title = title ?? kind.rawValue
        self.runs = runs
    }
}

@MainActor
@Observable
public final class RunPickerViewModel {
    public private(set) var sections: [RunSection] = []
    public private(set) var selectedRun: RunSnapshot?
    public private(set) var isAddingRun = false
    public private(set) var errorMessage: String?

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
        now: Date = .now,
        calendar: Calendar = .current,
        groupPastByMonth: Bool = false
    ) {
        if groupPastByMonth {
            sections = Self.monthSections(runs: runs, calendar: calendar)
            selectedRun = Self.defaultRun(from: runs, now: now, calendar: calendar)
            return
        }
        let startOfToday = calendar.startOfDay(for: now)
        let week = calendar.dateInterval(of: .weekOfYear, for: now)
        var buckets: [RunSectionKind: [RunSnapshot]] = [:]

        for run in runs {
            guard let scheduledAt = run.scheduledAt else {
                buckets[.later, default: []].append(run)
                continue
            }
            let day = calendar.startOfDay(for: scheduledAt)
            let kind: RunSectionKind
            if calendar.isDate(day, inSameDayAs: startOfToday) {
                kind = .today
            } else if day < startOfToday {
                kind = .past
            } else if week?.contains(day) == true {
                kind = .thisWeek
            } else {
                kind = .later
            }
            buckets[kind, default: []].append(run)
        }

        sections = RunSectionKind.allCases.compactMap { kind in
            guard var values = buckets[kind], !values.isEmpty else { return nil }
            values.sort(by: kind == .past ? Self.newestFirst : RunSnapshot.chronological)
            return RunSection(kind: kind, runs: values)
        }
        selectedRun = Self.defaultRun(from: runs, now: now, calendar: calendar)
    }

    /// Past-scope month grouping (Colin's review): one section per month, newest
    /// month first, runs newest-first inside, dateless rows in a trailing bucket.
    nonisolated static func monthSections(
        runs: [RunSnapshot],
        calendar: Calendar
    ) -> [RunSection] {
        var order: [Date] = []
        var byMonth: [Date: [RunSnapshot]] = [:]
        var dateless: [RunSnapshot] = []
        for run in runs {
            guard let scheduledAt = run.scheduledAt,
                  let month = calendar.dateInterval(of: .month, for: scheduledAt)?.start
            else {
                dateless.append(run)
                continue
            }
            if byMonth[month] == nil { order.append(month) }
            byMonth[month, default: []].append(run)
        }

        var sections = order.sorted(by: >).map { month in
            RunSection(
                kind: .past,
                title: month.formatted(
                    Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).month(.wide)
                ),
                runs: byMonth[month]!.sorted(by: Self.newestFirst)
            )
        }
        if !dateless.isEmpty {
            sections.append(RunSection(kind: .past, title: "Undated", runs: dateless))
        }
        return sections
    }

    /// R7: use the latest due run that is still blank. Only fall back to a recorded
    /// run after every due row has attendance.
    public nonisolated static func defaultRun(
        from runs: [RunSnapshot],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> RunSnapshot? {
        let due = runs.filter { ($0.scheduledAt ?? .distantFuture) <= now }
        let pending = due.filter { !$0.hasRecordedAttendance }
        return (pending.isEmpty ? due : pending).max(by: RunSnapshot.chronological)
    }

    public func addRun(_ request: AddRunRequest) async throws {
        // Checked before the first await: a double tap on Add starts two tasks,
        // and only the first may add the run. The view ignores the cancellation.
        guard !isAddingRun else { throw CancellationError() }
        isAddingRun = true
        errorMessage = nil
        defer { isAddingRun = false }
        do {
            _ = try await engine.addRun(request)
        } catch {
            errorMessage = UserFacingError.sync(error)
            throw error
        }
    }

    private func observeEvents() {
        eventMonitor.start(engine: engine) { [weak self] event in
            // These screens show problems only; a success leaves the last
            // error in place, as before.
            guard let banner = SyncBanner(event: event), banner.isProblem else { return }
            self?.errorMessage = banner.message
        }
    }

    private nonisolated static func newestFirst(_ lhs: RunSnapshot, _ rhs: RunSnapshot) -> Bool {
        RunSnapshot.chronological(rhs, lhs)
    }
}
