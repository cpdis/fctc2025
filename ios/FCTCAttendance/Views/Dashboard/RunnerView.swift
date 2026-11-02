//
//  RunnerView.swift
//  FCTCAttendance
//
//  One runner's season (R25): runs, km and current streak; club days made since
//  their first run in any season; a club-day calendar with the streak marked;
//  club days made per weekday; and the all-time total with the next milestone.
//  `DashboardModel` and `FirstRuns` built every value; this only draws:
//
//    Season    Jan  Feb  ...  Sep       one column per week, one row per club
//      M       ■ ■ ▢ ■ ■ ...  ■ ■ ■     weekday (2025: W and F only). Accent
//      W       ■ ■ ■ ■ ▢ ...  ■ ■ ■     marks the current streak.
//      F       ■ ▢ ■ ■ ■ ...  ■ ■ ■
//
//  All time stacks one calendar per season, newest first (Colin's call), so
//  each keeps a season's width and its own weekday rows.
//

import Charts
import FCTCAttendanceKit
import SwiftUI

struct RunnerView: View {
    let name: String
    /// Nil when the runner has no run this season (or left the data).
    let detail: RunnerDetail?
    /// The view's run count, for "29 of 30 runs".
    let seasonRuns: Int
    let period: DashboardPeriod?
    /// Club days since their first run in any season; nil when that run is
    /// not in the data (runs before the earliest season).
    let firstRun: FirstRun?
    let accent: Color

    @Environment(\.dynamicTypeSize) private var typeSize

    /// The runner's screen as the Dashboard store shows it now: the season or
    /// All time picked in the Dashboard's menu. Dashboard and Events push it.
    init(name: String, store: DashboardStore, accent: Color) {
        self.name = name
        detail = store.model?.runners[name]
        seasonRuns = store.model?.runs.count ?? 0
        period = store.model?.period
        firstRun = store.firstRuns[name]
        self.accent = accent
    }

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
                        if let firstRun {
                            FirstRunCard(firstRun: firstRun, accent: accent)
                        }
                        calendars(detail)
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

    /// One calendar for a season; for All time, one per season, newest first.
    /// The newest card carries the streak sentence, whichever season the
    /// streak started in (the accent marks it on every card).
    @ViewBuilder private func calendars(_ detail: RunnerDetail) -> some View {
        let record = detail.record
        let streak = record.currentFrom.map {
            "Accent marks the current streak of \(record.current), since \(DashboardFormat.day($0))."
        } ?? "No current streak."
        if period == .allTime {
            let seasons = detail.calendarBySeason
            ForEach(seasons, id: \.season) { season in
                let made = season.days.count(where: \.made)
                let tally = "Made \(made) of \(season.days.count) club days."
                SeasonCalendarCard(
                    title: String(season.season),
                    days: season.days,
                    caption: season.season == seasons.first?.season
                        ? "\(streak) Longest: \(record.best). \(tally)" : tally,
                    accent: accent
                )
                .accessibilityIdentifier("runner-calendar-\(season.season)")
            }
        } else {
            SeasonCalendarCard(title: "Season", days: detail.calendar,
                               caption: "\(streak) Best this season: \(record.best).", accent: accent)
                .accessibilityIdentifier("runner-calendar")
        }
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

/// Every club day of one season on a week-by-weekday grid.
private struct SeasonCalendarCard: View {
    /// "Season", or the season's year in All time.
    let title: String
    /// The season's club days, oldest first.
    let days: [RunnerDay]
    let caption: String
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
        // This season's club weekdays (2025 had no Monday row).
        let weekdays = Set(days.map(\.date.weekday)).sorted()
        DashboardCard(title, summary: summary) {
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
        guard let firstMonday = days.first?.date.startOfWeek.perthNoon else { return [] }
        return days.compactMap { day in
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
        let months = [days.first, days.last].compactMap {
            $0?.date.formatted(Date.FormatStyle.perth.month(.abbreviated))
        }
        return months.count == 2 && months[0] != months[1] ? "\(months[0]) – \(months[1])" : months.first ?? ""
    }

    private var summary: String {
        "\(title) calendar: \(days.count(where: \.made)) of \(days.count) club days made. \(caption)"
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

/// Club days made since the runner's first run in any season (Grant's build 14
/// feedback): the fair all-time rate for someone who joined part way through,
/// whatever season the screen shows.
private struct FirstRunCard: View {
    let firstRun: FirstRun
    let accent: Color

    var body: some View {
        // "62%".
        let rate = (Double(firstRun.made) / Double(max(firstRun.clubDays, 1)))
            .formatted(.percent.precision(.fractionLength(0)))
        // With the year: the first run can be in an earlier season.
        let day = firstRun.date.formatted(Date.FormatStyle.perth.weekday(.abbreviated).day().month(.abbreviated).year())
        let tally = "Made \(firstRun.made) of \(firstRun.clubDays) club days since \(day)."
        DashboardCard("Since first run", summary: "Since first run: \(rate). \(tally)") {
            Text(rate)
        } content: {
            ProgressView(value: Double(firstRun.made), total: Double(max(firstRun.clubDays, 1)))
                .tint(accent)
                .accessibilityHidden(true)
            Text(tally)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("runner-first-run")
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
