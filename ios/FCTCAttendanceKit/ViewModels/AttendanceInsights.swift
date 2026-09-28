//
//  AttendanceInsights.swift
//  FCTCAttendanceKit
//
//  Pure review-round helpers shared by view models and SwiftUI views.
//

import Foundation

public enum CatchUpPlanner {
    /// Return blank runs before today, newest first. This order lets a catch-up
    /// session move backwards one run at a time without changing Home navigation.
    public static func unrecordedPastRuns(
        among runs: [RunSnapshot],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [RunSnapshot] {
        let today = calendar.startOfDay(for: now)
        return runs
            .filter { run in
                guard let date = run.scheduledAt else { return false }
                return date < today && !run.hasRecordedAttendance
            }
            .sorted(by: descending)
    }

    public static func nextOlderUnrecorded(
        after current: RunSnapshot,
        among runs: [RunSnapshot],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> RunSnapshot? {
        guard let currentDate = current.scheduledAt else { return nil }
        let today = calendar.startOfDay(for: now)
        guard currentDate < today else { return nil }
        return unrecordedPastRuns(among: runs, now: now, calendar: calendar)
            .first { candidate in
                guard let candidateDate = candidate.scheduledAt else { return false }
                return (candidateDate, candidate.rowIndex) < (currentDate, current.rowIndex)
            }
    }

    private static func descending(_ lhs: RunSnapshot, _ rhs: RunSnapshot) -> Bool {
        (lhs.scheduledAt ?? .distantPast, lhs.rowIndex)
            > (rhs.scheduledAt ?? .distantPast, rhs.rowIndex)
    }
}

public struct MemberStats: Hashable, Sendable {
    public var attendanceCount: Int
    public var lastAttendedAt: Date?
    /// Consecutive most-recent club days made (R5), the rule the Dashboard uses.
    public var currentStreak: Int

    public init(attendanceCount: Int, lastAttendedAt: Date?, currentStreak: Int) {
        self.attendanceCount = attendanceCount
        self.lastAttendedAt = lastAttendedAt
        self.currentStreak = currentStreak
    }

    /// The checklist's streak line: "1 club day in a row", "14 club days in a row".
    public var streakLabel: String {
        currentStreak == 1 ? "1 club day in a row" : "\(currentStreak) club days in a row"
    }

    /// Empty scheduled rows are not evidence of an absence, and a row recorded
    /// ahead of its date must not break a streak today. Count recorded past rows
    /// only; the streak then walks their club days (`ClubDays`).
    public static func calculate(
        member: String,
        runs: [RunSnapshot],
        now: Date = .now
    ) -> MemberStats {
        let recorded = recordedRuns(runs, now: now)
        return calculate(member: member, recorded: recorded, clubDays: clubDays(recorded))
    }

    public static func calculateAll(
        members: [String],
        runs: [RunSnapshot],
        now: Date = .now
    ) -> [String: MemberStats] {
        let recorded = recordedRuns(runs, now: now)
        let days = clubDays(recorded)
        return Dictionary(uniqueKeysWithValues: members.map { member in
            (member, calculate(member: member, recorded: recorded, clubDays: days))
        })
    }

    private static func calculate(
        member: String,
        recorded: [RunSnapshot],
        clubDays: ClubDays
    ) -> MemberStats {
        let attended = recorded.filter { $0.attendees.contains(member) }
        return MemberStats(
            attendanceCount: attended.count,
            lastAttendedAt: attended.compactMap(\.scheduledAt).max(),
            currentStreak: clubDays.record(for: member).current
        )
    }

    private static func recordedRuns(
        _ runs: [RunSnapshot],
        now: Date
    ) -> [RunSnapshot] {
        runs.filter { ($0.scheduledAt ?? .distantFuture) <= now && $0.hasRecordedAttendance }
    }

    private static func clubDays(_ recorded: [RunSnapshot]) -> ClubDays {
        ClubDays(runs: recorded.compactMap { ClubRun($0) })
    }
}

public enum MemberAvatar {
    public static let paletteCount = 8

    public static func initials(for name: String) -> String {
        let tokens = name.split(whereSeparator: { $0.isWhitespace })
        return tokens.prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }

    /// Swift's Hasher changes between launches. This small weighted hash stays
    /// stable across app versions and gives each canonical sheet name one color.
    public static func paletteIndex(for name: String) -> Int {
        let canonical = GuestNames.canonical(name)
        let value = canonical.utf8.enumerated().reduce(0) { partial, pair in
            partial &+ (pair.offset + 1) &* Int(pair.element)
        }
        return value % paletteCount
    }
}
