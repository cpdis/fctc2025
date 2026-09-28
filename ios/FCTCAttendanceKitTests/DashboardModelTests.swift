//
//  DashboardModelTests.swift
//  FCTCAttendanceKitTests
//
//  U12 — every Dashboard card and the runner screen from one `DashboardModel`,
//  over the 27 Sep 2026 golden runs (R23, R25; KTD10, KTD12).
//

import Foundation
import Testing

@testable import FCTCAttendanceKit

@Suite("Dashboard model")
struct DashboardModelTests {

    private func model2026(previous: Bool = false, priors: LifetimePriors? = nil) throws -> DashboardModel {
        DashboardModel(
            season: 2026,
            runs: try ParityFixture.load(2026).clubRuns(),
            previous: previous ? try ParityFixture.load(2025).clubRuns() : nil,
            priors: priors
        )
    }

    @Test("The headline counts runs, member-km, runners and members per run")
    func headline() throws {
        let headline = try model2026().headline
        #expect(headline.runs == 118)
        #expect(roundKm(headline.memberKm) == 9888.73)
        #expect(headline.runners == 30)
        #expect(headline.perRun == 965.0 / 118.0)
        #expect(headline.vsPrevious == nil)
    }

    @Test("Last season is compared on the same date (Fri 25 Sep)")
    func sameDate() throws {
        let model = try model2026(previous: true)
        let vs = try #require(model.headline.vsPrevious)
        #expect(vs.year == 2025)
        #expect(vs.runs == 80)
        #expect(vs.runsDelta == 38)
        #expect(roundKm(vs.memberKm) == 8262.56)
        #expect(roundKm(vs.memberKmDelta) == roundKm(model.headline.memberKm - vs.memberKm))
    }

    @Test("An empty previous season or an empty season compares nothing")
    func noComparison() throws {
        #expect(DashboardModel(season: 2026, runs: try ParityFixture.load(2026).clubRuns(), previous: [])
            .headline.vsPrevious == nil)
        let empty = DashboardModel(season: 2026, runs: [], previous: try ParityFixture.load(2025).clubRuns())
        #expect(empty.headline.vsPrevious == nil)
        #expect(empty.progress == nil)
    }

    @Test("On a roll lists the top current streaks and season bests")
    func onARoll() throws {
        let roll = try model2026().onARoll
        #expect(roll.current.map(\.name) == ["Aaron", "Cam", "Scott", "Kate B", "Alex B"])
        #expect(roll.current.map(\.length) == [14, 5, 2, 2, 1])
        #expect(roll.current[0].from.iso == "2026-08-26")
        #expect(roll.current[0].to.iso == "2026-09-25")
        // Scott, Grant, Col and Cam share a best of 5; more runs wins the place.
        #expect(roll.bests.map(\.name) == ["Aaron", "Alex 👑", "Scott"])
        #expect(roll.bests.map(\.length) == [14, 9, 5])
        #expect(roll.bests[1].from.iso == "2026-01-02")
        #expect(roll.bests[1].to.iso == "2026-01-21")
        #expect(roll.weekdays == [.mon, .wed, .fri])
        #expect(DashboardModel(season: 2025, runs: try ParityFixture.load(2025).clubRuns())
            .onARoll.weekdays == [.wed, .fri])
    }

    @Test("The Wall marks runs, streak runs and specials for every runner")
    func wall() throws {
        let wall = try model2026().wall
        #expect(wall.columns.count == 118)
        #expect(wall.rows.count == 30)
        #expect(wall.rows.prefix(3).map(\.name) == ["Aaron", "Scott", "Alex 👑"])
        #expect(wall.rows.allSatisfy { $0.cells.count == wall.columns.count })

        let aaron = try #require(wall.rows.first)
        #expect(aaron.current == 14)
        #expect(aaron.cells.filter { $0 == .streak }.count == 14)
        let pubRun = try #require(wall.columns.firstIndex { $0.id == "2026-09-05-pub-run" })
        #expect(wall.columns[pubRun].isSpecial)
        #expect(aaron.cells[pubRun] == .ran)
        #expect(aaron.cells.last == .streak)
        // 2026's specials are the Sat Anzac Day races and the Sat Pub Run; its
        // Invasion Day Monday is a club day.
        #expect(wall.columns.filter(\.isSpecial).map(\.run.date.iso) == ["2026-04-25", "2026-04-25", "2026-09-05"])
    }

    @Test("The recent Wall covers the latest run's week and the four before it")
    func recentWall() throws {
        let recent = try model2026().recentWall
        #expect(recent.columns.first?.run.date.iso == "2026-08-24")
        #expect(recent.columns.last?.run.date.iso == "2026-09-25")
        #expect(recent.columns.count == 16)
        #expect(recent.columns.filter { !$0.isSpecial }.count == 15)
        #expect(recent.rows.first?.name == "Aaron")
        #expect(recent.rows.first?.cells.filter { $0 == .streak }.count == 14)
    }

    @Test("Recent runs are the latest runs, oldest first, with headcounts")
    func recentRuns() throws {
        let model = try model2026()
        let recent = model.recentRuns
        #expect(recent.count == DashboardModel.recentRunCount)
        #expect(recent.last?.run.date.iso == "2026-09-25")
        #expect(recent.map(\.run.date) == recent.map(\.run.date).sorted())
        let pubRun = try #require(recent.first { $0.id == "2026-09-05-pub-run" })
        #expect(pubRun.run.headcount == 18)
        #expect(pubRun.isSpecial)
    }

    @Test("Vs last year runs cumulative member-km per run date")
    func progress() throws {
        #expect(try model2026().progress == nil)
        let model = try model2026(previous: true)
        let progress = try #require(model.progress)
        #expect(progress.current.year == 2026)
        #expect(progress.previous.year == 2025)
        #expect(roundKm(progress.current.points.last?.memberKm ?? 0) == roundKm(model.headline.memberKm))
        #expect(roundKm(progress.previousAtLatest) == 8262.56)
        // Two runs on Mon 26 Jan fold into one point; one point per run date.
        #expect(progress.current.points.count == 116)
        #expect(progress.current.points.filter { $0.date.iso == "2026-01-26" }.count == 1)
        #expect(progress.current.points.first?.dayOfYear == 1)
        let totals = progress.current.points.map(\.memberKm)
        #expect(totals == totals.sorted())
    }

    @Test("The leaderboard ranks runs and km")
    func leaderboard() throws {
        let leaderboard = try model2026().leaderboard
        #expect(leaderboard.byRuns.prefix(5).map(\.name) == ["Aaron", "Scott", "Alex 👑", "Grant", "Col"])
        #expect(leaderboard.byRuns.first?.runs == 89)
        #expect(leaderboard.byKm.prefix(3).map(\.name) == ["Aaron", "Scott", "Alex 👑"])
        #expect(roundKm(leaderboard.byKm.first?.memberKm ?? 0) == 926.88)
        let km = leaderboard.byKm.map(\.memberKm)
        #expect(km == km.sorted(by: >))
    }

    @Test("Lifetime priors: lifetime 177 with 89 in the payload is prior 88; one more run makes 178")
    func lifetimePriors() throws {
        let payload = try ParityFixture.load(2026).clubRuns()
        let priors = LifetimePriors(
            lifetimeTotals: [MemberTotal(name: "Aaron", runs: 177), MemberTotal(name: "Ghost", runs: 3)],
            payload: payload
        )
        #expect(priors.runs["Aaron"] == 88)
        // A total below the payload count never goes negative.
        #expect(priors.runs["Ghost"] == 3)
        #expect(LifetimePriors(lifetimeTotals: [MemberTotal(name: "Col", runs: 10)], payload: payload)
            .runs["Col"] == 0)

        // Recorded today, before any sync: Mon 28 Sep with Aaron.
        let effective = payload + [clubRun("2026-09-28", ["Aaron"], run: "Intervals")]
        let model = DashboardModel(season: 2026, runs: effective, priors: priors)
        let aaron = try #require(model.runners["Aaron"])
        #expect(aaron.runs == 90)
        #expect(aaron.allTime == 178)
        #expect(aaron.nextMilestone == 200)
        #expect(aaron.record.current == 15)
    }

    @Test("Priors from a server state use that state's own runs")
    func priorsFromState() {
        let state = SheetState(
            runs: [
                RunRecord(rowIndex: 5, date: "Mon, 21-Sep", meet: "Drift", run: "Intervals", attendees: ["Col", "Ann"]),
                RunRecord(rowIndex: 6, date: "Wed, 23-Sep", meet: "Drift", run: "Intervals", attendees: ["Col"]),
            ],
            seasonYear: 2026,
            lifetimeTotals: [MemberTotal(name: "Col", runs: 140), MemberTotal(name: "Ann", runs: 1)]
        )
        let priors = LifetimePriors(state)
        #expect(priors.runs == ["Col": 138, "Ann": 0])
        #expect(priors.allTime(for: "Col", seasonRuns: 3) == 141)
        #expect(priors.allTime(for: "Nobody", seasonRuns: 2) == 2)
    }

    @Test("Milestones use MilestoneBoard over prior + season totals")
    func milestones() throws {
        let payload = try ParityFixture.load(2026).clubRuns()
        // Col has 68 this season and 148 lifetime: 2 to 150. "Former" has no
        // season runs but 46 from earlier seasons, tied at 4 with Kate B's 46
        // season-only total (no lifetime row, so no prior).
        let priors = LifetimePriors(
            lifetimeTotals: [MemberTotal(name: "Col", runs: 148), MemberTotal(name: "Former", runs: 46)],
            payload: payload
        )
        let model = DashboardModel(season: 2026, runs: payload, priors: priors)
        #expect(model.milestones.map(\.name) == ["Col", "Former", "Kate B"])
        #expect(model.milestones.map(\.runsNeeded) == [2, 4, 4])
        #expect(model.milestones.first?.milestone == 150)
        #expect(try model2026().milestones.isEmpty)
    }

    @Test("The runner screen has runs, km, streaks, a club-day calendar and weekday tallies")
    func runner() throws {
        let aaron = try #require(try model2026().runners["Aaron"])
        #expect(aaron.runs == 89)
        #expect(roundKm(aaron.memberKm) == 926.88)
        #expect(aaron.rank == 1)
        #expect(aaron.record.current == 14)
        #expect(aaron.record.best == 14)
        #expect(aaron.calendar.count == 114)
        #expect(aaron.calendar.filter(\.inStreak).count == 14)
        #expect(aaron.calendar.filter(\.made).count == aaron.record.made)
        #expect(aaron.calendar.last?.inStreak == true)
        #expect(aaron.record.byWeekday.map(\.made) == [19, 35, 33])
        #expect(aaron.record.byWeekday.map(\.weekday) == [.mon, .wed, .fri])
        #expect(aaron.allTime == nil)
        #expect(aaron.nextMilestone == nil)
    }

    @Test("Equal run counts share a rank")
    func sharedRank() {
        let model = DashboardModel(season: 2026, runs: [
            clubRun("2026-09-21", ["Ann", "Bob", "Cat"]), clubRun("2026-09-23", ["Ann", "Bob"]),
        ])
        #expect(model.runners["Ann"]?.rank == 1)
        #expect(model.runners["Bob"]?.rank == 1)
        #expect(model.runners["Cat"]?.rank == 3)
        #expect(model.leaderboard.byRuns.map(\.name) == ["Ann", "Bob", "Cat"])
    }

    @Test("Planned rows, blank rows and runs without km behave")
    func unrecordedAndNoKm() {
        let model = DashboardModel(season: 2026, runs: [
            clubRun("2026-09-21", ["Ann"], actualKm: nil),
            clubRun("2026-09-23", ["Ann"]),
            clubRun("2026-09-25", []),                  // blank past Friday
            clubRun("2026-09-28", []),                  // planned Monday
        ])
        #expect(model.headline.runs == 2)
        #expect(model.headline.memberKm == 8)
        #expect(model.clubDays.days.count == 2)
        #expect(model.runners["Ann"]?.record.current == 2)
        #expect(model.leaderboard.byKm.map(\.memberKm) == [8])
    }

    @Test("A runner with no km is on the runs board but not the km board")
    func zeroKmRunner() {
        let model = DashboardModel(season: 2026, runs: [clubRun("2026-09-21", ["Ann"], actualKm: nil)])
        #expect(model.leaderboard.byRuns.map(\.name) == ["Ann"])
        #expect(model.leaderboard.byKm.isEmpty)
    }

    @Test("An empty season builds empty cards")
    func emptySeason() {
        let model = DashboardModel(season: 2026, runs: [])
        #expect(model.headline == Headline(runs: 0, memberKm: 0, runners: 0, perRun: 0, vsPrevious: nil))
        #expect(model.onARoll.current.isEmpty)
        #expect(model.wall.columns.isEmpty)
        #expect(model.recentWall.rows.isEmpty)
        #expect(model.recentRuns.isEmpty)
        #expect(model.runners.isEmpty)
    }

    @Test("Runs sharing a date keep the order they were given")
    func sameDateOrder() {
        let half = clubRun("2026-01-26", ["Ann"], run: "Half - Invasion Day")
        let tenK = clubRun("2026-01-26", ["Bob"], run: "10k - Invasion Day")
        let later = clubRun("2026-01-28", ["Ann"])
        let model = DashboardModel(season: 2026, runs: [later, half, tenK])
        #expect(model.runs.map(\.id) == [half.id, tenK.id, later.id])
    }
}
