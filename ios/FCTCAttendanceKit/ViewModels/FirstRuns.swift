//
//  FirstRuns.swift
//  FCTCAttendanceKit
//
//  Each runner's club days since their first run ever (Grant's build 14
//  feedback): the fair attendance rate for someone who joined part way
//  through. The runner screen shows it whatever season the Dashboard shows,
//  so it is built from every season the app has, not from the shown view:
//
//    every season's runs ─┐
//    runs before them ────┴─> FirstRuns.build ─> name: first club day, made / held since
//
//  A runner with runs before the earliest season given has no entry: their
//  first run is not in the data, so any count would start in the wrong place.
//

import Foundation

/// One runner's club days from their first run on.
public struct FirstRun: Hashable, Sendable {
    /// The first club day they made.
    public let date: ClubDate
    /// Club days made from that day on, that day included.
    public let made: Int
    /// Club days held from that day on, that day included.
    public let clubDays: Int
}

public enum FirstRuns {

    /// Every runner's first run over `runs`.
    ///
    /// - Parameters:
    ///   - runs: every season's effective runs the app has, each with its own
    ///     season, in any order. Specials are runs, not club days, so they
    ///     neither start nor count toward a first run (`ClubDays`).
    ///   - before: lifetime runs before the earliest of those seasons. Nil
    ///     (no lifetime totals) builds nothing, as nobody's start is known.
    public static func build(runs: [ClubRun], before: LifetimePriors?) -> [String: FirstRun] {
        guard let before else { return [:] }
        let days = ClubDays(runs: runs).days
        var first: [String: Int] = [:]
        var made: [String: Int] = [:]
        for (index, day) in days.enumerated() {
            for name in day.attendees {
                if first[name] == nil { first[name] = index }
                made[name, default: 0] += 1
            }
        }
        var result: [String: FirstRun] = [:]
        for (name, index) in first where before.allTime(for: name, seasonRuns: 0) == 0 {
            result[name] = FirstRun(date: days[index].date, made: made[name] ?? 0, clubDays: days.count - index)
        }
        return result
    }
}
