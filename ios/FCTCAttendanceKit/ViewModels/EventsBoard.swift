//
//  EventsBoard.swift
//  FCTCAttendanceKit
//
//  One pure builder for the Events tab (R22, R26): what's coming up, from the
//  season the app already caches. The app builds it once per data change (cached
//  runs, the outbox, the season's refresh, the Perth day), never per render:
//
//    effective runs ─┐                ┌─> This week   club runs, today to Sunday
//    lifetime priors ┼─> EventsBoard ─┼─> Specials    one row per date
//    birthdays ──────┤                ├─> Milestones  all-time = prior + season
//    now (Perth) ────┘                └─> Birthdays   today and the next 30 days
//
//  A run is a SPECIAL when it is not on one of its season's club weekdays, or its
//  label names an event. So "Half - Invasion Day" on a Monday is a special here,
//  although it still counts as a club day for streaks (`ClubDays`): Events asks
//  "is this day special?", streaks ask "did the club run that weekday?".
//
//  Specials sharing a date fold into one row, titled by the event:
//
//    Sun 13 Dec  Mara - Xmas ─┐
//    Sun 13 Dec  Half - Xmas ─┼─>  Sun 13 Dec  "Xmas"  Mara / Half / 10k
//    Sun 13 Dec  10k - Xmas  ─┘
//

import Foundation

/// A club run still to come this week.
public struct UpcomingRun: Hashable, Sendable, Identifiable {
    /// The run's cache key, stable across refreshes.
    public let id: String
    public let date: ClubDate
    /// The normalized run type ("Intervals", "N'hood Loop").
    public let title: String
    public let location: String
    /// The planned distance. Nil when the sheet has none.
    public let approxKm: Double?
}

/// Every special on one date, as one row.
public struct SpecialDay: Hashable, Sendable, Identifiable {
    public let date: ClubDate
    /// The day's event ("Xmas"), or the run type when no run names one ("Pub Run").
    public let title: String
    /// The day's distinct meeting places, in sheet order, joined with " / ".
    public let location: String
    /// Each run's short name in sheet order, repeats dropped ("Mara", "Half", "10k").
    public let options: [String]

    public var id: ClubDate { date }

    /// "Mara / Half / 10k". Nil when the only option repeats the title, as a lone
    /// Pub Run would ("Pub Run · Pub Run" says nothing twice).
    public var optionsLabel: String? {
        options == [title] ? nil : options.joined(separator: " / ")
    }
}

public struct EventsBoard: Hashable, Sendable {

    /// This week's club runs from today, oldest first. On a Sunday, the week ahead.
    public let thisWeek: [UpcomingRun]
    /// Every special from today on, one per date, oldest first.
    public let specials: [SpecialDay]
    /// The MilestoneBoard shortlist over all-time totals. Empty without priors.
    public let milestones: [MilestoneCandidate]
    /// Nil when the server sends no birthdays (an older script), which has its
    /// own empty text; empty when nobody's birthday is in the window.
    public let birthdays: [UpcomingBirthday]?

    /// The sheet's own race prefixes for the normalized race types, so an option
    /// reads as the organiser typed it ("Mara", not "Marathon"). The reverse of
    /// `RunLabel`'s race table.
    private static let shortRaceNames = ["Marathon": "Mara", "Half Marathon": "Half", "10K": "10k"]

    /// Build the board.
    ///
    /// - Parameters:
    ///   - runs: the active season's effective runs (`EffectiveRuns.runs`), in
    ///     sheet order. Planned rows with no attendance are expected: they are
    ///     the upcoming runs. Rows with no usable date are skipped.
    ///   - priors: lifetime runs before this season (KTD12), or nil when there
    ///     are no lifetime totals; the milestones are then empty.
    ///   - birthdays: the season's recorded birthdays, or nil for an older server.
    ///   - now: the current instant. Today is its day in Perth, the club's zone.
    public init(runs: [RunSnapshot], priors: LifetimePriors?, birthdays: [MemberBirthday]?, now: Date) {
        // Sheet order breaks date ties, so a day's options keep the sheet's order.
        let season = runs.compactMap { snapshot in ClubRun(snapshot).map { (snapshot: snapshot, run: $0) } }
            .enumerated()
            .sorted { ($0.element.run.date, $0.offset) < ($1.element.run.date, $1.offset) }
            .map(\.element)

        // Components of a real instant always form a real day; nil never happens.
        if let today = ClubDate(now, calendar: ClubDate.calendar) {
            let upcoming = season.filter { $0.run.date >= today }
            let weekEnd = Self.weekEnd(for: today)
            thisWeek = upcoming
                .filter { !Self.isSpecial($0.run) && $0.run.date <= weekEnd }
                .map { UpcomingRun(id: $0.run.id, date: $0.run.date, title: $0.run.label.type,
                                   location: $0.run.location, approxKm: $0.snapshot.approxKm) }
            specials = Self.specialDays(upcoming.map(\.run).filter(Self.isSpecial))
        } else {
            thisWeek = []
            specials = []
        }
        milestones = priors.map { MilestoneBoard.shortlist(priors: $0, season: season.map(\.run)) } ?? []
        self.birthdays = birthdays.map { BirthdayBoard.upcoming(from: $0, now: now) }
    }

    /// True when the run is a special: off its season's club weekdays, or an event.
    private static func isSpecial(_ run: ClubRun) -> Bool {
        run.label.event != nil || !ClubDays.weekdays(for: run.season).contains(run.weekday)
    }

    /// The last day "this week" covers: the coming Sunday. On a Sunday the club's
    /// week is over (Sundays are never club days), so it looks a week ahead.
    private static func weekEnd(for today: ClubDate) -> ClubDate {
        today.weekday == .sun ? today.adding(days: 7) : today.startOfWeek.adding(days: 6)
    }

    /// One row per date. Runs arrive in date, then sheet, order.
    private static func specialDays(_ runs: [ClubRun]) -> [SpecialDay] {
        var days: [ClubDate] = []
        var byDate: [ClubDate: [ClubRun]] = [:]
        for run in runs {
            if byDate[run.date] == nil { days.append(run.date) }
            byDate[run.date, default: []].append(run)
        }
        return days.compactMap { date in
            guard let runs = byDate[date], let first = runs.first else { return nil }
            return SpecialDay(
                date: date,
                title: runs.lazy.compactMap(\.label.event).first ?? first.label.type,
                location: distinct(runs.map(\.location).filter { !$0.isEmpty }).joined(separator: " / "),
                options: distinct(runs.map { shortRaceNames[$0.label.type] ?? $0.label.type })
            )
        }
    }

    /// The values in first-seen order.
    private static func distinct(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }
}

extension LifetimePriors {
    /// Priors from one server state, for its current roster only, so former
    /// members stay off the milestones. The state's own runs are the payload its
    /// totals were counted with (KTD12).
    public init(rosterOf state: SheetState) {
        let roster = Set(state.roster.map { ClubRun.memberName($0.name) })
        var scoped = state
        scoped.lifetimeTotals = state.lifetimeTotals.filter { roster.contains(ClubRun.memberName($0.name)) }
        self.init(scoped)
    }
}
