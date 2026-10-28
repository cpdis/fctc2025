//
//  MilestonesSection.swift
//  FCTCAttendance
//
//  Who is near a landmark run, shown on the Events tab.
//
//  Passive by design: no notification, no Settings control. The weekly email
//  is the active nudge; this is the place to glance at. A row opens the
//  runner's Dashboard screen, as a name on the Dashboard does, when the
//  Dashboard has one: a runner with no run in its view stays a plain row.
//

import FCTCAttendanceKit
import SwiftUI

struct MilestonesSection: View {
    /// The shortlist over all-time totals, built once per data change by `EventsBoard`.
    let candidates: [MilestoneCandidate]
    /// This launch's empty-state line, held by the runtime.
    let emptyPhrase: String
    /// The names the Dashboard has a runner screen for.
    let linked: Set<String>

    var body: some View {
        Section {
            if candidates.isEmpty {
                Text(emptyPhrase)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("milestone-empty")
            } else {
                ForEach(candidates) { candidate in
                    Group {
                        if linked.contains(candidate.name) {
                            NavigationLink(value: DashboardRoute.runner(candidate.name)) {
                                MilestoneRow(candidate: candidate)
                            }
                        } else {
                            MilestoneRow(candidate: candidate)
                        }
                    }
                    .accessibilityIdentifier("milestone-row-\(candidate.name)")
                }
            }
        } header: {
            Text("Milestones")
                .accessibilityIdentifier("events-milestones")
        }
    }
}

/// A name with its all-time count, and the distance to go in a pill.
private struct MilestoneRow: View {
    let candidate: MilestoneCandidate

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.name)
                // A shortlisted runner is at most 10 short of a multiple of 50,
                // so the count is never 1.
                Text(Self.allTimeRuns(candidate.runs))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 12)
            Text("\(candidate.runsNeeded) to \(candidate.milestone)")
                .font(.subheadline.weight(.semibold))
                // Digits keep their column as the numbers change.
                .monospacedDigit()
                .foregroundStyle(.tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.tint.opacity(0.14), in: .capsule)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(candidate.name), \(distance), \(Self.allTimeRuns(candidate.runs))")
    }

    /// "3 runs to 150", for VoiceOver, where the pill's shorthand reads badly.
    private var distance: String {
        let runs = DashboardFormat.runs(candidate.runsNeeded)
        return "\(runs) to \(candidate.milestone)"
    }
    /// "147 all-time runs": the count and the adjective read in that order.
    private static func allTimeRuns(_ count: Int) -> String {
        "\(count) all-time \(count == 1 ? "run" : "runs")"
    }

}
