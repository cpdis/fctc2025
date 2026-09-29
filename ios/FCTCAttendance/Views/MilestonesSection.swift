//
//  MilestonesSection.swift
//  FCTCAttendance
//
//  Who is near a landmark run, shown on the Events tab.
//
//  Passive by design: no tap target, no notification, no Settings control. The
//  weekly email is the active nudge; this is the place to glance at.
//

import FCTCAttendanceKit
import SwiftUI

struct MilestonesSection: View {
    /// The shortlist over all-time totals, built once per data change by `EventsBoard`.
    let candidates: [MilestoneCandidate]
    /// This launch's empty-state line, held by the runtime.
    let emptyPhrase: String

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
                    MilestoneRow(candidate: candidate)
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
                Text("\(candidate.runs) all-time runs")
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
        .accessibilityLabel("\(candidate.name), \(distance), \(candidate.runs) all-time runs")
    }

    /// "3 runs to 150", for VoiceOver, where the pill's shorthand reads badly.
    private var distance: String {
        let runs = candidate.runsNeeded == 1 ? "1 run" : "\(candidate.runsNeeded) runs"
        return "\(runs) to \(candidate.milestone)"
    }
}
