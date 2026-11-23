//
//  BeenAWhile.swift
//  FCTCAttendanceKit
//
//  Grant's "been a while…" list (23 Nov 2026): members who ran at least once in
//  the last 12 weeks but not in the last 4, so organisers can nudge them. Weeks
//  are days back from today in Perth, and any run counts, specials included:
//
//    today Mon 23 Nov 2026
//    window from Mon 31 Aug (84 days) ───── recent from Mon 26 Oct (28 days) ── today
//      Jack   x Wed 2 Sep                                    -> listed, 11 weeks
//      Liam       x  x  x  x  x Fri 23 Oct                   -> listed, 4 weeks
//      Aaron      x  x  x  x  x  x  x  x  x  x  x  x Mon 26 Oct -> recent
//
//  iOS only (Colin's call): the web dashboard is public, and this names people.
//  Guests are +1 counts on a run, not people, so only members are listed.
//

import Foundation

/// Members whose latest run is in the last 12 weeks but before the last 4.
public struct BeenAWhile: Hashable, Sendable {

    /// A run this many days back or fewer is recent (28: four weeks).
    public static let recentDays = 28
    /// A run this many days back or fewer is in the window (84: twelve weeks).
    public static let windowDays = 84

    /// One member who has not run for a while.
    public struct Runner: Hashable, Sendable, Identifiable {
        public let name: String
        /// Their latest run.
        public let lastRun: ClubDate
        /// Days from each of their runs in the window to today, latest first.
        public let daysBack: [Int]

        public var id: String { name }
        /// Days from the latest run to today: 29 to 84.
        public var daysAway: Int { daysBack.first ?? 0 }
        /// Their runs in the window, the last run included.
        public var runs: Int { daysBack.count }
        /// Whole weeks since the last run: 4 to 12.
        public var weeksAway: Int { daysAway / 7 }

        /// The window's twelve weeks, oldest first: true where they ran. Week
        /// 0 (the last cell) is the 7 days up to today, so a run 28 days back
        /// is in the 4th cell from the end and 29 days back in the 5th.
        public var weeks: [Bool] {
            var weeks = Array(repeating: false, count: BeenAWhile.windowDays / 7)
            for days in daysBack {
                let back = min(weeks.count - 1, (max(days, 1) - 1) / 7)
                weeks[weeks.count - 1 - back] = true
            }
            return weeks
        }
    }

    /// The latest last run first, then name, so the order reads the same on
    /// every refresh.
    public let runners: [Runner]

    /// Build the list for `today`.
    ///
    /// - Parameters:
    ///   - runs: every run the app has, in any order and from any season, so in
    ///     January the window reaches back into December.
    ///   - roster: the live sheet's member columns. A name not on it has left
    ///     the club. Empty when unknown, which drops nobody.
    ///   - today: the day in Perth, the club's zone.
    public init(runs: [ClubRun], roster: Set<String>, today: ClubDate) {
        let windowFrom = today.adding(days: -Self.windowDays)
        let recentFrom = today.adding(days: -Self.recentDays)
        var dates: [String: [ClubDate]] = [:]
        for run in runs where run.date >= windowFrom {
            for name in run.attendees where roster.isEmpty || roster.contains(name) {
                dates[name, default: []].append(run.date)
            }
        }
        runners = dates.compactMap { name, dates in
            let latestFirst = dates.sorted(by: >)
            guard let last = latestFirst.first, last < recentFrom else { return nil }
            return Runner(name: name, lastRun: last, daysBack: latestFirst.map { $0.days(to: today) })
        }
        .sorted { $0.lastRun != $1.lastRun ? $0.lastRun > $1.lastRun : codeUnitPrecedes($0.name, $1.name) }
    }
}
