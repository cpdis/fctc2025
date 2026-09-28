//
//  DashboardModel.swift
//  FCTCAttendanceKit
//
//  One pure builder for every Dashboard card and the runner screen (KTD10, R23,
//  R25). The app builds it once per data change (cached runs, pending submissions,
//  season), never per render, and every card reads its slice:
//
//    effective runs  ─┐
//    last season     ─┼─> DashboardModel ─> headline, On a roll, Wall (recent +
//    lifetime priors ─┘                      full), recent runs, Vs last year,
//                                            leaderboard, milestones, runners
//
//  The rules match the web's `src/utils/dashboardMetrics.js` builders: club days
//  and streaks come from `ClubDays`, member-km is actual km x attending members
//  (+1s excluded), and a same-date comparison sets the season against the
//  previous one up to the month and day of the latest run. The card value types
//  live in `DashboardValues.swift`.
//

import Foundation

public struct DashboardModel: Hashable, Sendable {

    /// How many runners each On a roll list shows (the approved mockup).
    public static let currentPlaces = 5
    public static let bestPlaces = 3

    /// The Wall card's window: the latest run's week and the four before it.
    public static let recentWeeks = 5

    /// Runs behind the headline sparkline and the Every run card.
    public static let recentRunCount = 24

    public let season: Int
    /// Every run of the season (rows with an attendee or +1), oldest first; runs
    /// sharing a date keep the order they were given (sheet order).
    public let runs: [DashboardRun]
    public let clubDays: ClubDays
    public let headline: Headline
    public let onARoll: OnARoll
    /// Every active runner against every run of the season.
    public let wall: Wall
    /// The same rows against the last `recentWeeks` weeks of runs.
    public let recentWall: Wall
    /// Nil when there is no previous season to compare with.
    public let progress: SeasonProgress?
    public let leaderboard: Leaderboard
    /// The MilestoneBoard shortlist over all-time totals. Empty without priors.
    public let milestones: [MilestoneCandidate]
    /// Runner screens by member name, for everyone with a run this season.
    public let runners: [String: RunnerDetail]

    /// The latest runs, oldest first, for the headline sparkline and Every run.
    public var recentRuns: ArraySlice<DashboardRun> {
        runs.suffix(Self.recentRunCount)
    }

    /// Build every card.
    ///
    /// - Parameters:
    ///   - season: the season year the runs belong to.
    ///   - runs: the season's effective runs in sheet order. Planned and blank
    ///     rows may be included; they are not runs and are dropped.
    ///   - previous: last season's runs, or nil to hide the comparisons.
    ///   - priors: lifetime runs before this season (KTD12), or nil when the
    ///     server sent no lifetime totals; all-time numbers are then absent.
    public init(season: Int, runs: [ClubRun], previous: [ClubRun]? = nil, priors: LifetimePriors? = nil) {
        let ordered = Self.chronological(runs)
        let clubDays = ClubDays(runs: ordered)
        let entries = ordered.map { DashboardRun(run: $0, isSpecial: !clubDays.isClubRun($0)) }
        let standings = Self.standings(ordered).map { Standing(entry: $0, record: clubDays.record(for: $0.name)) }

        self.season = season
        self.runs = entries
        self.clubDays = clubDays

        // The previous season lined up against this one (web: lineUpPrevious).
        let previousRuns = Self.chronological(previous ?? [])
        let lineUp = ordered.last.flatMap { latest in
            previousRuns.first.map { first in
                (year: first.season, sameDate: previousRuns.filter { $0.date.isOnOrBefore(monthDayOf: latest.date) })
            }
        }

        headline = Self.headline(ordered, runners: standings.count, lineUp: lineUp)
        onARoll = Self.onARoll(standings, clubDays: clubDays)
        wall = Self.wall(entries, standings: standings)
        recentWall = Self.wall(Self.latestWeeks(of: entries), standings: standings)
        progress = lineUp.map { lineUp in
            SeasonProgress(
                current: .init(year: season, points: Self.cumulativeMemberKm(ordered)),
                previous: .init(year: lineUp.year, points: Self.cumulativeMemberKm(previousRuns)),
                previousAtLatest: Self.memberKm(lineUp.sameDate)
            )
        }
        let byRuns = standings.map(\.entry)
        leaderboard = Leaderboard(
            byRuns: byRuns,
            byKm: byRuns.filter { $0.memberKm > 0 }.sorted {
                $0.memberKm != $1.memberKm ? $0.memberKm > $1.memberKm : codeUnitPrecedes($0.name, $1.name)
            }
        )
        milestones = priors.map { MilestoneBoard.shortlist(priors: $0, season: ordered) } ?? []
        runners = Dictionary(uniqueKeysWithValues: standings.map { standing in
            (standing.entry.name, Self.runner(standing, among: byRuns, clubDays: clubDays, priors: priors))
        })
    }

    /// A runner's season totals with their club-day record, built once and
    /// shared by On a roll, both Walls and the runner screens.
    private struct Standing {
        let entry: LeaderboardEntry
        let record: ClubDayRecord
    }

    // MARK: - Builders

    /// Recorded runs by date; same-date runs keep the order they were given.
    private static func chronological(_ runs: [ClubRun]) -> [ClubRun] {
        runs.enumerated()
            .filter { $0.element.isRecorded }
            .sorted { ($0.element.date, $0.offset) < ($1.element.date, $1.offset) }
            .map(\.element)
    }

    private static func memberKm(_ runs: [ClubRun]) -> Double {
        runs.reduce(0) { $0 + $1.memberKm }
    }

    /// Each runner's season runs and member-km: most runs first, then name.
    private static func standings(_ runs: [ClubRun]) -> [LeaderboardEntry] {
        var totals: [String: (runs: Int, km: Double)] = [:]
        for run in runs {
            for name in run.attendees {
                totals[name, default: (0, 0)].runs += 1
                totals[name, default: (0, 0)].km += run.actualKm ?? 0
            }
        }
        return totals
            .map { LeaderboardEntry(name: $0.key, runs: $0.value.runs, memberKm: $0.value.km) }
            .sorted(by: byRuns)
    }

    /// Most runs first, then plain name order, so ties read the same on every refresh.
    private static func byRuns(_ lhs: LeaderboardEntry, _ rhs: LeaderboardEntry) -> Bool {
        lhs.runs != rhs.runs ? lhs.runs > rhs.runs : codeUnitPrecedes(lhs.name, rhs.name)
    }

    private static func headline(
        _ runs: [ClubRun],
        runners: Int,
        lineUp: (year: Int, sameDate: [ClubRun])?
    ) -> Headline {
        let km = memberKm(runs)
        let attendances = runs.reduce(0) { $0 + $1.attendees.count }
        return Headline(
            runs: runs.count,
            memberKm: km,
            runners: runners,
            perRun: runs.isEmpty ? 0 : Double(attendances) / Double(runs.count),
            vsPrevious: lineUp.map { lineUp in
                let pastKm = memberKm(lineUp.sameDate)
                return SameDateComparison(
                    year: lineUp.year,
                    runs: lineUp.sameDate.count,
                    memberKm: pastKm,
                    runsDelta: runs.count - lineUp.sameDate.count,
                    memberKmDelta: km - pastKm
                )
            }
        )
    }

    /// Top current streaks and season bests, longest first, then more runs, then name.
    private static func onARoll(_ standings: [Standing], clubDays: ClubDays) -> OnARoll {
        let lastClubDay = clubDays.days.last?.date
        // A zero streak has no dates, so the guards also drop it.
        let current = standings.compactMap { standing -> StreakLine? in
            guard let from = standing.record.currentFrom, let to = lastClubDay else { return nil }
            return StreakLine(name: standing.entry.name, length: standing.record.current, from: from, to: to)
        }
        let bests = standings.compactMap { standing -> StreakLine? in
            guard let from = standing.record.bestFrom, let to = standing.record.bestTo else { return nil }
            return StreakLine(name: standing.entry.name, length: standing.record.best, from: from, to: to)
        }
        return OnARoll(
            current: longestFirst(current, places: currentPlaces),
            bests: longestFirst(bests, places: bestPlaces),
            weekdays: clubDays.weekdays
        )
    }

    /// The longest `places` streaks. The lines arrive in standings order (more
    /// runs, then name), which breaks a tie in length.
    private static func longestFirst(_ lines: [StreakLine], places: Int) -> [StreakLine] {
        Array(
            lines.enumerated()
                .sorted { ($1.element.length, $0.offset) < ($0.element.length, $1.offset) }
                .map(\.element)
                .prefix(places)
        )
    }

    /// One row per runner (standings order), one cell per column.
    ///
    ///   Aaron, current streak 14 from Wed 26 Aug 2026
    ///   ... Mon 24 Aug  Wed 26 Aug  ...  Sat 5 Sep (Pub Run)  ...  Fri 25 Sep
    ///        ran          streak           ran (special column)      streak
    private static func wall(_ columns: [DashboardRun], standings: [Standing]) -> Wall {
        let rows = standings.map { standing in
            let name = standing.entry.name
            let cells = columns.map { column -> WallMark in
                guard column.run.attendees.contains(name) else { return .missed }
                // Every club day from currentFrom on is one the member made, so each
                // club-day run they ran from then on belongs to the current streak.
                if !column.isSpecial, let from = standing.record.currentFrom, column.run.date >= from {
                    return .streak
                }
                return .ran
            }
            return WallRow(name: name, runs: standing.entry.runs, current: standing.record.current, cells: cells)
        }
        return Wall(columns: columns, rows: rows)
    }

    /// Runs from the Monday `recentWeeks - 1` weeks before the latest run's week.
    private static func latestWeeks(of runs: [DashboardRun]) -> [DashboardRun] {
        guard let latest = runs.last?.run.date else { return [] }
        let start = latest.startOfWeek.adding(days: -7 * (recentWeeks - 1))
        return runs.filter { $0.run.date >= start }
    }

    /// Running member-km, one point per run date (same-date runs fold into one).
    private static func cumulativeMemberKm(_ runs: [ClubRun]) -> [ProgressPoint] {
        var points: [ProgressPoint] = []
        var total = 0.0
        for run in runs {
            total += run.memberKm
            let point = ProgressPoint(date: run.date, memberKm: total)
            if points.last?.date == run.date {
                points[points.count - 1] = point
            } else {
                points.append(point)
            }
        }
        return points
    }

    private static func runner(
        _ standing: Standing,
        among entries: [LeaderboardEntry],
        clubDays: ClubDays,
        priors: LifetimePriors?
    ) -> RunnerDetail {
        let entry = standing.entry
        let streakFrom = standing.record.currentFrom
        return RunnerDetail(
            name: entry.name,
            runs: entry.runs,
            memberKm: entry.memberKm,
            // Competition ranking: equal run counts share a place.
            rank: 1 + entries.count(where: { $0.runs > entry.runs }),
            record: standing.record,
            calendar: clubDays.days.map { day in
                let made = day.attendees.contains(entry.name)
                let inStreak = made && streakFrom.map { day.date >= $0 } == true
                return RunnerDay(date: day.date, made: made, inStreak: inStreak)
            },
            allTime: priors?.allTime(for: entry.name, seasonRuns: entry.runs)
        )
    }
}
