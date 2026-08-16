//
//  MilestonesSection.swift
//  FCTCAttendance
//
//  Who is near a landmark run, shown below Runs on the home screen.
//
//  Passive by design: no tap target, no notification, no Settings control. The
//  weekly email is the active nudge; this is the place to glance at.
//
//  Its own file rather than another block inside HomeView, which is already past
//  the repo's 500-line guideline.
//

import FCTCAttendanceKit
import SwiftUI

struct MilestonesSection: View {
    /// Cached roster with lifetime totals. Filtering lives in MilestoneBoard.
    let members: [Member]
    /// This launch's empty-state line, held by the runtime.
    let emptyPhrase: String

    private var candidates: [MilestoneCandidate] {
        MilestoneBoard.shortlist(from: members.map { ($0.name, $0.lifetimeRuns) })
    }

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
        }
    }
}

private struct MilestoneRow: View {
    let candidate: MilestoneCandidate

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(candidate.name)
                .font(.body)
            Spacer(minLength: 12)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                // Digits keep their column as the numbers change.
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(candidate.name), \(detail)")
    }

    private var detail: String {
        let runs = candidate.runsNeeded == 1 ? "1 run" : "\(candidate.runsNeeded) runs"
        return "\(runs) to \(candidate.milestone)"
    }
}
