//
//  BeenAWhileTests.swift
//  FCTCAttendanceKitTests
//
//  Grant's "been a while…" list (23 Nov 2026): members who ran in the last 12
//  weeks but not in the last 4, counted in days back from today in Perth.
//
//    today Mon 23 Nov 2026
//    window from Mon 31 Aug (84 days back) ... recent from Mon 26 Oct (28 days back)
//

import Foundation
import Testing

@testable import FCTCAttendanceKit

@Suite("Been a while")
struct BeenAWhileTests {

    private let today = ClubDate(iso: "2026-11-23")!

    private func names(_ runs: [ClubRun], roster: Set<String> = [], today: ClubDate? = nil) -> [String] {
        BeenAWhile(runs: runs, roster: roster, today: today ?? self.today).runners.map(\.name)
    }

    @Test("A run exactly 28 days ago is recent; 29 days ago is a while")
    func recentBoundary() {
        // Mon 26 Oct is 28 days back, Sun 25 Oct 29.
        let runs = [
            clubRun("2026-09-02", ["Aaron", "Ben"]),
            clubRun("2026-10-25", ["Ben"], run: "Pub Run"),
            clubRun("2026-10-26", ["Aaron"]),
        ]
        #expect(names(runs) == ["Ben"])
    }

    @Test("A run exactly 84 days ago is in the window; 85 days ago is not")
    func windowBoundary() {
        // Mon 31 Aug is 84 days back, Sun 30 Aug 85.
        let runs = [
            clubRun("2026-08-30", ["Cat"], run: "Pub Run"),
            clubRun("2026-08-31", ["Dee"]),
        ]
        #expect(names(runs) == ["Dee"])
    }

    @Test("Each row has the last run, the whole weeks since it and the runs in the window")
    func rowDetails() throws {
        let runs = [
            clubRun("2026-08-28", ["Liam"]),
            clubRun("2026-09-02", ["Liam", "Jack"]),
            clubRun("2026-10-21", ["Liam"]),
            clubRun("2026-10-23", ["Liam"]),
        ]
        let board = BeenAWhile(runs: runs, roster: [], today: today)
        let liam = try #require(board.runners.first)
        #expect(liam.name == "Liam")
        #expect(liam.lastRun.iso == "2026-10-23")
        #expect(liam.daysAway == 31)
        #expect(liam.weeksAway == 4)
        // 28 Aug is before the window, so 3 of Liam's 4 runs count.
        #expect(liam.runs == 3)
        let jack = try #require(board.runners.last)
        #expect(jack.weeksAway == 11)
        #expect(jack.runs == 1)
    }

    @Test("Twelve weeks, oldest first, mark the weeks with a run")
    func weeks() throws {
        // 84 days back is the first cell, 29 the 5th from the end, 30 the same week.
        let runs = [
            clubRun("2026-08-31", ["Liam"]),
            clubRun("2026-10-24", ["Liam"], run: "Pub Run"),
            clubRun("2026-10-25", ["Liam"], run: "Pub Run"),
        ]
        let liam = try #require(BeenAWhile(runs: runs, roster: [], today: today).runners.first)
        #expect(liam.weeks == [true] + Array(repeating: false, count: 6) + [true, false, false, false, false])
        #expect(liam.weeks.count == 12)
    }

    @Test("The latest last run comes first, then name")
    func order() {
        let runs = [
            clubRun("2026-09-02", ["Jack"]),
            clubRun("2026-09-05", ["Rhys", "Laura E"], run: "Pub Run"),
            clubRun("2026-10-23", ["Liam"]),
        ]
        #expect(names(runs) == ["Liam", "Laura E", "Rhys", "Jack"])
    }

    @Test("A special counts as a run, so a Pub Run keeps a member off the list")
    func specialsCount() {
        let runs = [
            clubRun("2026-09-02", ["Aaron"]),
            clubRun("2026-11-21", ["Aaron"], run: "Pub Run"),
        ]
        #expect(names(runs).isEmpty)
    }

    @Test("Guests are not listed: +1s are counts, not people")
    func guestsIgnored() {
        let runs = [clubRun("2026-09-02", [], plusOnes: 2)]
        #expect(names(runs).isEmpty)
    }

    @Test("A known roster drops anyone no longer on the sheet")
    func rosterFilters() {
        let runs = [clubRun("2026-09-02", ["Aaron", "Gone"])]
        #expect(names(runs, roster: ["Aaron"]) == ["Aaron"])
        #expect(names(runs, roster: []) == ["Aaron", "Gone"], "an unknown roster drops nobody")
    }

    @Test("In January the window reaches back into last season")
    func acrossSeasons() {
        // Today Wed 20 Jan 2027: the window opens Wed 28 Oct 2026, recent from Wed 23 Dec.
        let runs = [
            clubRun("2026-12-18", ["Aaron", "Col"]),
            clubRun("2027-01-18", ["Col"]),
        ]
        #expect(names(runs, today: ClubDate(iso: "2027-01-20")!) == ["Aaron"])
    }

    @Test("A run after today counts as recent")
    func laterRunIsRecent() {
        let runs = [
            clubRun("2026-09-02", ["Aaron"]),
            clubRun("2026-11-25", ["Aaron"]),
        ]
        #expect(names(runs).isEmpty)
    }

    @Test("Nobody qualifies: the list is empty")
    func empty() {
        #expect(BeenAWhile(runs: [], roster: [], today: today).runners.isEmpty)
        #expect(names([clubRun("2026-11-20", ["Aaron"])]).isEmpty)
    }
}
