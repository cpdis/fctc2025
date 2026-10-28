//
//  DashboardAllTimeTests.swift
//  FCTCAttendanceKitTests
//
//  The Dashboard's All time view: every season's runs in one `DashboardModel`.
//  The synthetic cases pin the rules; the parity cases hold the kit to the
//  web's All time numbers in `fixtures/attendance/parity/all-time.json`.
//

import Foundation
import Testing

@testable import FCTCAttendanceKit

/// The web's All time view of every season. Runs come from the season files.
struct AllTimeParityFixture: Decodable {
    struct Gap: Decodable {
        let name: String
        let cells: Int
    }

    struct Expected: Decodable {
        let totals: ParityFixture.Totals
        let members: [ParityFixture.Member]
        let clubDays: ParityFixture.Days
        let streaks: [ParityFixture.Streak]
        let milestones: [ParityFixture.Milestone]
        let notOnRoster: [Gap]
    }

    let seasons: [Int]
    let rosters: [String: [String]]
    let expected: Expected

    static func load() throws -> AllTimeParityFixture {
        let data = try Data(contentsOf: Fixtures.url("parity/all-time.json"))
        return try JSONDecoder().decode(AllTimeParityFixture.self, from: data)
    }

    /// Every season's golden runs.
    func clubRuns() throws -> [ClubRun] {
        try seasons.flatMap { try ParityFixture.load($0).clubRuns() }
    }

    /// Each season's sheet columns, as the store builds them from snapshots.
    var rosterSets: [Int: Set<String>] {
        Dictionary(uniqueKeysWithValues: rosters.compactMap { key, names in
            Int(key).map { ($0, Set(names.map(ClubRun.memberName))) }
        })
    }
}

@Suite("Dashboard All time")
struct DashboardAllTimeTests {

    // MARK: - Rules

    /// 2025 ran Wed and Fri; 2026 runs Mon, Wed and Fri. Aaron makes the last
    /// two club days of 2025 and the first two of 2026; Mon 29 Dec 2025 is a
    /// special. René joined in 2026.
    private let newYear = [
        clubRun("2025-12-26", ["Aaron"]),
        clubRun("2025-12-29", ["Aaron"]),
        clubRun("2025-12-31", ["Aaron"]),
        clubRun("2026-01-02", ["Aaron"]),
        clubRun("2026-01-05", ["Aaron", "René"]),
    ]

    @Test("A streak runs on from Wed 31 Dec 2025 into Fri 2 Jan 2026")
    func streakAcrossNewYear() throws {
        let allTime = DashboardModel(allTime: newYear, rosters: [:])
        let aaron = try #require(allTime.runners["Aaron"]?.record)
        #expect(aaron.current == 4)
        #expect(aaron.currentFrom?.iso == "2025-12-26")
        // The Monday of 2025 is a special: a run, not a club day.
        #expect(allTime.runs.filter(\.isSpecial).map(\.run.date.iso) == ["2025-12-29"])

        let season = DashboardModel(season: 2026, runs: newYear.filter { $0.season == 2026 })
        #expect(season.runners["Aaron"]?.record.current == 2)
    }

    @Test("All time names itself and compares with nothing")
    func comparesWithNothing() {
        let model = DashboardModel(allTime: newYear, rosters: [:])
        #expect(model.period == .allTime)
        #expect(model.season == nil)
        #expect(model.progress == nil)
        #expect(model.headline.vsPrevious == nil)
        #expect(model.headline.runs == 5)
        #expect(DashboardPeriod.allTime.label == "All time")
        #expect(DashboardPeriod.season(2025).label == "2025")
    }

    @Test("A season whose sheet had no column for the runner is off the roster, not a miss")
    func notOnRoster() throws {
        let rosters: [Int: Set<String>] = [2025: ["Aaron"], 2026: ["Aaron", "René"]]
        let model = DashboardModel(allTime: newYear, rosters: rosters)
        let rene = try #require(model.wall.rows.first { $0.name == "René" })
        // Three 2025 runs before René joined, a 2026 miss, then the club day
        // that starts his current streak.
        #expect(rene.cells == [.notOnRoster, .notOnRoster, .notOnRoster, .missed, .streak])

        // A season with no roster marks nobody.
        let unknown = DashboardModel(allTime: newYear, rosters: [2026: ["Aaron", "René"]])
        #expect(unknown.wall.rows.first { $0.name == "René" }?.cells.prefix(3).allSatisfy { $0 == .missed } == true)
    }

    @Test("The runner calendar splits by season, newest first")
    func calendarBySeason() throws {
        let model = DashboardModel(allTime: newYear, rosters: [:])
        let calendars = try #require(model.runners["Aaron"]?.calendarBySeason)
        #expect(calendars.map(\.season) == [2026, 2025])
        #expect(calendars.map { $0.days.map(\.date.iso) } == [["2026-01-02", "2026-01-05"], ["2025-12-26", "2025-12-31"]])
    }

    @Test("A given milestone shortlist wins over one built from the view")
    func milestonesFromOutside() {
        // 40 before plus 5 in view: 5 to go to 50.
        let priors = LifetimePriors(lifetimeTotals: [MemberTotal(name: "Aaron", runs: 40)], payload: [])
        #expect(DashboardModel(allTime: newYear, rosters: [:], priors: priors).milestones.map(\.name) == ["Aaron"])
        #expect(DashboardModel(allTime: newYear, rosters: [:], priors: priors, milestones: []).milestones.isEmpty)
    }

    // MARK: - Parity with the web

    private func parityModel() throws -> (AllTimeParityFixture, DashboardModel) {
        let fixture = try AllTimeParityFixture.load()
        return (fixture, DashboardModel(allTime: try fixture.clubRuns(), rosters: fixture.rosterSets))
    }

    @Test("Totals and member-km match the web's All time")
    func parityTotals() throws {
        let (fixture, model) = try parityModel()
        let expected = fixture.expected
        #expect(model.headline.runs == expected.totals.runs)
        #expect(roundKm(model.headline.memberKm) == expected.totals.memberKm)
        #expect(model.headline.runners == expected.totals.runners)

        let members = model.leaderboard.byRuns.sorted { codeUnitPrecedes($0.name, $1.name) }
        try #require(members.map(\.name) == expected.members.map(\.name))
        for (member, wanted) in zip(members, expected.members) {
            #expect(member.runs == wanted.runs, "\(wanted.name)")
            #expect(roundKm(member.memberKm) == wanted.memberKm, "\(wanted.name)")
        }
    }

    @Test("Club days and streaks across seasons match the web's All time")
    func parityStreaks() throws {
        let (fixture, model) = try parityModel()
        #expect(model.clubDays.days.map(\.date.iso) == fixture.expected.clubDays.dates)
        #expect(model.runners.count == fixture.expected.streaks.count)
        for wanted in fixture.expected.streaks {
            let record = try #require(model.runners[wanted.name]?.record, "\(wanted.name)")
            #expect(record.current == wanted.current, "\(wanted.name)")
            #expect(record.currentFrom?.iso == wanted.currentFrom, "\(wanted.name)")
            #expect(record.best == wanted.best, "\(wanted.name)")
            #expect(record.bestFrom?.iso == wanted.bestFrom, "\(wanted.name)")
            #expect(record.bestTo?.iso == wanted.bestTo, "\(wanted.name)")
            let made = Dictionary(uniqueKeysWithValues: record.byWeekday.map { ($0.weekday.shortName, $0.made) })
            #expect(made == wanted.madeByWeekday, "\(wanted.name)")
        }
    }

    @Test("Wall cells off the roster match the web's All time")
    func parityRoster() throws {
        let (fixture, model) = try parityModel()
        let gaps = model.wall.rows
            .map { (name: $0.name, cells: $0.cells.count { $0 == .notOnRoster }) }
            .filter { $0.cells > 0 }
            .sorted { codeUnitPrecedes($0.name, $1.name) }
        #expect(gaps.map(\.name) == fixture.expected.notOnRoster.map(\.name))
        #expect(gaps.map(\.cells) == fixture.expected.notOnRoster.map(\.cells))
    }

    @Test("Milestones match the web: all-time totals of the live season's members")
    func parityMilestones() throws {
        let fixture = try AllTimeParityFixture.load()
        let live = try ParityFixture.load(2026).clubRuns()
        // The store's inputs: lifetime totals for the live roster, counted with
        // the live season's own runs; the shortlist the store hands every view.
        let roster = fixture.rosterSets[2026] ?? []
        let lifetime = fixture.expected.members
            .filter { roster.contains($0.name) }
            .map { MemberTotal(name: $0.name, runs: $0.runs) }
        let priors = LifetimePriors(lifetimeTotals: lifetime, payload: live)
        let shortlist = MilestoneBoard.shortlist(priors: priors, season: live)

        let all = try fixture.clubRuns()
        let model = DashboardModel(allTime: all, rosters: fixture.rosterSets,
                                   priors: priors.rebased(live: live, onto: all), milestones: shortlist)
        #expect(model.milestones.map(\.name) == fixture.expected.milestones.map(\.name))
        #expect(model.milestones.map(\.runs) == fixture.expected.milestones.map(\.runs))
        #expect(model.milestones.map(\.runsNeeded) == fixture.expected.milestones.map(\.runsNeeded))
        // Each runner's all-time total is today's total.
        for member in fixture.expected.members {
            #expect(model.runners[member.name]?.allTime == member.runs, "\(member.name)")
        }
    }
}
