//
//  ParityFixtureTests.swift
//  FCTCAttendanceKitTests
//
//  U12, R28 — the golden parity fixtures (`fixtures/attendance/parity/<season>.json`,
//  written by the web's own rules via `scripts/build-parity-fixtures.js`).
//
//  For each season the Swift kit must:
//   • parse every run's raw `run` and `meet` cells with `RunLabel` into the golden
//     type, event and location, and land every date on the golden weekday;
//   • recompute, from the golden runs alone, the expected totals, member-km, club
//     days, streaks and milestone shortlist.
//  A failure here means the JS and Swift rules drifted. Fix the rule, never the
//  fixture (regenerate it only from the web side).
//

import Foundation
import Testing

@testable import FCTCAttendanceKit

/// One season's golden fixture. The schema is in `fixtures/attendance/README.md`.
/// The club-day and Dashboard suites read the same files.
struct ParityFixture: Decodable {
    struct Run: Decodable {
        let id: String
        let date: String
        let weekday: String
        let run: String
        let meet: String
        let type: String
        let event: String?
        let location: String
        let actualKm: Double
        let attendees: [String]
        let plusOnes: Int
    }

    struct Totals: Decodable {
        let runs: Int
        let memberKm: Double
        let runners: Int
    }

    struct Member: Decodable {
        let name: String
        let runs: Int
        let memberKm: Double
    }

    struct Days: Decodable {
        let count: Int
        let dates: [String]
    }

    struct Streak: Decodable {
        let name: String
        let current: Int
        let currentFrom: String?
        let best: Int
        let bestFrom: String?
        let bestTo: String?
        let madeByWeekday: [String: Int]
    }

    struct Milestone: Decodable {
        let name: String
        let runs: Int
        let milestone: Int
        let runsNeeded: Int
    }

    struct Expected: Decodable {
        let totals: Totals
        let members: [Member]
        let clubDays: Days
        let streaks: [Streak]
        let milestones: [Milestone]
    }

    let season: Int
    let clubWeekdays: [String]
    let runs: [Run]
    let expected: Expected

    static let seasons = [2025, 2026]

    static func load(_ season: Int) throws -> ParityFixture {
        let data = try Data(contentsOf: Fixtures.url("parity/\(season).json"))
        return try JSONDecoder().decode(ParityFixture.self, from: data)
    }

    /// The golden runs as the kit's run value, in the fixture's (date, sheet) order.
    func clubRuns() throws -> [ClubRun] {
        try runs.map { run in
            ClubRun(
                id: run.id, date: try #require(ClubDate(iso: run.date)), season: season,
                run: run.run, meet: run.meet, actualKm: run.actualKm,
                attendees: run.attendees, plusOnes: run.plusOnes
            )
        }
    }
}

/// Kilometres to 2 decimals after summing, as the fixture script rounds them.
func roundKm(_ km: Double) -> Double {
    (km * 100).rounded() / 100
}

@Suite("Parity fixtures — Swift matches the web")
struct ParityFixtureTests {

    @Test("The season's club weekdays match the web table", arguments: ParityFixture.seasons)
    func clubWeekdays(season: Int) throws {
        let fixture = try ParityFixture.load(season)
        #expect(fixture.season == season)
        #expect(ClubDays.weekdays(for: season).map(\.shortName) == fixture.clubWeekdays)
    }

    @Test("RunLabel parses every raw run and meet into the golden fields", arguments: ParityFixture.seasons)
    func labels(season: Int) throws {
        let fixture = try ParityFixture.load(season)
        #expect(!fixture.runs.isEmpty)
        for run in fixture.runs {
            let label = RunLabel(run.run)
            #expect(label.type == run.type, "\(run.id): \(run.run)")
            #expect(label.event == run.event, "\(run.id): \(run.run)")
            #expect(RunLabel.location(run.meet) == run.location, "\(run.id): \(run.meet)")
            #expect(ClubDate(iso: run.date)?.weekday.shortName == run.weekday, "\(run.id)")
        }
    }

    @Test("Totals and member-km match", arguments: ParityFixture.seasons)
    func totals(season: Int) throws {
        let fixture = try ParityFixture.load(season)
        let model = DashboardModel(season: season, runs: try fixture.clubRuns())
        let expected = fixture.expected

        #expect(model.headline.runs == expected.totals.runs)
        #expect(roundKm(model.headline.memberKm) == expected.totals.memberKm)
        #expect(model.headline.runners == expected.totals.runners)

        let members = model.leaderboard.byRuns.sorted { codeUnitPrecedes($0.name, $1.name) }
        #expect(members.map(\.name) == expected.members.map(\.name))
        for (member, wanted) in zip(members, expected.members) {
            #expect(member.runs == wanted.runs, "\(wanted.name)")
            #expect(roundKm(member.memberKm) == wanted.memberKm, "\(wanted.name)")
        }
    }

    @Test("Club days match", arguments: ParityFixture.seasons)
    func clubDays(season: Int) throws {
        let fixture = try ParityFixture.load(season)
        let days = ClubDays(runs: try fixture.clubRuns())
        #expect(days.days.count == fixture.expected.clubDays.count)
        #expect(days.days.map(\.date.iso) == fixture.expected.clubDays.dates)
    }

    @Test("Current and best streaks and made-by-weekday match", arguments: ParityFixture.seasons)
    func streaks(season: Int) throws {
        let fixture = try ParityFixture.load(season)
        let model = DashboardModel(season: season, runs: try fixture.clubRuns())
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
            // Mon..Sun order, like the web's key order.
            #expect(record.byWeekday.map(\.weekday) == record.byWeekday.map(\.weekday).sorted())
        }
    }

    @Test("The milestone shortlist over season totals matches", arguments: ParityFixture.seasons)
    func milestones(season: Int) throws {
        let fixture = try ParityFixture.load(season)
        let runs = try fixture.clubRuns()
        // Lifetime equal to the season makes every prior 0, so all-time is the
        // season total the fixture's milestones are computed over.
        let seasonTotals = fixture.expected.members.map { MemberTotal(name: $0.name, runs: $0.runs) }
        let priors = LifetimePriors(lifetimeTotals: seasonTotals, payload: runs)
        #expect(priors.runs.values.allSatisfy { $0 == 0 })

        let model = DashboardModel(season: season, runs: runs, priors: priors)
        #expect(model.milestones.map(\.name) == fixture.expected.milestones.map(\.name))
        #expect(model.milestones.map(\.runs) == fixture.expected.milestones.map(\.runs))
        #expect(model.milestones.map(\.milestone) == fixture.expected.milestones.map(\.milestone))
        #expect(model.milestones.map(\.runsNeeded) == fixture.expected.milestones.map(\.runsNeeded))
    }
}
