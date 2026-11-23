//
//  BeenAWhileCard.swift
//  FCTCAttendance
//
//  "Been a while…" (Grant, 23 Nov 2026): members who ran in the last 12 weeks
//  but not the last 4, so organisers can nudge them. The kit's `BeenAWhile`
//  decided who, in what order, and which weeks they ran; this only draws.
//  Colin picked the week strip over a dated list and name chips:
//
//    Been a while…                Last 12 weeks
//    Liam   ■ ■ ■ ■ ■ ■ ■ ■ □ □ □ □   4 wk     ■ ran that week (as The Wall)
//    Rhys   ■ □ ■ ■ ■ □ ■ □ □ □ □ □   6 wk     □ no run
//    Jack   □ ■ ■ □ □ □ □ □ □ □ □ □   9 wk
//
//  The strip tells a regular who stopped (Liam) from a one-off visitor (Jack).
//  Each row opens the runner screen.
//

import FCTCAttendanceKit
import SwiftUI

struct BeenAWhileCard: View {
    let runners: [BeenAWhile.Runner]

    var body: some View {
        DashboardCard("Been a while…", summary: summary) {
            Text("Last 12 weeks")
        } content: {
            VStack(spacing: 8) {
                ForEach(runners) { runner in
                    NavigationLink(value: DashboardRoute.runner(runner.name)) {
                        BeenAWhileRow(runner: runner)
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel(runner.name)
                    .accessibilityValue(Self.spoken(runner))
                    .accessibilityHint("Opens \(runner.name)'s runs")
                    .accessibilityIdentifier("been-a-while-row-\(runner.name)")
                }
            }
        }
        .accessibilityIdentifier("been-a-while")
    }

    /// "Been a while: 3 members have not run in 4 weeks".
    private var summary: String {
        let members = runners.count == 1 ? "1 member has" : "\(runners.count) members have"
        return "Been a while: \(members) not run in 4 weeks"
    }

    /// "Last run Wed 21 Oct, 4 weeks ago, 9 runs in 12 weeks".
    private static func spoken(_ runner: BeenAWhile.Runner) -> String {
        "Last run \(DashboardFormat.day(runner.lastRun)), \(runner.weeksAway) weeks ago, "
            + "\(DashboardFormat.runs(runner.runs)) in 12 weeks"
    }
}

/// Name, the twelve-week strip and weeks away; the name sits over the strip
/// at accessibility sizes, as the Leaderboard's rows do.
private struct BeenAWhileRow: View {
    let runner: BeenAWhile.Runner

    @ScaledMetric(relativeTo: .body) private var nameWidth: CGFloat = 76
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(runner.name)
                        Spacer(minLength: 8)
                        weeksAway
                    }
                    WeekStrip(weeks: runner.weeks)
                }
            } else {
                HStack(spacing: 10) {
                    Text(runner.name)
                        .lineLimit(1)
                        .frame(width: nameWidth, alignment: .leading)
                    WeekStrip(weeks: runner.weeks)
                    weeksAway
                        .frame(minWidth: 40, alignment: .trailing)
                }
            }
        }
        .foregroundStyle(.primary)
        .padding(.vertical, 2)
        .contentShape(.rect)
    }

    /// "4 wk".
    private var weeksAway: some View {
        Text("\(runner.weeksAway) wk")
            .font(.system(.subheadline, design: .rounded, weight: .bold))
            .monospacedDigit()
    }
}

/// One cell per week, oldest first, in The Wall's colours: primary where they
/// ran, the faint fill where they did not.
private struct WeekStrip: View {
    let weeks: [Bool]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(weeks.indices, id: \.self) { index in
                RoundedRectangle(cornerRadius: 3)
                    .fill(weeks[index] ? AnyShapeStyle(.primary) : AnyShapeStyle(Color(.tertiarySystemFill)))
                    .frame(height: 14)
            }
        }
        .accessibilityHidden(true)
    }
}
