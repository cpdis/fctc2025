//
//  DashboardCharts.swift
//  FCTCAttendance
//
//  The Dashboard's lower chart cards, in Swift Charts:
//
//    Vs last year   LineMark per season, cumulative member-km on a Jan..Dec axis
//    Every run      BarMark per recent run: members, then guests stacked on top
//    Leaderboard    one BarMark per row, by runs or member-km
//
//  Split from DashboardCards.swift to keep each file small; the chrome
//  (`DashboardCard`, `DashboardFormat`) lives there.
//

import Charts
import FCTCAttendanceKit
import SwiftUI

// MARK: - Vs last year

/// This season's cumulative member-km against last season's (R14 on the web).
struct VsLastYearCard: View {
    let progress: SeasonProgress
    let accent: Color

    /// Day-of-year starts of Jan, Apr, Jul and Oct.
    private static let quarterStarts = [0, 90, 181, 273]
    private static let quarterNames = ["Jan", "Apr", "Jul", "Oct"]

    var body: some View {
        let current = String(progress.current.year)
        let previous = String(progress.previous.year)
        DashboardCard("Vs last year", summary: summary) {
            Text("\(DashboardFormat.km(currentTotal)) vs \(DashboardFormat.km(progress.previousAtLatest)) km")
        } content: {
            Chart {
                ForEach(progress.previous.points) { point in
                    LineMark(x: .value("Day", point.dayOfYear), y: .value("Km", point.memberKm))
                        .foregroundStyle(by: .value("Season", previous))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .accessibilityLabel("\(previous), \(DashboardFormat.day(point.date))")
                        .accessibilityValue("\(DashboardFormat.km(point.memberKm)) km")
                }
                ForEach(progress.current.points) { point in
                    LineMark(x: .value("Day", point.dayOfYear), y: .value("Km", point.memberKm))
                        .foregroundStyle(by: .value("Season", current))
                        .lineStyle(StrokeStyle(lineWidth: 3, lineJoin: .round))
                        .accessibilityLabel("\(current), \(DashboardFormat.day(point.date))")
                        .accessibilityValue("\(DashboardFormat.km(point.memberKm)) km")
                }
                if let latest = progress.current.points.last {
                    PointMark(x: .value("Day", latest.dayOfYear), y: .value("Km", latest.memberKm))
                        .foregroundStyle(accent)
                        .symbolSize(70)
                        .accessibilityHidden(true)
                }
            }
            .chartForegroundStyleScale(domain: [current, previous], range: [accent, Color.secondary])
            .chartLegend(position: .bottom, alignment: .leading)
            .chartXScale(domain: 0...365)
            .chartXAxis {
                AxisMarks(values: Self.quarterStarts) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let day = value.as(Int.self), let index = Self.quarterStarts.firstIndex(of: day) {
                            Text(Self.quarterNames[index])
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: FloatingPointFormatStyle<Double>.number.notation(.compactName))
                }
            }
            .frame(height: 150)
        }
        .accessibilityIdentifier("vs-last-year")
    }

    private var currentTotal: Double {
        progress.current.points.last?.memberKm ?? 0
    }

    private var summary: String {
        "Vs last year: \(DashboardFormat.km(currentTotal)) km together this season, against \(DashboardFormat.km(progress.previousAtLatest)) km by the same date in \(String(progress.previous.year))"
    }
}

// MARK: - Every run

/// Everyone on each recent run: members, with guests stacked lighter on top.
/// The busiest run takes the accent.
struct EveryRunCard: View {
    let runs: [DashboardRun]
    let accent: Color

    /// Runs the card shows (the approved mockup).
    static let count = 18

    var body: some View {
        let busiest = runs.max { $0.run.headcount < $1.run.headcount }
        DashboardCard("Every run", summary: summary(busiest: busiest)) {
            Text("Runners · last \(runs.count)")
        } content: {
            Chart(runs) { entry in
                let tint = entry.id == busiest?.id ? accent : Color.primary
                BarMark(x: .value("Run", entry.id), y: .value("Runners", entry.run.attendees.count), width: .ratio(0.7))
                    .foregroundStyle(tint)
                    .accessibilityLabel(DashboardFormat.run(entry))
                    .accessibilityValue("\(entry.run.attendees.count) members, \(entry.run.plusOnes) guests")
                BarMark(x: .value("Run", entry.id), y: .value("Runners", entry.run.plusOnes), width: .ratio(0.7))
                    .foregroundStyle(tint.opacity(0.35))
                    .accessibilityHidden(true)
            }
            .chartXScale(domain: runs.map(\.id))
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let id = value.as(String.self), let entry = runs.first(where: { $0.id == id }) {
                            // The weekday's initial: M W F, S for a weekend special.
                            Text(String(entry.run.weekday.shortName.prefix(1)))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .frame(height: 130)

            if let busiest {
                Text("Busiest: \(DashboardFormat.day(busiest.run.date)), \(busiest.run.headcount) runners. Lighter tops are guests.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("every-run")
    }

    private func summary(busiest: DashboardRun?) -> String {
        guard let busiest else { return "Every run" }
        return "Every run: the last \(runs.count) runs. The busiest was \(DashboardFormat.day(busiest.run.date)) with \(busiest.run.headcount) runners"
    }
}

// MARK: - Leaderboard

/// The season's top runners by runs or member-km. A row opens its runner.
struct LeaderboardCard: View {
    let leaderboard: Leaderboard
    let accent: Color

    enum Metric: String, CaseIterable, Identifiable {
        case runs = "Runs"
        case km = "Km"
        var id: Self { self }
    }

    /// Rows the card shows (the approved mockup).
    static let places = 5

    @State private var metric = Metric.runs

    var body: some View {
        let entries = Array((metric == .runs ? leaderboard.byRuns : leaderboard.byKm).prefix(Self.places))
        let top = entries.first.map(value) ?? 1
        DashboardCard("Leaderboard", summary: "Leaderboard by \(metric.rawValue.lowercased())") {
            Picker("Rank by", selection: $metric.animation(Motion.snappy)) {
                ForEach(Metric.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .accessibilityIdentifier("leaderboard-metric")
        } content: {
            VStack(spacing: 4) {
                ForEach(entries) { entry in
                    // Competition ranking: equal values share a place.
                    let rank = 1 + entries.count { value($0) > value(entry) }
                    NavigationLink(value: DashboardRoute.runner(entry.name)) {
                        LeaderRow(rank: rank, name: entry.name, value: value(entry), top: top,
                                  valueText: shortLabel(entry), accent: accent)
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("\(rank), \(entry.name)")
                    .accessibilityValue(label(entry))
                    .accessibilityIdentifier("leaderboard-row-\(entry.name)")
                }
            }
        }
    }

    private func value(_ entry: LeaderboardEntry) -> Double {
        metric == .runs ? Double(entry.runs) : entry.memberKm
    }

    /// "29 runs" or "412 km", as VoiceOver reads the row.
    private func label(_ entry: LeaderboardEntry) -> String {
        metric == .runs ? DashboardFormat.runs(entry.runs) : shortLabel(entry)
    }

    /// "29" or "412 km", as the row prints it.
    private func shortLabel(_ entry: LeaderboardEntry) -> String {
        metric == .runs ? entry.runs.formatted() : "\(DashboardFormat.km(entry.memberKm)) km"
    }
}

/// Rank, name, a bar against the leader, and the value.
private struct LeaderRow: View {
    let rank: Int
    let name: String
    let value: Double
    let top: Double
    let valueText: String
    let accent: Color

    @ScaledMetric(relativeTo: .body) private var nameWidth: CGFloat = 92

    var body: some View {
        HStack(spacing: 10) {
            Text(rank, format: .number)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(minWidth: 22, alignment: .leading)
            Text(name)
                .lineLimit(1)
                .frame(width: nameWidth, alignment: .leading)
            Chart {
                // An x-only bar fills the chart's height: the 10 pt frame below.
                BarMark(x: .value("Value", value))
                    .foregroundStyle(rank == 1 ? accent : Color.primary)
                    .cornerRadius(5)
            }
            .chartXScale(domain: 0...max(top, 1))
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 10)
            .accessibilityHidden(true)
            Text(valueText)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
        .foregroundStyle(.primary)
        .padding(.vertical, 4)
        .contentShape(.rect)
    }
}
