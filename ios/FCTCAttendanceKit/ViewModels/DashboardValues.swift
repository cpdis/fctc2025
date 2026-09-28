//
//  DashboardValues.swift
//  FCTCAttendanceKit
//
//  The values `DashboardModel` hands each Dashboard card and the runner screen,
//  plus the lifetime priors behind every all-time number (KTD12). Plain Sendable
//  data: no SwiftUI, no SwiftData, so every card can be pinned in a unit test.
//

import Foundation

// MARK: - All time

/// Each member's runs before the live season (KTD12).
///
/// The server's `lifetimeTotals` already include the season it was sent with.
/// Subtracting the member's runs in that SAME payload leaves the earlier
/// seasons, and adding the effective (outbox-applied) season count back gives an
/// all-time total that moves the moment attendance is recorded:
///
///   lifetime 177 - payload 89 = prior 88;   prior 88 + effective 90 = 178
public struct LifetimePriors: Hashable, Sendable {

    /// Runs before the live season by member name. Never negative.
    public let runs: [String: Int]

    /// - Parameters:
    ///   - lifetimeTotals: the server's lifetime runs per member. Filter them to
    ///     the roster first if former members should stay off the milestones.
    ///   - payload: the season runs delivered with those totals, before any
    ///     pending submission is applied.
    public init(lifetimeTotals: [MemberTotal], payload: [ClubRun]) {
        self.init(lifetimeTotals: lifetimeTotals, payloadAttendees: payload.map(\.attendees))
    }

    /// Priors from one server state: its lifetime totals and its own runs.
    public init(_ state: SheetState) {
        self.init(lifetimeTotals: state.lifetimeTotals, payloadAttendees: state.runs.map(\.attendees))
    }

    private init(lifetimeTotals: [MemberTotal], payloadAttendees: [[String]]) {
        var seasonRuns: [String: Int] = [:]
        for name in payloadAttendees.joined() {
            seasonRuns[ClubRun.memberName(name), default: 0] += 1
        }
        var runs: [String: Int] = [:]
        for total in lifetimeTotals {
            let name = ClubRun.memberName(total.name)
            runs[name] = max(0, total.runs - (seasonRuns[name] ?? 0))
        }
        self.runs = runs
    }

    /// All-time runs: the prior plus this season's effective count.
    public func allTime(for name: String, seasonRuns: Int) -> Int {
        (runs[ClubRun.memberName(name)] ?? 0) + seasonRuns
    }
}

// MARK: - Cards

/// The headline numbers. `perRun` is member attendances per run (+1s excluded).
public struct Headline: Hashable, Sendable {
    public let runs: Int
    /// Actual km x attending members, summed ("km together").
    public let memberKm: Double
    /// Members with at least one run.
    public let runners: Int
    public let perRun: Double
    /// Last season on the same date, or nil when there is none.
    public let vsPrevious: SameDateComparison?
}

/// The previous season up to the month and day of this season's latest run.
public struct SameDateComparison: Hashable, Sendable {
    public let year: Int
    public let runs: Int
    public let memberKm: Double
    /// This season minus last season: positive means ahead.
    public let runsDelta: Int
    public let memberKmDelta: Double
}

/// One streak for the On a roll card. For a current streak `to` is the latest
/// club day.
public struct StreakLine: Hashable, Sendable, Identifiable {
    public let name: String
    public let length: Int
    public let from: ClubDate
    public let to: ClubDate

    public var id: String { name }
}

/// The On a roll card (R10): top current streaks, top season bests, and the
/// weekdays the streaks count for the rule sentence (2025: Wed, Fri).
public struct OnARoll: Hashable, Sendable {
    public let current: [StreakLine]
    public let bests: [StreakLine]
    public let weekdays: [Weekday]
}

/// One run as the Wall, the charts and the run log show it.
public struct DashboardRun: Hashable, Sendable, Identifiable {
    public let run: ClubRun
    /// Off its season's club weekdays: a weekend or holiday run (R11).
    public let isSpecial: Bool

    public var id: String { run.id }
}

/// What a Wall cell shows for one runner and one run.
public enum WallMark: Hashable, Sendable {
    case missed
    /// Ran, outside the current streak (or on a special).
    case ran
    /// Ran a club-day run inside the runner's current streak.
    case streak
}

/// One Wall row. `cells` line up with `Wall.columns` by index.
public struct WallRow: Hashable, Sendable, Identifiable {
    public let name: String
    /// Season runs, the row order.
    public let runs: Int
    /// Current club-day streak.
    public let current: Int
    public let cells: [WallMark]

    public var id: String { name }
}

/// Runners (most runs first) against runs (oldest first).
public struct Wall: Hashable, Sendable {
    public let columns: [DashboardRun]
    public let rows: [WallRow]
}

/// Cumulative member-km at the end of one run date.
public struct ProgressPoint: Hashable, Sendable, Identifiable {
    public let date: ClubDate
    public let memberKm: Double

    public var id: ClubDate { date }
    /// Where the point sits on a Jan..Dec axis shared by both seasons.
    public var dayOfYear: Int { date.dayOfYear }
}

/// Vs last year (R14): both seasons' cumulative member-km, and last season's
/// total at this season's latest month and day (the far end of the gap label).
public struct SeasonProgress: Hashable, Sendable {
    public struct Series: Hashable, Sendable {
        public let year: Int
        public let points: [ProgressPoint]
    }

    public let current: Series
    public let previous: Series
    public let previousAtLatest: Double
}

/// One runner's season totals.
public struct LeaderboardEntry: Hashable, Sendable, Identifiable {
    public let name: String
    public let runs: Int
    public let memberKm: Double

    public var id: String { name }
}

/// The leaderboard card's two rankings. `byKm` leaves out runners with no km.
public struct Leaderboard: Hashable, Sendable {
    public let byRuns: [LeaderboardEntry]
    public let byKm: [LeaderboardEntry]
}

/// One club day on the runner screen's season calendar.
public struct RunnerDay: Hashable, Sendable, Identifiable {
    public let date: ClubDate
    public let made: Bool
    /// Made, and part of the current streak.
    public let inStreak: Bool

    public var id: ClubDate { date }
}

/// Everything the runner screen shows (R25).
public struct RunnerDetail: Hashable, Sendable, Identifiable {
    public let name: String
    public let runs: Int
    public let memberKm: Double
    /// Place on runs, 1 = most. Equal run counts share a place.
    public let rank: Int
    /// Current and best streaks, and club days made per weekday.
    public let record: ClubDayRecord
    /// Every club day of the season, oldest first.
    public let calendar: [RunnerDay]
    /// Prior seasons plus this one; nil when the server sent no lifetime totals.
    public let allTime: Int?

    public var id: String { name }

    /// The next landmark after the all-time total (MilestoneBoard's rule).
    public var nextMilestone: Int? {
        allTime.map(MilestoneBoard.nextMilestone(after:))
    }
}
