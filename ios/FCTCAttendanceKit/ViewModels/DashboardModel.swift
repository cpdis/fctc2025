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
//  All time is the same builders over every season's runs (the web's
//  `combineYearData`): club days keep each season's weekdays, so a streak to
//  Wed 31 Dec 2025 runs on into Fri 2 Jan 2026; nothing compares; and a Wall
//  cell on a season whose sheet had no column for the runner is `notOnRoster`.
//

import Foundation

/// What the Dashboard shows: one season, or every listed season together.
public enum DashboardPeriod: Hashable, Sendable {
    case season(Int)
    case allTime

    /// The season menu's label: "2026" or "All time".
    public var label: String {
        switch self {
        case .season(let year): String(year)
        case .allTime: "All time"
        }
    }
}

public struct DashboardModel: Hashable, Sendable {

    /// How many runners each On a roll list shows (the approved mockup).
    public static let currentPlaces = 5
    public static let bestPlaces = 3

    /// The Wall card's window: the latest run's week and the four before it.
    public static let recentWeeks = 5

    /// Runs behind the headline sparkline and the Every run card.
    public static let recentRunCount = 24

    public let period: DashboardPeriod
    /// Every run of the view (rows with an attendee or +1), oldest first; runs
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

    /// The season shown; nil for All time.
    public var season: Int? {
        if case .season(let year) = period { year } else { nil }
    }

    /// Build every card for one season.
    ///
    /// - Parameters:
    ///   - season: the season year the runs belong to.
    ///   - runs: the season's effective runs in sheet order. Planned and blank
    ///     rows may be included; they are not runs and are dropped.
    ///   - previous: last season's runs, or nil to hide the comparisons. Runs
    ///     whose season is not before `season` are ignored.
    ///   - priors: lifetime runs before this season (KTD12), or nil when the
    ///     server sent no lifetime totals; all-time numbers are then absent.
    ///   - milestones: the shortlist to show, or nil to build it from `priors`
    ///     and `runs`. The store passes the live season's, so every view names
    ///     the same people (the web's rule).
    public init(
        season: Int,
        runs: [ClubRun],
        previous: [ClubRun]? = nil,
        priors: LifetimePriors? = nil,
        milestones: [MilestoneCandidate]? = nil
    ) {
        self.init(period: .season(season), runs: runs, previous: previous, priors: priors,
                  rosters: nil, milestones: milestones)
    }

    /// Build every card for All time: every season's runs together.
    ///
    /// - Parameters:
    ///   - runs: every season's effective runs; each keeps its own season.
    ///   - rosters: each season's sheet columns by season year, so a Wall cell
    ///     on a season the runner was not on reads `notOnRoster`. A season
    ///     missing here marks nobody.
    ///   - priors: lifetime runs before the earliest season shown.
    ///   - milestones: as for one season.
    public init(
        allTime runs: [ClubRun],
        rosters: [Int: Set<String>],
        priors: LifetimePriors? = nil,
        milestones: [MilestoneCandidate]? = nil
    ) {
        self.init(period: .allTime, runs: runs, previous: nil, priors: priors,
                  rosters: rosters, milestones: milestones)
    }

    private init(
        period: DashboardPeriod,
        runs: [ClubRun],
        previous: [ClubRun]?,
        priors: LifetimePriors?,
        rosters: [Int: Set<String>]?,
        milestones: [MilestoneCandidate]?
    ) {
        let ordered = Self.chronological(runs)
        let clubDays = ClubDays(runs: ordered)
        let entries = ordered.map { DashboardRun(run: $0, isSpecial: !clubDays.isClubRun($0)) }
        let standings = Self.standings(ordered).map { Standing(entry: $0, record: clubDays.record(for: $0.name)) }

        self.period = period
        self.runs = entries
        self.clubDays = clubDays

        // The previous season lined up against this one (web: lineUpPrevious).
        // Only an earlier season compares: runs of this season or a later one
        // are dropped, so a stale answer cannot pose as last year. All time
        // never compares.
        let season: Int? = if case .season(let year) = period { year } else { nil }
        let previousRuns = season.map { season in
            Self.chronological((previous ?? []).filter { $0.season < season })
        } ?? []
        let lineUp = ordered.last.flatMap { latest in
            previousRuns.first.map { first in
                (year: first.season, sameDate: previousRuns.filter { $0.date.isOnOrBefore(monthDayOf: latest.date) })
            }
        }

        headline = Self.headline(ordered, runners: standings.count, lineUp: lineUp)
        onARoll = Self.onARoll(standings, clubDays: clubDays)
        wall = Self.wall(entries, standings: standings, rosters: rosters)
        recentWall = Self.wall(Self.latestWeeks(of: entries), standings: standings, rosters: rosters)
        progress = lineUp.flatMap { lineUp in
            season.map { season in
                SeasonProgress(
                    current: .init(year: season, points: Self.cumulativeMemberKm(ordered)),
                    previous: .init(year: lineUp.year, points: Self.cumulativeMemberKm(previousRuns)),
                    previousAtLatest: Self.memberKm(lineUp.sameDate)
                )
            }
        }
        let byRuns = standings.map(\.entry)
        leaderboard = Leaderboard(
            byRuns: byRuns,
            byKm: byRuns.filter { $0.memberKm > 0 }.sorted {
                $0.memberKm != $1.memberKm ? $0.memberKm > $1.memberKm : codeUnitPrecedes($0.name, $1.name)
            }
        )
        self.milestones = milestones ?? priors.map { MilestoneBoard.shortlist(priors: $0, season: ordered) } ?? []
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
    private static func wall(_ columns: [DashboardRun], standings: [Standing], rosters: [Int: Set<String>]?) -> Wall {
        let rows = standings.map { standing in
            let name = standing.entry.name
            let cells = columns.map { column -> WallMark in
                guard column.run.attendees.contains(name) else {
                    // All time: no column for them on that season's sheet.
                    if let roster = rosters?[column.run.season], !roster.contains(name) { return .notOnRoster }
                    return .missed
                }
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
                return RunnerDay(date: day.date, season: day.season, made: made, inStreak: inStreak)
            },
            allTime: priors?.allTime(for: entry.name, seasonRuns: entry.runs)
        )
    }
}
