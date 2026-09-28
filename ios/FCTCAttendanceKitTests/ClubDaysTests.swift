//
//  ClubDaysTests.swift
//  FCTCAttendanceKitTests
//
//  U12 — calendar days, the club weekday table and the club-day streak rules,
//  mirroring `src/utils/clubDays.test.js` (R4, R5; AE1–AE3, AE9).
//

import Foundation
import Testing

@testable import FCTCAttendanceKit

/// A recorded run on an ISO day; the id defaults to the day plus the first name.
func clubRun(
    _ iso: String,
    _ attendees: [String],
    run: String = "Intervals",
    id: String? = nil,
    plusOnes: Int = 0,
    actualKm: Double? = 8
) -> ClubRun {
    let date = ClubDate(iso: iso)!
    return ClubRun(
        id: id ?? "\(iso)-\(run)", date: date, season: date.year, run: run, meet: "Il Lido",
        actualKm: actualKm, attendees: attendees, plusOnes: plusOnes
    )
}

@Suite("Calendar days")
struct ClubDateTests {

    @Test("The sheet's date cell reads as a civil day with its weekday")
    func sheetDate() throws {
        let date = try #require(ClubDate(sheetDate: "Fri, 25-Sep", season: 2026))
        #expect(date.iso == "2026-09-25")
        #expect(date.weekday == .fri)
        #expect(ClubDate(sheetDate: " Mon, 5-Jan ", season: 2026)?.iso == "2026-01-05")
    }

    /// The web's `parseRunDate` and Apps Script's `parseSheetDate` rule: the day
    /// and month word anywhere in the cell, the month by its first three letters
    /// in any case, and the weekday from the calendar, never the typed text.
    @Test("Loose date cells read as the web and Apps Script read them", arguments: [
        ("Fri 25-Sep", "2026-09-25", Weekday.fri),
        ("Fri, 25-Sept", "2026-09-25", Weekday.fri),
        ("Fri, 25-sep", "2026-09-25", Weekday.fri),
        ("25-Sep", "2026-09-25", Weekday.fri),
        ("Sat 26 Sep", "2026-09-26", Weekday.sat),
        ("Sat, 26/Sep", "2026-09-26", Weekday.sat),
        ("Thurs, 1-Oct", "2026-10-01", Weekday.thu),
        ("Mon, 5 - January", "2026-01-05", Weekday.mon),
        // A mistyped weekday: 2 Oct 2026 is a Friday.
        ("Wed, 2-Oct", "2026-10-02", Weekday.fri),
    ])
    func looseDates(cell: String, iso: String, weekday: Weekday) throws {
        let date = try #require(ClubDate(sheetDate: cell, season: 2026))
        #expect(date.iso == iso)
        #expect(date.weekday == weekday)
    }

    @Test("Impossible days, unknown months and metadata rows are not dates", arguments: [
        "Wed, 31-Sep", "0-Oct", "3-Foo", "BIRTHDAY", "Notes", "",
    ])
    func notDates(cell: String) {
        #expect(ClubDate(sheetDate: cell, season: 2026) == nil)
    }

    @Test("A sheet day starts at midnight in the calendar it is placed in")
    func startOfDay() throws {
        var perth = Calendar(identifier: .gregorian)
        perth.timeZone = try #require(TimeZone(identifier: "Australia/Perth"))
        let day = try #require(ClubDate(sheetDate: "Sat 4-Oct", season: 2026))
        let start = try #require(day.startOfDay(in: perth))
        #expect(perth.dateComponents([.year, .month, .day, .hour, .minute], from: start)
            == DateComponents(year: 2026, month: 10, day: 4, hour: 0, minute: 0))
        #expect(ClubDate(start, calendar: perth) == day)
        #expect(ClubDate(sheetDate: "Sat 4-Oct", season: 0) == nil)
    }

    @Test("ISO days round-trip and order by date")
    func iso() throws {
        let day = try #require(ClubDate(iso: "2026-01-26"))
        #expect(day.iso == "2026-01-26")
        #expect(day.weekday == .mon)
        #expect(ClubDate(iso: "2026-02-30") == nil)
        #expect(ClubDate(iso: "2025-12-31")! < day)
        #expect(ClubDate(iso: "2026-09-25")!.description == "2026-09-25")
    }

    @Test("Day arithmetic crosses months, years and weeks")
    func arithmetic() throws {
        let friday = try #require(ClubDate(iso: "2026-09-25"))
        #expect(friday.startOfWeek.iso == "2026-09-21")
        #expect(friday.startOfWeek.adding(days: -28).iso == "2026-08-24")
        #expect(ClubDate(iso: "2025-12-31")!.adding(days: 2).iso == "2026-01-02")
        #expect(ClubDate(iso: "2026-09-21")!.startOfWeek.iso == "2026-09-21")
        #expect(ClubDate(iso: "2026-09-27")!.startOfWeek.iso == "2026-09-21")
        #expect(ClubDate(iso: "2026-01-01")!.dayOfYear == 0)
        #expect(friday.dayOfYear == 267)
    }

    @Test("Weekdays run Monday to Sunday and read the sheet's names")
    func weekdays() {
        #expect(Weekday.allCases.map(\.shortName) == ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])
        #expect(Weekday(shortName: "Wed") == .wed)
        #expect(Weekday(shortName: "wed") == nil)
        #expect(Weekday.mon < .sun)
    }

    @Test("A cached run takes its day from the sheet text and season")
    func snapshotAdapter() throws {
        let snapshot = RunSnapshot(
            rowIndex: 7, date: "Sat, 5-Sep", scheduledAt: nil, meet: "Some-day", run: "**Cruise",
            actualKm: 7.5, attendees: [" Aaron ", "Col"], plusOnes: 2, seasonYear: 2026
        )
        let run = try #require(ClubRun(snapshot))
        #expect(run.id == snapshot.id)
        #expect(run.date.iso == "2026-09-05")
        #expect(run.weekday == .sat)
        #expect(run.season == 2026)
        #expect(run.label.type == "Cruise")
        #expect(run.location == "Someday")
        #expect(run.attendees == ["Aaron", "Col"])
        #expect(run.memberKm == 15)
        #expect(run.headcount == 4)
    }

    @Test("Without a season year the day is scheduledAt read in the device zone")
    func snapshotFallback() throws {
        // Midnight 25 Sep in UTC+14 is still 24 Sep in Perth. Reading it back in
        // the zone that parsed it keeps the sheet's day.
        var device = Calendar(identifier: .gregorian)
        device.timeZone = try #require(TimeZone(identifier: "Pacific/Kiritimati"))
        let midnight = try #require(device.date(from: DateComponents(year: 2026, month: 9, day: 25)))
        let snapshot = RunSnapshot(
            rowIndex: 3, date: "Run 3", scheduledAt: midnight, meet: "Drift", run: "River Loop",
            attendees: ["Aaron"]
        )
        let run = try #require(ClubRun(snapshot, deviceCalendar: device))
        #expect(run.date.iso == "2026-09-25")
        #expect(run.weekday == .fri)
        #expect(run.season == 2026)

        let undated = RunSnapshot(rowIndex: 4, date: "BIRTHDAY", scheduledAt: nil, meet: "", run: "")
        #expect(ClubRun(undated) == nil)
    }

    @Test("A server run adapts with its season")
    func recordAdapter() throws {
        let record = RunRecord(
            rowIndex: 12, date: "Wed, 31-Dec", meet: "Il Lido", run: "Soft Sand",
            actualKm: nil, attendees: ["Adam"]
        )
        let run = try #require(ClubRun(record, season: 2025))
        #expect(run.date.iso == "2025-12-31")
        #expect(run.id == "legacy:12")
        #expect(run.memberKm == 0)
        #expect(ClubRun(RunRecord(rowIndex: 2, date: "BIRTHDAY", meet: "", run: ""), season: 2025) == nil)
    }
}

@Suite("Club days")
struct ClubDaysTests {

    @Test("Club weekdays are season config: 2025 Wed and Fri, otherwise Mon, Wed and Fri")
    func weekdayTable() {
        #expect(ClubDays.weekdays(for: 2025) == [.wed, .fri])
        #expect(ClubDays.weekdays(for: 2026) == [.mon, .wed, .fri])
        #expect(ClubDays.weekdays(for: 2027) == ClubDays.defaultWeekdays)
    }

    @Test("Club days come out oldest first whatever order the runs arrive in")
    func ordering() {
        let days = ClubDays(runs: [
            clubRun("2026-09-25", ["Ann"]), clubRun("2026-09-21", ["Ann"]), clubRun("2026-09-23", ["Bob"]),
        ])
        #expect(days.days.map(\.date.iso) == ["2026-09-21", "2026-09-23", "2026-09-25"])
    }

    @Test("Same-date runs fold into one club day that anyone on either run made (AE2)")
    func sameDate() {
        let half = clubRun("2026-01-26", ["Ann"], run: "Half - Invasion Day")
        let tenK = clubRun("2026-01-26", ["Bob"], run: "10k - Invasion Day")
        let days = ClubDays(runs: [half, tenK])
        #expect(days.days.count == 1)
        #expect(days.days[0].runIDs == [half.id, tenK.id])
        #expect(days.days[0].attendees == ["Ann", "Bob"])
        #expect(days.record(for: "Bob").current == 1)
        #expect(days.isClubRun(tenK))
    }

    @Test("Runs off the given weekdays are specials")
    func pinnedWeekdays() {
        let saturday = clubRun("2026-09-26", ["Ann"], run: "Pub Run")
        let runs = [clubRun("2026-09-21", ["Ann"]), clubRun("2026-09-23", ["Ann"]), saturday]
        let wednesdays = ClubDays(runs: runs, weekdays: { _ in [.wed] })
        #expect(wednesdays.days.map(\.date.iso) == ["2026-09-23"])
        #expect(wednesdays.weekdays == [.wed])
        #expect(!ClubDays(runs: runs).isClubRun(saturday))
    }

    @Test("Each run is judged by its own season's weekdays")
    func perSeasonWeekdays() {
        // Invasion Day Monday 2025 is a special; Monday 2026 is a club day.
        let days = ClubDays(runs: [clubRun("2025-01-27", ["Ann"]), clubRun("2026-01-26", ["Ann"])])
        #expect(days.days.map(\.date.iso) == ["2026-01-26"])
    }

    @Test("No runs means no club days and an empty record")
    func empty() {
        let days = ClubDays(runs: [])
        #expect(days.days.isEmpty)
        #expect(days.weekdays.isEmpty)
        let record = days.record(for: "Ann")
        #expect(record == ClubDayRecord(
            made: 0, byWeekday: [], current: 0, currentFrom: nil, best: 0, bestFrom: nil, bestTo: nil
        ))
    }

    @Test("The current streak counts back from the latest club day")
    func current() {
        let days = ClubDays(runs: [
            clubRun("2026-09-21", ["Ann", "Bob"]),
            clubRun("2026-09-23", ["Bob"]),
            clubRun("2026-09-25", ["Ann", "Bob"]),
            clubRun("2026-09-26", ["Cat"], run: "Pub Run"),
        ])
        #expect(days.record(for: "Bob").current == 3)
        #expect(days.record(for: "Bob").currentFrom?.iso == "2026-09-21")
        #expect(days.record(for: "Ann").current == 1)
        #expect(days.record(for: "Ann").currentFrom?.iso == "2026-09-25")
        // Missing the latest club day means no current streak.
        #expect(days.record(for: "Cat").current == 0)
        #expect(days.record(for: "Cat").currentFrom == nil)
        // A name is matched trimmed.
        #expect(days.record(for: " Bob ").current == 3)
    }

    @Test("Of two equally long best streaks the earlier is kept")
    func earliestBest() {
        let days = ClubDays(runs: [
            clubRun("2026-09-07", ["Ann"]), clubRun("2026-09-09", ["Ann"]),
            clubRun("2026-09-11", ["Bob"]),
            clubRun("2026-09-14", ["Ann"]), clubRun("2026-09-16", ["Ann"]),
            clubRun("2026-09-18", ["Bob"]),
        ])
        let record = days.record(for: "Ann")
        #expect(record.best == 2)
        #expect(record.bestFrom?.iso == "2026-09-07")
        #expect(record.bestTo?.iso == "2026-09-09")
        #expect(record.current == 0)
    }

    @Test("Club days made per weekday come in weekday order, zeros included")
    func byWeekday() {
        let days = ClubDays(runs: [
            clubRun("2026-09-25", ["Ann"]), clubRun("2026-09-23", ["Bob"]),
            clubRun("2026-09-21", ["Ann"]), clubRun("2026-09-18", ["Ann"]),
        ])
        #expect(days.weekdays == [.mon, .wed, .fri])
        #expect(days.record(for: "Ann").byWeekday == [
            WeekdayTally(weekday: .mon, made: 1, clubDays: 1),
            WeekdayTally(weekday: .wed, made: 0, clubDays: 1),
            WeekdayTally(weekday: .fri, made: 2, clubDays: 2),
        ])
        #expect(days.record(for: "Ann").made == 3)
    }

    @Test("A blank past row and a future Monday are not club days and break nothing")
    func unrecordedRows() {
        let blankFriday = clubRun("2026-09-18", [])
        let futureMonday = clubRun("2026-09-28", [])
        let days = ClubDays(runs: [
            clubRun("2026-09-16", ["Ann"]), blankFriday,
            clubRun("2026-09-21", ["Ann"]), clubRun("2026-09-23", ["Ann"]), clubRun("2026-09-25", ["Ann"]),
            futureMonday,
        ])
        #expect(!days.days.contains { $0.date.iso == "2026-09-18" || $0.date.iso == "2026-09-28" })
        #expect(days.record(for: "Ann").current == 4)
        #expect(!days.isClubRun(futureMonday))
    }

    @Test("A day with only +1s is still a club day nobody on the roster made")
    func plusOnesOnly() {
        let days = ClubDays(runs: [clubRun("2026-09-21", ["Ann"]), clubRun("2026-09-23", [], plusOnes: 2)])
        #expect(days.days.count == 2)
        #expect(days.record(for: "Ann").current == 0)
    }
}

@Suite("Club days — 27 Sep 2026 snapshot")
struct ClubDaysSnapshotTests {

    @Test("Aaron's 2026 current streak is 14 from Wed 26 Aug (AE1)")
    func aaron() throws {
        let days = ClubDays(runs: try ParityFixture.load(2026).clubRuns())
        let record = days.record(for: "Aaron")
        #expect(record.current == 14)
        #expect(record.currentFrom?.iso == "2026-08-26")
        #expect(days.days.last?.date.iso == "2026-09-25")
    }

    @Test("The Sat 5 Sep Pub Run neither adds to nor breaks a streak (AE1)")
    func pubRun() throws {
        let runs = try ParityFixture.load(2026).clubRuns()
        let pubRun = try #require(runs.first { $0.id == "2026-09-05-pub-run" })
        #expect(pubRun.attendees.contains("Aaron"))
        let days = ClubDays(runs: runs)
        #expect(!days.days.contains { $0.date.iso == "2026-09-05" })
        #expect(!days.isClubRun(pubRun))

        let withoutAaron = runs.map { run in
            run.id != pubRun.id ? run : ClubRun(
                id: run.id, date: run.date, season: run.season, run: run.run, meet: run.meet,
                actualKm: run.actualKm, attendees: run.attendees.filter { $0 != "Aaron" }, plusOnes: run.plusOnes
            )
        }
        let record = ClubDays(runs: withoutAaron).record(for: "Aaron")
        #expect(record.current == 14)
        #expect(record.currentFrom?.iso == "2026-08-26")
    }

    @Test("A member who ran only the Mon 26 Jan 2026 10k made that club day (AE2)")
    func tenK() throws {
        let runs = try ParityFixture.load(2026).clubRuns()
        let day = try #require(ClubDays(runs: runs).days.first { $0.date.iso == "2026-01-26" })
        let dayRuns = day.runIDs.compactMap { id in runs.first { $0.id == id } }
        #expect(dayRuns.map(\.label.type) == ["Half Marathon", "10K"])
        #expect(!dayRuns[0].attendees.contains("Alex B"))
        #expect(dayRuns[1].attendees.contains("Alex B"))
        #expect(day.attendees.contains("Alex B"))
    }

    @Test("Skipping the Sun 13 Dec Xmas specials leaves a streak unchanged (AE3)")
    func xmas() throws {
        let xmas = ["Mara - Xmas", "Half - Xmas", "10k - Xmas"].map {
            clubRun("2026-12-13", ["Alex 👑"], run: $0)
        }
        let days = ClubDays(runs: try ParityFixture.load(2026).clubRuns() + xmas)
        #expect(!days.days.contains { $0.date.iso == "2026-12-13" })
        #expect(days.record(for: "Aaron").current == 14)
        #expect(days.record(for: "Aaron").currentFrom?.iso == "2026-08-26")
    }

    @Test("2025 has 104 club days and the Invasion Day Monday runs are specials (AE9)")
    func season2025() throws {
        let runs = try ParityFixture.load(2025).clubRuns()
        let days = ClubDays(runs: runs)
        #expect(days.days.count == 104)
        #expect(!days.days.contains { $0.weekday == .mon })
        #expect(runs.filter { $0.date.iso == "2025-01-27" }.count == 2)
        #expect(!days.days.contains { $0.date.iso == "2025-01-27" })
    }

    @Test("Scott's 2025 best is 54 (3 Jan to 9 Jul) and he ends the season on 49 (AE9)")
    func scott() throws {
        let record = ClubDays(runs: try ParityFixture.load(2025).clubRuns()).record(for: "Scott")
        #expect(record.best == 54)
        #expect(record.bestFrom?.iso == "2025-01-03")
        #expect(record.bestTo?.iso == "2025-07-09")
        #expect(record.current == 49)
    }

    @Test("The blank Fri 8 May 2026 row is not a club day")
    func blankMay() throws {
        let days = ClubDays(runs: try ParityFixture.load(2026).clubRuns())
        #expect(!days.days.contains { $0.date.iso == "2026-05-08" })
    }
}
