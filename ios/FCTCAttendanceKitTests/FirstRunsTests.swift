//
//  FirstRunsTests.swift
//  FCTCAttendanceKitTests
//
//  Each runner's club days since their first run in any season (Grant's build
//  14 feedback), for the runner screen's "Since first run" card.
//

import Foundation
import Testing

@testable import FCTCAttendanceKit

@Suite("First runs")
struct FirstRunsTests {

    /// 2025 ran Wed and Fri; 2026 runs Mon, Wed and Fri. Aaron starts on Fri 26
    /// Dec 2025. Mon 29 Dec 2025 is a special (2025 had no Monday runs), so
    /// René's first club day is Mon 5 Jan 2026. Fri 2 Jan is a blank row.
    private let runs = [
        clubRun("2025-12-26", ["Aaron"]),
        clubRun("2025-12-29", ["Aaron", "René"]),
        clubRun("2025-12-31", ["Aaron"]),
        clubRun("2026-01-02", []),
        clubRun("2026-01-05", ["Aaron", "René"]),
        clubRun("2026-01-07", ["René"]),
    ]

    /// Nobody ran before 2025.
    private let nothingBefore = LifetimePriors(lifetimeTotals: [], payload: [])

    @Test("A first run counts club days from that day on, across seasons")
    func acrossSeasons() throws {
        let firstRuns = FirstRuns.build(runs: runs, before: nothingBefore)
        let aaron = try #require(firstRuns["Aaron"])
        #expect(aaron.date.iso == "2025-12-26")
        // Club days: 26 and 31 Dec, 5 and 7 Jan (the blank 2 Jan is none).
        // Aaron made the first three.
        #expect(aaron.made == 3)
        #expect(aaron.clubDays == 4)
    }

    @Test("A special neither starts a first run nor counts toward one")
    func specialIsNoClubDay() throws {
        let rene = try #require(FirstRuns.build(runs: runs, before: nothingBefore)["René"])
        #expect(rene.date.iso == "2026-01-05")
        #expect(rene.made == 2)
        #expect(rene.clubDays == 2)
    }

    @Test("A runner with runs before the data has no first run")
    func ranBefore() {
        let before = LifetimePriors(lifetimeTotals: [MemberTotal(name: "Aaron", runs: 3)], payload: [])
        let firstRuns = FirstRuns.build(runs: runs, before: before)
        #expect(firstRuns["Aaron"] == nil)
        #expect(firstRuns["René"]?.date.iso == "2026-01-05")
    }

    @Test("Without lifetime totals nobody's first run is known")
    func noTotals() {
        #expect(FirstRuns.build(runs: runs, before: nil).isEmpty)
    }
}
