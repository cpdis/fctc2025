//
//  EventsBoardTests.swift
//  FCTCAttendanceKitTests
//
//  U16, R22, R26 — the Events tab's builder over the 2026 season as the app
//  caches it: the recorded runs from the golden parity fixture plus the planned
//  rows still ahead in the 27 Sep 2026 snapshot
//  (`fixtures/attendance/2026-09-27/2026.csv`, rows with no distance and no
//  attendance), copied below so no Swift CSV parser is needed (KTD3).
//

import Foundation
import Testing

@testable import FCTCAttendanceKit

@Suite("Events board")
struct EventsBoardTests {

    // MARK: This week

    @Test("On Mon 28 Sep 2026 this week lists Mon 28 Sep, Wed 30 Sep and Fri 2 Oct")
    func thisWeek() throws {
        let board = EventsBoard(runs: try season2026(), priors: nil, birthdays: nil, now: perth("2026-09-28"))
        #expect(board.thisWeek.map(\.date.iso) == ["2026-09-28", "2026-09-30", "2026-10-02"])
        #expect(board.thisWeek.map(\.title) == ["Intervals", "Lakes Loop", "Soft Sand"])
        #expect(board.thisWeek.map(\.location) == ["Drift", "Filament", "Il Lido"])
        #expect(board.thisWeek.map(\.approxKm) == [10, 12.5, 7])
    }

    @Test("Saturday night UTC is Sunday in Perth, so the board shows the week ahead")
    func perthDay() throws {
        let runs = try season2026()
        // 17:00 UTC Sat 26 Sep is 01:00 Sun 27 Sep in Perth.
        let sundayInPerth = try Date("2026-09-26T17:00:00Z", strategy: .iso8601)
        #expect(EventsBoard(runs: runs, priors: nil, birthdays: nil, now: sundayInPerth).thisWeek.map(\.date.iso)
            == ["2026-09-28", "2026-09-30", "2026-10-02"])
        // Midday Saturday in Perth: the week's club days are done.
        #expect(EventsBoard(runs: runs, priors: nil, birthdays: nil, now: perth("2026-09-26")).thisWeek.isEmpty)
    }

    @Test("Today's run stays listed once recorded; earlier runs this week do not")
    func fromToday() throws {
        // Wed 23 Sep: Mon 21 is past; Wed 23 is today and already recorded.
        let board = EventsBoard(runs: try season2026(), priors: nil, birthdays: nil, now: perth("2026-09-23"))
        #expect(board.thisWeek.map(\.date.iso) == ["2026-09-23", "2026-09-25"])
    }

    // MARK: Specials

    @Test("The three Sun 13 Dec runs fold into one Xmas row: Mara / Half / 10k")
    func xmas() throws {
        let board = EventsBoard(runs: try season2026(), priors: nil, birthdays: nil, now: perth("2026-09-28"))
        // Fri 25 Dec is a club Friday with no event in its label, so it is a
        // club run, not a special: Xmas is the only special left.
        let xmas = try #require(board.specials.first)
        #expect(board.specials.count == 1)
        #expect(xmas.date.iso == "2026-12-13")
        #expect(xmas.title == "Xmas")
        #expect(xmas.location == "Alex 👑's")
        #expect(xmas.options == ["Mara", "Half", "10k"])
        #expect(xmas.optionsLabel == "Mara / Half / 10k")
    }

    @Test("A club-day holiday is a special, not a club run; a Sunday shows the week ahead")
    func clubDayHoliday() throws {
        // Sun 25 Jan 2026: the coming week holds Invasion Day, Mon 26 Jan.
        let board = EventsBoard(runs: try season2026(), priors: nil, birthdays: nil, now: perth("2026-01-25"))
        #expect(board.thisWeek.map(\.date.iso) == ["2026-01-28", "2026-01-30"])

        #expect(board.specials.map(\.date.iso) == ["2026-01-26", "2026-04-03", "2026-04-25", "2026-09-05", "2026-12-13"])
        #expect(board.specials.map(\.title) == ["Invasion Day", "Good Friday", "Anzac Day", "Pub Run", "Xmas"])
        #expect(board.specials.map(\.optionsLabel) == ["Half / 10k", "Pancake Run", "Mara / Half", nil, "Mara / Half / 10k"])
        #expect(board.specials.first?.location == "Filament")
    }

    @Test("A special on a club weekday stays off This week")
    func futureHoliday() throws {
        // A future Invasion Day on a Wednesday, inside this week's window.
        let holiday = snapshot(row: 900, "Wed, 30-Sep", meet: "Filament", run: "Half - Invasion Day", approxKm: 21.1)
        let runs = try season2026().filter { $0.date != "Wed, 30-Sep" } + [holiday]
        let board = EventsBoard(runs: runs, priors: nil, birthdays: nil, now: perth("2026-09-28"))
        #expect(board.thisWeek.map(\.date.iso) == ["2026-09-28", "2026-10-02"])
        #expect(board.specials.first?.date.iso == "2026-09-30")
        #expect(board.specials.first?.title == "Invasion Day")
        #expect(board.specials.first?.optionsLabel == "Half")
    }

    // MARK: Milestones

    @Test("Milestones use all-time totals and move with an unsynced outbox run")
    func milestonesWithOutbox() throws {
        let cached = try season2026()
        // Col: 148 lifetime with 68 this season, so 2 to 150. Kate B: 46 this
        // season and no earlier runs, so 4 to 50.
        let priors = LifetimePriors(
            lifetimeTotals: [MemberTotal(name: "Col", runs: 148), MemberTotal(name: "Kate B", runs: 46)],
            payload: cached.compactMap { ClubRun($0) }
        )
        let before = EventsBoard(runs: cached, priors: priors, birthdays: nil, now: perth("2026-09-28"))
        #expect(before.milestones.map(\.name) == ["Col", "Kate B"])
        #expect(before.milestones.map(\.runsNeeded) == [2, 4])

        // Tonight's run, recorded offline and still in the outbox.
        let monday = try #require(cached.first { $0.date == "Mon, 28-Sep" })
        let queued = PendingSubmissionSnapshot(
            id: UUID(), rowIndex: monday.rowIndex, expectedDate: monday.date, expectedRun: monday.run,
            attendees: ["Col", "Kate B"], plusOnes: nil, actualKm: 10.2, mode: .merge, status: .queued,
            createdAt: Date(timeIntervalSince1970: 0), endpointIdentity: endpoint
        )
        let effective = EffectiveRuns(cached: cached, submissions: [queued], endpoint: endpoint, refreshedAt: nil)
        #expect(effective.unsyncedCount == 1)
        let after = EventsBoard(runs: effective.runs, priors: priors, birthdays: nil, now: perth("2026-09-28"))
        #expect(after.milestones.map(\.name) == ["Col", "Kate B"])
        #expect(after.milestones.map(\.runs) == [149, 47])
        #expect(after.milestones.map(\.runsNeeded) == [1, 3])
        // Recording today's run does not take it off This week.
        #expect(after.thisWeek.first?.date.iso == "2026-09-28")
    }

    @Test("Roster priors leave former members off the milestones")
    func rosterPriors() {
        let state = SheetState(
            roster: [RosterEntry(name: "Col", colIndex: 6)],
            runs: [RunRecord(rowIndex: 5, date: "Mon, 21-Sep", meet: "Drift", run: "Intervals", attendees: ["Col"])],
            seasonYear: 2026,
            lifetimeTotals: [MemberTotal(name: "Col", runs: 148), MemberTotal(name: "Former", runs: 49)]
        )
        let priors = LifetimePriors(rosterOf: state)
        #expect(priors.runs == ["Col": 147])

        let board = EventsBoard(runs: [snapshot(row: 5, "Mon, 21-Sep", meet: "Drift", run: "Intervals", attendees: ["Col"])],
                                priors: priors, birthdays: nil, now: perth("2026-09-28"))
        #expect(board.milestones.map(\.name) == ["Col"])
        #expect(board.milestones.first?.runsNeeded == 2)
    }

    // MARK: Birthdays and empty states

    @Test("Birthdays come from BirthdayBoard's 30-day Perth window")
    func birthdays() throws {
        // The snapshot's BIRTHDAY row, plus one inside the window.
        let recorded = [
            MemberBirthday(name: "Aaron", month: 9, day: 1),
            MemberBirthday(name: "Alex 👑", month: 9, day: 17),
            MemberBirthday(name: "Joe", month: 11, day: 8),
            MemberBirthday(name: "Scott", month: 1, day: 20),
            MemberBirthday(name: "Kate B", month: 10, day: 1),
        ]
        let board = EventsBoard(runs: try season2026(), priors: nil, birthdays: recorded, now: perth("2026-09-28"))
        #expect(board.birthdays?.map(\.name) == ["Kate B"])
        #expect(board.birthdays?.first?.daysUntil == 3)
    }

    @Test("Empty inputs give every section its empty state; no birthdays feed stays nil")
    func emptyStates() throws {
        let empty = EventsBoard(runs: [], priors: nil, birthdays: [], now: perth("2026-09-28"))
        #expect(empty.thisWeek.isEmpty)
        #expect(empty.specials.isEmpty)
        #expect(empty.milestones.isEmpty)
        #expect(empty.birthdays == [])
        #expect(EventsBoard(runs: [], priors: nil, birthdays: nil, now: perth("2026-09-28")).birthdays == nil)

        // After the season's last run nothing is ahead. With no earlier runs,
        // all-time is the season, so the shortlist is the golden fixture's.
        let late = EventsBoard(runs: try season2026(), priors: LifetimePriors(lifetimeTotals: [], payload: []),
                               birthdays: [], now: perth("2026-12-31"))
        #expect(late.thisWeek.isEmpty)
        #expect(late.specials.isEmpty)
        #expect(late.milestones.map(\.name) == (try ParityFixture.load(2026).expected.milestones.map(\.name)))
    }
}

// MARK: - The 2026 season as cached

private let endpoint = "https://example.invalid/exec"

/// The snapshot's planned rows, "date|meet|run|approx km", in sheet order.
private let plannedRows = [
    "Mon, 28-Sep|Drift|Intervals|10.0", "Wed, 30-Sep|Filament|Lakes Loop|12.5", "Fri, 2-Oct|Il Lido|Soft Sand|7.0",
    "Mon, 5-Oct|Drift|Cruise|10.0", "Wed, 7-Oct|Filament|Intervals|8.0", "Fri, 9-Oct|Il Lido|Soft Sand|7.0",
    "Mon, 12-Oct|Drift|Intervals|10.0", "Wed, 14-Oct|Filament|Social|8.0", "Fri, 16-Oct|Il Lido|Soft Sand|7.0",
    "Mon, 19-Oct|Drift|Cruise|10.0", "Wed, 21-Oct|Filament|Intervals|8.0", "Fri, 23-Oct|MSBB|River Loop|12.5",
    "Mon, 26-Oct|Drift|Intervals|10.0", "Wed, 28-Oct|Filament|Lakes Loop|12.5", "Fri, 30-Oct|Il Lido|Soft Sand|7.0",
    "Mon, 2-Nov|Drift|Cruise|10.0", "Wed, 4-Nov|Filament|Intervals|8.0", "Fri, 6-Nov|Il Lido|Soft Sand|7.0",
    "Mon, 9-Nov|Drift|Intervals|10.0", "Wed, 11-Nov|Filament|Social|8.0", "Fri, 13-Nov|Il Lido|Soft Sand|7.0",
    "Mon, 16-Nov|Drift|Cruise|10.0", "Wed, 18-Nov|Filament|Intervals|8.0", "Fri, 20-Nov|MSBB|River Loop|12.5",
    "Mon, 23-Nov|Drift|Intervals|10.0", "Wed, 25-Nov|Filament|Lakes Loop|12.5", "Fri, 27-Nov|Il Lido|Soft Sand|7.0",
    "Mon, 30-Nov|Drift|Cruise|10.0", "Wed, 2-Dec|Filament|Intervals|8.0", "Fri, 4-Dec|Il Lido|Soft Sand|7.0",
    "Mon, 7-Dec|Drift|Intervals|10.0", "Wed, 9-Dec|Filament|Social|8.0", "Fri, 11-Dec|Il Lido|Soft Sand|7.0",
    "Sun, 13-Dec|Alex 👑's|Mara - Xmas|42.2", "Sun, 13-Dec|Alex 👑's|Half - Xmas|21.1",
    "Sun, 13-Dec|Alex 👑's|10k - Xmas|10.0", "Mon, 14-Dec|Drift|Cruise|10.0", "Wed, 16-Dec|Filament|Intervals|8.0",
    "Fri, 18-Dec|MSBB|River Loop|12.5", "Mon, 21-Dec|Drift|Intervals|10.0", "Wed, 23-Dec|Filament|Lakes Loop|12.5",
    "Fri, 25-Dec|Il Lido|Soft Sand|7.0", "Mon, 28-Dec|Drift|Cruise|10.0", "Wed, 30-Dec|Filament|Intervals|8.0",
]

/// The season's cached rows in sheet order: the golden recorded runs, then the
/// planned rows, as legacy snapshots (sheet date text plus the season year).
private func season2026() throws -> [RunSnapshot] {
    let recorded = try ParityFixture.load(2026).runs.map { golden in
        (sheetDate: try sheetDate(golden.date), meet: golden.meet, run: golden.run,
         approxKm: Double?.none, actualKm: Optional(golden.actualKm), attendees: golden.attendees, plusOnes: golden.plusOnes)
    }
    let planned = plannedRows.map { row in
        let cells = row.split(separator: "|").map(String.init)
        return (sheetDate: cells[0], meet: cells[1], run: cells[2],
                approxKm: Double(cells[3]), actualKm: Double?.none, attendees: [String](), plusOnes: 0)
    }
    return (recorded + planned).enumerated().map { index, row in
        snapshot(row: 10 + index, row.sheetDate, meet: row.meet, run: row.run, approxKm: row.approxKm,
                 actualKm: row.actualKm, attendees: row.attendees, plusOnes: row.plusOnes)
    }
}

private func snapshot(
    row: Int,
    _ date: String,
    meet: String,
    run: String,
    approxKm: Double? = nil,
    actualKm: Double? = nil,
    attendees: [String] = [],
    plusOnes: Int = 0
) -> RunSnapshot {
    RunSnapshot(
        rowIndex: row, date: date, scheduledAt: nil, meet: meet, run: run, approxKm: approxKm,
        actualKm: actualKm, attendees: attendees, plusOnes: plusOnes, endpointIdentity: endpoint, seasonYear: 2026
    )
}

/// "2026-09-28" as the sheet writes it: "Mon, 28-Sep".
private func sheetDate(_ iso: String) throws -> String {
    let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    let day = try #require(ClubDate(iso: iso))
    return "\(day.weekday.shortName), \(day.day)-\(months[day.month - 1])"
}

/// Midday on a Perth calendar day.
private func perth(_ iso: String) -> Date {
    let day = ClubDate(iso: iso)!
    return BirthdayBoard.calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12))!
}
