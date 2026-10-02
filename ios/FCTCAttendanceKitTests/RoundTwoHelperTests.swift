//
//  RoundTwoHelperTests.swift
//  FCTCAttendanceKitTests
//
//  Review-round-two attendance helper rules.
//

import Foundation
import SwiftData
import Testing

@testable import FCTCAttendanceKit

@Suite("Round two attendance helpers")
struct RoundTwoHelperTests {
    private let now = Date(timeIntervalSince1970: 1_786_665_600) // 2026-08-14 UTC

    @Test("Catch-up selects the nearest older unrecorded run")
    func catchUpSelection() throws {
        let current = run(row: 4, dayOffset: -1)
        let runs = [
            run(row: 1, dayOffset: -4),
            run(row: 2, dayOffset: -3, attendees: ["Col"]),
            run(row: 3, dayOffset: -2),
            current,
            run(row: 5, dayOffset: 1),
        ]

        let next = CatchUpPlanner.nextOlderUnrecorded(
            after: current,
            among: runs,
            now: now,
            calendar: utcCalendar
        )

        #expect(next?.rowIndex == 3)
        #expect(
            CatchUpPlanner.nextOlderUnrecorded(
                after: run(row: 6, dayOffset: 0),
                among: runs,
                now: now,
                calendar: utcCalendar
            ) == nil
        )
        #expect(
            CatchUpPlanner.unrecordedPastRuns(
                among: runs,
                now: now,
                calendar: utcCalendar
            ).map(\.rowIndex) == [4, 3, 1]
        )
    }

    @Test("Member stats count attendance, last date, and the club-day streak")
    func memberStats() throws {
        // Week of Mon 14 Sep 2026 to Mon 28 Sep, read on Sun 27 Sep.
        let today = try #require(deviceCalendar.date(from: DateComponents(year: 2026, month: 9, day: 27, hour: 12)))
        let runs = [
            sheetRun(row: 1, "Mon, 14-Sep", attendees: ["Col"]),
            sheetRun(row: 2, "Wed, 16-Sep", attendees: ["Aaron"]),
            sheetRun(row: 3, "Fri, 18-Sep", attendees: ["Col"]),
            sheetRun(row: 4, "Mon, 21-Sep", attendees: ["Col", "Aaron"]),
            sheetRun(row: 5, "Wed, 23-Sep", attendees: ["Col"]),
            // A blank past Friday is not a club day, so it breaks nothing.
            sheetRun(row: 6, "Fri, 25-Sep"),
            // The Saturday special neither adds to nor breaks a streak.
            sheetRun(row: 7, "Sat, 26-Sep", attendees: ["Aaron"]),
            // Recorded ahead of its date: ignored until it happens.
            sheetRun(row: 8, "Mon, 28-Sep", attendees: ["Aaron"]),
        ]

        let stats = MemberStats.calculate(member: "Col", runs: runs, now: today)

        #expect(stats.attendanceCount == 4)
        #expect(stats.lastAttendedAt == runs[4].scheduledAt)
        #expect(stats.currentStreak == 3)
        let all = MemberStats.calculateAll(members: ["Col", "Aaron"], runs: runs, now: today)
        #expect(all["Col"] == stats)
        // Aaron missed Wed 23 Sep, the latest club day.
        #expect(all["Aaron"]?.currentStreak == 0)
        #expect(all["Aaron"]?.attendanceCount == 3)
    }

    @Test("Member stats give Aaron his 14 club days in a row on the 2026 fixture")
    func memberStatsFixture() throws {
        let today = try #require(deviceCalendar.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 12)))
        let runs = try ParityFixture.load(2026).runs.enumerated().map { index, golden in
            let date = try #require(ClubDate(iso: golden.date))
            let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
            return sheetRun(
                row: index + 5, "\(golden.weekday), \(date.day)-\(months[date.month - 1])",
                attendees: golden.attendees, plusOnes: golden.plusOnes
            )
        }

        let aaron = MemberStats.calculate(member: "Aaron", runs: runs, now: today)

        #expect(aaron.attendanceCount == 89)
        #expect(aaron.currentStreak == 14)
        #expect(aaron.streakLabel == "14 club days in a row")
    }

    @Test("The streak label counts club days, singular for one")
    func streakLabel() {
        let stats = { (streak: Int) in MemberStats(attendanceCount: 9, lastAttendedAt: nil, currentStreak: streak) }
        #expect(stats(0).streakLabel == "0 club days in a row")
        #expect(stats(1).streakLabel == "1 club day in a row")
        #expect(stats(2).streakLabel == "2 club days in a row")
    }

    @Test("Promotion is suggested at ten confirmed distinct runs")
    func promotionThreshold() {
        for count in [9, 10, 11] {
            let guest = SharedGuest(guestId: UUID().uuidString, displayName: "Rene", confirmedRuns: count)
            #expect(guest.canSuggestPromotion == (count >= 10))
            #expect(guest.status == "active")
        }
    }

    @Test("Avatar initials and palette indexes are stable")
    func avatarIdentity() {
        #expect(MemberAvatar.initials(for: " Alex Kravchenko ") == "AK")
        #expect(MemberAvatar.initials(for: "Col") == "C")
        #expect(MemberAvatar.paletteIndex(for: "Álex Kr") == MemberAvatar.paletteIndex(for: "alex kr"))
        #expect(MemberAvatar.paletteIndex(for: "Alex Kr") == 0)
        #expect((0..<8).contains(MemberAvatar.paletteIndex(for: "Someone Else")))
    }

    /// The app parses sheet dates in the device zone (`SyncEngine.parseDate`).
    private var deviceCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    /// A 2026 sheet row as the cache holds it: sheet date text, season year and
    /// `scheduledAt` at device-zone midnight, like `SyncEngine.parseDate`.
    private func sheetRun(
        row: Int,
        _ date: String,
        attendees: [String] = [],
        plusOnes: Int = 0
    ) -> RunSnapshot {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = deviceCalendar
        formatter.dateFormat = "EEE, d-MMM-yyyy"
        return RunSnapshot(
            rowIndex: row,
            date: date,
            scheduledAt: formatter.date(from: "\(date)-2026"),
            meet: "Il Lido",
            run: "Intervals",
            actualKm: 8,
            attendees: attendees,
            plusOnes: plusOnes,
            seasonYear: 2026
        )
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func run(
        row: Int,
        dayOffset: Int,
        attendees: [String] = [],
        plusOnes: Int = 0
    ) -> RunSnapshot {
        RunSnapshot(
            rowIndex: row,
            date: "Run \(row)",
            scheduledAt: utcCalendar.date(byAdding: .day, value: dayOffset, to: now),
            meet: "Meet \(row)",
            run: "Run \(row)",
            approxKm: 8,
            attendees: attendees,
            plusOnes: plusOnes,
            cachedRevision: "rev-1"
        )
    }
}
