//
//  UITestDashboardFixture.swift
//  FCTCAttendance
//
//  `-ui-dashboard`: a season the Dashboard UI tests can pin numbers on, served
//  by the shared UI-test server (`UITestSharedGuestAPI`) only. Thirty club days
//  (Mon, Wed, Fri, Perth) end on the last club weekday before today, plus one
//  Saturday Pub Run special that neither adds to nor breaks a streak:
//
//    club day   0 ........ 13  14  15 ............ 28   29
//    Aaron      x ........ x   .   x ............. x    (blank)  -> streak 14
//    Col        all but days 3 and 18 ............ x             -> streak 10
//    Dan        two of every three ............... x             -> streak 2
//    Dan B      days 0 to 5 only                                  -> streak 0
//
//  Day 29 is a planned row nobody has recorded yet (row 130, the latest), so the
//  season has 30 runs; recording Aaron on it offline lifts that to 31 and his
//  streak to 15. Last season repeats the same weekdays 52 weeks earlier.
//
//  `-ui-dashboard-full` is the profiling size: a real season's shape, 118 club
//  days and 30 runners (the four above plus 26 whose attendance thins from
//  about 85% to 5%). Instruments runs use it; no test pins its numbers.
//

import FCTCAttendanceKit
import Foundation

enum UITestDashboardFixture {
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("-ui-dashboard") || isFull }
    /// The profiling size (`-ui-dashboard-full`).
    static var isFull: Bool { ProcessInfo.processInfo.arguments.contains("-ui-dashboard-full") }

    private static var clubDays: Int { isFull ? 118 : 30 }

    private static let pinned = ["Aaron", "Col", "Dan", "Dan B"]
    /// The profiling size's other runners, most regular first.
    private static let extras = [
        "Scott", "Alex", "Grant", "Cam", "Adam", "Darren", "Kate B", "Shane", "Alex B", "Toby", "Wes", "Anna", "Celeste",
        "Ming", "Joe", "Deano", "Liam", "Chartt", "Claire", "Rhys", "Jack", "René", "Rohan", "Tarquin", "Alex Kr", "Laura E",
    ]

    /// The season's roster: the pinned four, plus the extras at profiling size.
    static var roster: [String] { isFull ? pinned + extras : pinned }

    /// Lifetime runs sent with the season: Aaron is 3 short of 150.
    static var lifetimeTotals: [MemberTotal] {
        let base = [
            MemberTotal(name: "Aaron", runs: 147), MemberTotal(name: "Col", runs: 60),
            MemberTotal(name: "Dan", runs: 40), MemberTotal(name: "Dan B", runs: 12),
        ]
        return isFull ? base + extras.enumerated().map { MemberTotal(name: $1, runs: 180 - $0 * 7) } : base
    }

    /// This season's runs (season sheet 26) and last season's (25).
    static func runs(seasonYear: Int) -> (current: [RunRecord], previous: [RunRecord]) {
        let perth = BirthdayBoard.calendar
        let dates = clubDates(seasonYear: seasonYear)
        // The Pub Run: the Saturday after club day 20.
        let special = perth.nextDate(after: dates[20], matching: DateComponents(weekday: 7), matchingPolicy: .nextTime)!
        // Each row's club day, or nil for the special; in date order, like the sheet.
        var rows: [(date: Date, day: Int?)] = dates.enumerated().map { ($1, $0) }
        rows.append((special, nil))
        rows.sort { $0.date < $1.date }
        let current = rows.enumerated().map { index, row in
            record(row: 100 + index, date: row.date, attendees: row.day.map(attendees) ?? ["Aaron", "Col", "Dan B"],
                   special: row.day == nil, season: 26, seasonYear: seasonYear, id: "ffffffff-ffff-4fff-8fff-%012d", index: index)
        }
        let previous = dates.enumerated().compactMap { index, date -> RunRecord? in
            let lastYear = perth.date(byAdding: .day, value: -364, to: date)!
            guard perth.component(.year, from: lastYear) == seasonYear - 1 else { return nil }
            return record(row: 100 + index, date: lastYear, attendees: index.isMultiple(of: 2) ? ["Aaron", "Col", "Dan"] : ["Aaron", "Col"],
                          special: false, season: 25, seasonYear: seasonYear - 1, id: "abababab-abab-4bab-8bab-%012d", index: index)
        }
        return (current, previous)
    }

    /// Who made club day `day`. The last one waits to be recorded.
    private static func attendees(_ day: Int) -> [String] {
        guard day < clubDays - 1 else { return [] }
        var names: [String] = []
        if day != 14 { names.append("Aaron") }
        if day != 3 && day != 18 { names.append("Col") }
        if day % 3 != 2 { names.append("Dan") }
        if day < 6 { names.append("Dan B") }
        guard isFull else { return names }
        // A fixed scatter: runner i makes about (85 - 3i)% of club days.
        for (index, name) in extras.enumerated() where (day * 37 + index * 11) % 100 < 85 - index * 3 {
            names.append(name)
        }
        return names
    }

    /// The last `clubDays` Mondays, Wednesdays and Fridays before today, Perth.
    /// A sheet date has no year, so in early January, when that window would
    /// reach back into last year, it starts on the year's first club day instead.
    private static func clubDates(seasonYear: Int) -> [Date] {
        let perth = BirthdayBoard.calendar
        // Foundation weekday numbers: 2 Monday, 4 Wednesday, 6 Friday.
        let isClubDay = { (day: Date) in [2, 4, 6].contains(perth.component(.weekday, from: day)) }
        var dates: [Date] = []
        var day = perth.startOfDay(for: .now)
        while dates.count < clubDays {
            day = perth.date(byAdding: .day, value: -1, to: day)!
            if isClubDay(day) { dates.insert(day, at: 0) }
        }
        guard perth.component(.year, from: dates[0]) != seasonYear else { return dates }
        dates = []
        day = perth.date(from: DateComponents(year: seasonYear, month: 1, day: 1))!
        while dates.count < clubDays {
            if isClubDay(day) { dates.append(day) }
            day = perth.date(byAdding: .day, value: 1, to: day)!
        }
        return dates
    }

    /// One shared-endpoint row. Every fifth recorded run brings an unnamed guest.
    private static func record(
        row: Int, date: Date, attendees: [String], special: Bool,
        season: Int, seasonYear: Int, id: String, index: Int
    ) -> RunRecord {
        let perth = BirthdayBoard.calendar
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = perth
        formatter.timeZone = perth.timeZone
        formatter.dateFormat = "EEE, d-MMM"
        let plans: [Int: (meet: String, run: String, km: Double)] = [
            2: ("Drift", "Intervals", 10), 4: ("Filament", "Lakes Loop", 12.5), 6: ("Il Lido", "Soft Sand", 7),
        ]
        let plan = special ? (meet: "The Local", run: "Pub Run", km: 5.0) : plans[perth.component(.weekday, from: date)]!
        let guests = !attendees.isEmpty && index.isMultiple(of: 5) ? 1 : 0
        return RunRecord(
            rowIndex: row, date: formatter.string(from: date), meet: plan.meet, run: plan.run,
            approxKm: plan.km, actualKm: attendees.isEmpty ? nil : plan.km, attendees: attendees, plusOnes: guests,
            identity: RunIdentity(spreadsheetId: "ui-book", seasonSheetId: season, runId: String(format: id, index)),
            namedGuestIds: [], unnamedGuests: guests, seasonYear: seasonYear
        )
    }
}
