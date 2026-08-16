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
    public var currentStreak: Int

    public init(attendanceCount: Int, lastAttendedAt: Date?, currentStreak: Int) {
        self.attendanceCount = attendanceCount
        self.lastAttendedAt = lastAttendedAt
        self.currentStreak = currentStreak
    }

    /// Empty scheduled rows are not evidence of an absence. Calculate the streak
    /// across recorded past rows only, newest first.
    public static func calculate(
        member: String,
        runs: [RunSnapshot],
        now: Date = .now
    ) -> MemberStats {
        calculate(member: member, recorded: recordedRuns(runs, now: now))
    }

    public static func calculateAll(
        members: [String],
        runs: [RunSnapshot],
        now: Date = .now
    ) -> [String: MemberStats] {
        let recorded = recordedRuns(runs, now: now)
        return Dictionary(uniqueKeysWithValues: members.map { member in
            (member, calculate(member: member, recorded: recorded))
        })
    }

    private static func calculate(
        member: String,
        recorded: [RunSnapshot]
    ) -> MemberStats {
        let attended = recorded.filter { $0.attendees.contains(member) }
        var streak = 0
        for run in recorded {
            guard run.attendees.contains(member) else { break }
            streak += 1
        }
        return MemberStats(
            attendanceCount: attended.count,
            lastAttendedAt: attended.compactMap(\.scheduledAt).max(),
            currentStreak: streak
        )
    }

    private static func recordedRuns(
        _ runs: [RunSnapshot],
        now: Date
    ) -> [RunSnapshot] {
        runs
            .filter { ($0.scheduledAt ?? .distantFuture) <= now && $0.hasRecordedAttendance }
            .sorted {
                ($0.scheduledAt ?? .distantPast, $0.rowIndex)
                    > ($1.scheduledAt ?? .distantPast, $1.rowIndex)
            }
    }
}

public enum GuestPromotionCounter {
    public static let threshold = 3

    /// Count a guest once per submission. Case and diacritics do not create a new
    /// history identity, matching the roster's existing uniqueness rule.
    public static func counts(in submissionGuestNames: [[String]]) -> [String: Int] {
        var result: [String: Int] = [:]
        for names in submissionGuestNames {
            let unique = Set(names.map(canonical).filter { !$0.isEmpty })
            for name in unique { result[name, default: 0] += 1 }
        }
        return result
    }

    public static func isFrequent(
        _ name: String,
        counts: [String: Int],
        threshold: Int = threshold
    ) -> Bool {
        counts[canonical(name), default: 0] >= threshold
    }

    public static func canonical(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
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
        let canonical = GuestPromotionCounter.canonical(name)
        let value = canonical.utf8.enumerated().reduce(0) { partial, pair in
            partial &+ (pair.offset + 1) &* Int(pair.element)
        }
        return value % paletteCount
    }
}
