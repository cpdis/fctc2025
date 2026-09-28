//
//  MilestoneBoard.swift
//  FCTCAttendanceKit
//
//  Who is near a landmark run. Pure policy over cached lifetime totals, so the
//  rule can be argued with in a unit test rather than against the live sheet.
//
//  Deliberately simpler than the weekly email, which additionally forecasts the
//  chance of getting there. This is the passive view: a name and a distance.
//

import Foundation

/// One person's approach to their next landmark run.
public struct MilestoneCandidate: Hashable, Sendable, Identifiable {
    public var name: String
    /// Runs across every season.
    public var runs: Int
    /// The next positive multiple of `MilestoneBoard.step`.
    public var milestone: Int
    /// How many more runs are needed to reach it. Always 1 or more.
    public var runsNeeded: Int

    public var id: String { name }

    public init(name: String, runs: Int, milestone: Int, runsNeeded: Int) {
        self.name = name
        self.runs = runs
        self.milestone = milestone
        self.runsNeeded = runsNeeded
    }
}

public enum MilestoneBoard {

    /// Landmarks are every 50 runs, matching `src/utils/milestones.js`.
    public static let step = 50

    /// Nobody further out than this appears. Ten runs is roughly three weeks of
    /// running, past which "ahead" stops meaning anything and the section would
    /// read as a leaderboard.
    public static let ceiling = 10

    /// How many people the section shows before the tie rule extends it.
    public static let places = 3

    /// The next landmark for a given lifetime count.
    ///
    /// Someone sitting exactly on a landmark is already past it, so 100 needs 50
    /// more rather than 0. There is no such thing as needing zero runs.
    public static func nextMilestone(after runs: Int) -> Int {
        (runs / step + 1) * step
    }

    /// The people to show, closest first.
    ///
    /// The closest `places` are taken, then anyone tied with the last of them is
    /// included too. Splitting a tie would drop one of two people at the same
    /// distance, and which one got dropped would flip as unrelated rows changed.
    ///
    /// - Parameter totals: name and lifetime run count, in any order.
    public static func shortlist(from totals: [(name: String, runs: Int)]) -> [MilestoneCandidate] {
        let eligible = totals
            // Someone who has never run is not approaching their fiftieth.
            .filter { $0.runs > 0 }
            .map { total -> MilestoneCandidate in
                let milestone = nextMilestone(after: total.runs)
                return MilestoneCandidate(
                    name: total.name,
                    runs: total.runs,
                    milestone: milestone,
                    runsNeeded: milestone - total.runs
                )
            }
            .filter { $0.runsNeeded <= ceiling }
            // Name breaks the tie so the order is stable between refreshes.
            .sorted { ($0.runsNeeded, $0.name) < ($1.runsNeeded, $1.name) }

        guard eligible.count > places else { return eligible }
        let lastPlace = eligible[places - 1].runsNeeded
        return eligible.filter { $0.runsNeeded <= lastPlace }
    }

    /// The shortlist over all-time totals (KTD12): each member's prior runs plus
    /// their runs in `season`, for everyone with a prior or a run this season.
    /// Events and the Dashboard both call this, so both tabs name the same people.
    ///
    /// - Parameters:
    ///   - priors: lifetime runs before this season.
    ///   - season: this season's effective runs. Planned rows have no attendees,
    ///     so they add nothing.
    public static func shortlist(priors: LifetimePriors, season: [ClubRun]) -> [MilestoneCandidate] {
        var seasonRuns: [String: Int] = [:]
        for name in season.lazy.flatMap(\.attendees) { seasonRuns[name, default: 0] += 1 }
        let names = Set(priors.runs.keys).union(seasonRuns.keys)
        return shortlist(from: names.map { name in
            (name: name, runs: priors.allTime(for: name, seasonRuns: seasonRuns[name] ?? 0))
        })
    }
}
