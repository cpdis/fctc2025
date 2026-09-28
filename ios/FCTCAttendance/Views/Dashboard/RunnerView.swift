//
//  RunnerView.swift
//  FCTCAttendance
//
//  One runner's season (R25): runs, km and current streak; a club-day calendar
//  with the streak marked; club days made per weekday; and the all-time total
//  with the next milestone. `DashboardModel` built every value; this only draws:
//
//    Season    Jan  Feb  ...  Sep       one column per week, one row per club
//      M       ■ ■ ▢ ■ ■ ...  ■ ■ ■     weekday (2025: W and F only). Accent
//      W       ■ ■ ■ ■ ▢ ...  ■ ■ ■     marks the current streak.
//      F       ■ ▢ ■ ■ ■ ...  ■ ■ ■
//

import Charts
import FCTCAttendanceKit
import SwiftUI

struct RunnerView: View {
    let name: String
    /// Nil when the runner has no run this season (or left the data).
    let detail: RunnerDetail?
    /// The season's run count, for "29 of 30 runs".
    let seasonRuns: Int
    let accent: Color

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if let detail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("#\(detail.rank) on runs · \(detail.runs) of \(DashboardFormat.runs(seasonRuns))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .accessibilityIdentifier("runner-summary")
                        stats(detail)
                        SeasonCalendarCard(detail: detail, accent: accent)
                        ByDayCard(record: detail.record)
                        AllTimeCard(detail: detail, accent: accent)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            } else {
                ContentUnavailableView("No Runs This Season", systemImage: "figure.run",
                                       description: Text("\(name) has no recorded run this season."))
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(name)
    }

    private func stats(_ detail: RunnerDetail) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            RunnerStat(title: "Runs", value: detail.runs.formatted(), tint: .primary)
                .accessibilityIdentifier("runner-runs")
            RunnerStat(title: "Km", value: DashboardFormat.km(detail.memberKm), tint: .primary)
                .accessibilityIdentifier("runner-km")
            RunnerStat(title: "Streak", value: String(detail.record.current), tint: accent)
                .accessibilityIdentifier("runner-streak")
        }
    }
}

/// A label over a big rounded number.
private struct RunnerStat: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            StatLabel(text: title)
            Text(value)
                .font(.system(.title, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .dashboardCardStyle()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}

/// Every club day of the season on a week-by-weekday grid.
private struct SeasonCalendarCard: View {
    let detail: RunnerDetail
    let accent: Color

    @ScaledMetric(relativeTo: .caption) private var rowHeight: CGFloat = 22

    /// One club day placed on the grid.
    private struct Cell: Identifiable {
        let day: RunnerDay
        /// Weeks since the Monday of the season's first club day.
        let week: Int
        var id: ClubDate { day.date }
    }

    var body: some View {
        let cells = self.cells
        let weeks = (cells.map(\.week).max() ?? 0) + 1
        let months = monthStarts(cells)
        let weekdays = detail.record.byWeekday.map(\.weekday)
        DashboardCard("Season", summary: summary) {
            Text(range)
        } content: {
            // Weekday initials in a column beside the plot, one per band, as
            // the Wall's names are: a visible categorical y-axis squeezes the
            // bands into thin lines.
            HStack(alignment: .top, spacing: 6) {
                VStack(spacing: 0) {
                    ForEach(weekdays, id: \.self) { weekday in
                        Text(weekday.shortName.prefix(1))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(height: rowHeight)
                    }
                }
                .accessibilityHidden(true)

                Chart(cells) { cell in
                    RectangleMark(
                        xStart: .value("Week", Double(cell.week) + 0.1),
                        xEnd: .value("Week", Double(cell.week) + 0.9),
                        y: .value("Day", cell.day.date.weekday.shortName),
                        height: .ratio(0.8)
                    )
                    .foregroundStyle(cell.day.inStreak ? accent : cell.day.made ? Color.primary : Color(.tertiarySystemFill))
                    .cornerRadius(2)
                    .accessibilityLabel(DashboardFormat.day(cell.day.date))
                    .accessibilityValue(cell.day.inStreak ? "Made, in the current streak" : cell.day.made ? "Made" : "Missed")
                }
                .chartXScale(domain: 0...Double(weeks))
                .chartYScale(domain: weekdays.map(\.shortName))
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks(values: months.map(\.week)) { value in
                        AxisValueLabel(collisionResolution: .greedy) {
                            if let week = value.as(Double.self), let month = months.first(where: { $0.week == week }) {
                                Text(month.name)
                            }
                        }
                    }
                }
                .chartPlotStyle { $0.frame(height: CGFloat(weekdays.count) * rowHeight) }
            }

            Text(caption)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var cells: [Cell] {
        guard let firstMonday = detail.calendar.first?.date.startOfWeek.perthNoon else { return [] }
        return detail.calendar.compactMap { day in
            guard let monday = day.date.startOfWeek.perthNoon,
                  let days = BirthdayBoard.calendar.dateComponents([.day], from: firstMonday, to: monday).day
            else { return nil }
            return Cell(day: day, week: days / 7)
        }
    }

    /// The week each month's first club day falls in, and the month's name.
    /// The name comes from that club day, not the week's Monday, which can
    /// still be in the month before.
    private func monthStarts(_ cells: [Cell]) -> [(week: Double, name: String)] {
        var seen: Set<Int> = []
        return cells.compactMap { cell in
            guard seen.insert(cell.day.date.month).inserted else { return nil }
            return (Double(cell.week), cell.day.date.formatted(Date.FormatStyle.perth.month(.abbreviated)))
        }
    }

    /// "Jan – Sep".
    private var range: String {
        let months = [detail.calendar.first, detail.calendar.last].compactMap {
            $0?.date.formatted(Date.FormatStyle.perth.month(.abbreviated))
        }
        return months.count == 2 && months[0] != months[1] ? "\(months[0]) – \(months[1])" : months.first ?? ""
    }

    private var caption: String {
        let record = detail.record
        let best = "Best this season: \(record.best)."
        guard let from = record.currentFrom else { return "No current streak. \(best)" }
        return "Accent marks the current streak of \(record.current), since \(DashboardFormat.day(from)). \(best)"
    }

    private var summary: String {
        "Season calendar: \(detail.record.made) of \(detail.calendar.count) club days made. \(caption)"
    }
}

/// Club days made on each club weekday, against that weekday's club days.
/// One row per weekday on a shared scale, so a weekday with fewer club days
/// draws a shorter track.
private struct ByDayCard: View {
    let record: ClubDayRecord

    @ScaledMetric(relativeTo: .body) private var dayWidth: CGFloat = 36

    var body: some View {
        let most = max(record.byWeekday.map(\.clubDays).max() ?? 1, 1)
        DashboardCard("By day", summary: summary) {
            Text("Club days made")
        } content: {
            VStack(spacing: 10) {
                ForEach(record.byWeekday) { tally in
                    HStack(spacing: 10) {
                        Text(tally.weekday.shortName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(width: dayWidth, alignment: .leading)
                        Chart {
                            // The weekday's club days, then the ones made on top.
                            BarMark(xStart: .value("Club days", 0), xEnd: .value("Club days", tally.clubDays))
                                .foregroundStyle(Color(.tertiarySystemFill))
                                .cornerRadius(5)
                            BarMark(xStart: .value("Club days", 0), xEnd: .value("Club days", tally.made))
                                .foregroundStyle(Color.primary)
                                .cornerRadius(5)
                        }
                        .chartXScale(domain: 0...most)
                        .chartXAxis(.hidden)
                        .chartYAxis(.hidden)
                        .frame(height: 10)
                        Text("\(tally.made)/\(tally.clubDays)")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(tally.weekday.shortName)
                    .accessibilityValue("\(tally.made) of \(tally.clubDays) club days")
                }
            }
        }
    }

    private var summary: String {
        "By day: " + record.byWeekday.map { "\($0.weekday.shortName) \($0.made) of \($0.clubDays)" }.joined(separator: ", ")
    }
}

/// Prior seasons plus this one, and the way to the next landmark.
private struct AllTimeCard: View {
    let detail: RunnerDetail
    let accent: Color

    var body: some View {
        if let allTime = detail.allTime, let next = detail.nextMilestone {
            let togo = next - allTime
            DashboardCard("All time", summary: "All time: \(DashboardFormat.runs(allTime)), \(DashboardFormat.runs(togo)) to \(next)") {
                Text(DashboardFormat.runs(allTime))
            } content: {
                ProgressView(value: Double(MilestoneBoard.step - togo), total: Double(MilestoneBoard.step))
                    .tint(accent)
                    .accessibilityHidden(true)
                Text("\(DashboardFormat.runs(togo)) to \(next)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("runner-all-time")
        } else {
            DashboardCard("All time", summary: "All time: not available yet") {
                Text("All-time totals are not available yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("runner-all-time")
        }
    }
}
