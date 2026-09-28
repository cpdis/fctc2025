//
//  ClubDays.swift
//  FCTCAttendanceKit
//
//  Club-day and streak rules (R4, R5), the Swift mirror of `src/utils/clubDays.js`
//  and the club weekday table in `src/config/years.js` (KTD2).
//
//  A club day is a date on one of its season's official club weekdays with at
//  least one run. A member makes a club day by running any run that day, so the
//  Half and the 10k on Mon 26 Jan 2026 are one club day. A run on any other day
//  is a special (the Sat Pub Run, the Sun Xmas races, 2025's Invasion Day
//  Monday): it never adds to or breaks a streak.
//
//    club days    Mon 21  Wed 23  Fri 25  (Sat 26 Pub Run: not a club day)
//    Ann made       x       .       x     -> current 1 from Fri 25, best 1
//    Bob made       x       x       x     -> current 3 from Mon 21, best 3
//
//  A member's current streak is the number of consecutive most-recent club days
//  they made. Planned rows with no attendance are not runs, so a future Monday is
//  neither a club day nor a break.
//

import Foundation

/// One club day: a club weekday with at least one run on it.
public struct ClubDay: Hashable, Sendable, Identifiable {
    public let date: ClubDate
    /// That day's run ids, in the order the runs were given.
    public let runIDs: [String]
    /// Everyone who ran any run that day.
    public let attendees: Set<String>

    public var id: ClubDate { date }
    public var weekday: Weekday { date.weekday }
}

/// Club days made on one weekday, against the club days on that weekday.
public struct WeekdayTally: Hashable, Sendable, Identifiable {
    public let weekday: Weekday
    public let made: Int
    public let clubDays: Int

    public var id: Weekday { weekday }
}

/// One member's record over a view's club days (the web's `memberClubDays`).
public struct ClubDayRecord: Hashable, Sendable {
    /// Club days made.
    public let made: Int
    /// Every weekday that has club days, Mon..Sun, zeros included.
    public let byWeekday: [WeekdayTally]
    /// Consecutive most-recent club days made, and the first of them.
    public let current: Int
    public let currentFrom: ClubDate?
    /// The longest run of club days made. Of two equal bests the earlier wins.
    public let best: Int
    public let bestFrom: ClubDate?
    public let bestTo: ClubDate?
}

/// A view's club days, oldest first, and the streak rules over them.
public struct ClubDays: Hashable, Sendable {

    /// Seasons that did not run Monday, Wednesday and Friday. Mirrors
    /// `CLUB_WEEKDAYS` in `src/config/years.js`: 2025 had no official Monday run,
    /// so its Invasion Day Monday was a special.
    private static let weekdaysBySeason: [Int: [Weekday]] = [2025: [.wed, .fri]]

    /// Every other season's club weekdays.
    public static let defaultWeekdays: [Weekday] = [.mon, .wed, .fri]

    /// A season's official club weekdays, Mon..Sun order.
    public static func weekdays(for season: Int) -> [Weekday] {
        weekdaysBySeason[season] ?? defaultWeekdays
    }

    /// The club days, oldest first.
    public let days: [ClubDay]

    /// Weekdays that have club days, Mon..Sun, for the rule sentence and the
    /// weekday tracks (2025: Wed, Fri).
    public let weekdays: [Weekday]

    /// Ids of the runs that sit on a club day. Every other recorded run is a special.
    private let clubRunIDs: Set<String>

    /// Club days per weekday, for each member's made-of-all tallies.
    private let countsByWeekday: [Weekday: Int]

    /// Build club days from runs.
    ///
    /// - Parameters:
    ///   - runs: one season's runs, in sheet order. Unrecorded rows are skipped.
    ///   - weekdays: a season's club weekdays. Each run is judged by its own
    ///     season's set; tests pin it, callers use the season table.
    public init(runs: [ClubRun], weekdays: (Int) -> [Weekday] = ClubDays.weekdays(for:)) {
        var runIDs: [ClubDate: [String]] = [:]
        var attendees: [ClubDate: Set<String>] = [:]
        for run in runs where run.isRecorded && weekdays(run.season).contains(run.weekday) {
            runIDs[run.date, default: []].append(run.id)
            attendees[run.date, default: []].formUnion(run.attendees)
        }
        days = runIDs.keys.sorted().map { date in
            ClubDay(date: date, runIDs: runIDs[date] ?? [], attendees: attendees[date] ?? [])
        }
        clubRunIDs = Set(runIDs.values.joined())
        countsByWeekday = Dictionary(grouping: days, by: \.weekday).mapValues(\.count)
        self.weekdays = countsByWeekday.keys.sorted()
    }

    /// True when the run sits on a club day; false for a special or a non-run.
    public func isClubRun(_ run: ClubRun) -> Bool {
        clubRunIDs.contains(run.id)
    }

    /// One member's club-day record.
    public func record(for member: String) -> ClubDayRecord {
        let name = ClubRun.memberName(member)
        var madeByWeekday: [Weekday: Int] = [:]
        var made = 0
        var streak = 0
        var best = 0
        var bestEnd = -1

        for (index, day) in days.enumerated() {
            guard day.attendees.contains(name) else {
                streak = 0
                continue
            }
            made += 1
            madeByWeekday[day.weekday, default: 0] += 1
            streak += 1
            // Strictly longer only, so the first of two equal streaks wins.
            if streak > best {
                best = streak
                bestEnd = index
            }
        }

        // The streak still open after the last club day is the current one.
        return ClubDayRecord(
            made: made,
            byWeekday: weekdays.map {
                WeekdayTally(weekday: $0, made: madeByWeekday[$0] ?? 0, clubDays: countsByWeekday[$0] ?? 0)
            },
            current: streak,
            currentFrom: streak > 0 ? days[days.count - streak].date : nil,
            best: best,
            bestFrom: best > 0 ? days[bestEnd - best + 1].date : nil,
            bestTo: best > 0 ? days[bestEnd].date : nil
        )
    }
}
