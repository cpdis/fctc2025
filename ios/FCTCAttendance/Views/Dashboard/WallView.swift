//
//  WallView.swift
//  FCTCAttendance
//
//  The Wall (R24): runners against runs, one RectangleMark per cell. The card
//  and the full screen share `WallGrid`. Names are real buttons in a column
//  beside the chart, one row per plot band, so they stay put while the full
//  Wall scrolls sideways and VoiceOver can reach every runner:
//
//    names (NavigationLinks)   Chart (RectangleMark per cell)
//    ┌──────────────┐ ┌─────────────────────────────────────────┐
//    │ Aaron     14 │ │ ■ ■ ■ ▢ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ │ ← scrolls on the
//    │ Col       10 │ │ ■ ■ ■ ■ ■ ■ ▢ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ │   full Wall, opening
//    └──────────────┘ └─────────────────────────────────────────┘   at the latest run
//
//  Tapping a cell opens its runner too: a spatial tap reads the runner from the
//  plot's y value. Streak cells use the accent, other runs the label colour.
//

import Charts
import FCTCAttendanceKit
import SwiftUI

/// Runners against runs. Row `i` of the name column sits on plot band `i`.
struct WallGrid: View {
    let wall: Wall
    /// The rows to draw, in drawing order.
    let rows: [WallRow]
    /// Indices into `wall.columns`, oldest first.
    let columns: [Int]
    let accent: Color
    /// The full Wall: dates on top, sideways scrolling, specials shaded.
    let isFull: Bool
    let open: (String) -> Void

    /// Columns the full Wall shows at once: about five weeks of club days.
    static let visibleColumns = 16

    @ScaledMetric(relativeTo: .caption) private var rowHeight: CGFloat = 22
    @ScaledMetric(relativeTo: .caption) private var nameWidth: CGFloat = 104
    /// Where the plot starts inside the chart: below the dates on the full Wall.
    @State private var plotTop: CGFloat = 0

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            names
                .padding(.top, plotTop)
            chart
        }
    }

    private var names: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { row in
                NavigationLink(value: DashboardRoute.runner(row.name)) {
                    HStack(spacing: 4) {
                        Text(row.name)
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        if row.current > 0 {
                            Text(row.current, format: .number)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                                .foregroundStyle(accent)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .frame(height: rowHeight)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(row.name)
                .accessibilityValue("\(DashboardFormat.runs(row.runs)), streak \(row.current)")
                .accessibilityIdentifier("\(isFull ? "wall" : "wall-card")-runner-\(row.name)")
            }
        }
        .frame(width: nameWidth)
    }

    private var chart: some View {
        // Formatted once per render, not once per mark.
        let labels = columns.map { DashboardFormat.day(wall.columns[$0].run.date) }
        let positions = Array(columns.enumerated())
        return Chart {
            if isFull {
                // A faint stripe behind each special: off the club days, it
                // neither adds to nor breaks a streak (R11).
                ForEach(positions, id: \.offset) { position, index in
                    if wall.columns[index].isSpecial {
                        RectangleMark(xStart: .value("Run", Double(position)), xEnd: .value("Run", Double(position + 1)))
                            .foregroundStyle(accent.opacity(0.14))
                            .accessibilityHidden(true)
                    }
                }
            }
            ForEach(rows) { row in
                ForEach(positions, id: \.offset) { position, index in
                    let mark = row.cells[index]
                    // A special nobody expects you at is not a miss: leave it blank.
                    if mark != .missed || !wall.columns[index].isSpecial {
                        RectangleMark(
                            xStart: .value("Run", Double(position) + 0.1),
                            xEnd: .value("Run", Double(position) + 0.9),
                            y: .value("Runner", row.name),
                            height: .ratio(0.78)
                        )
                        .foregroundStyle(color(for: mark))
                        .cornerRadius(2.5)
                        .accessibilityLabel("\(row.name), \(labels[position])")
                        .accessibilityValue(description(of: mark))
                    }
                }
            }
        }
        .chartXScale(domain: 0...Double(max(columns.count, 1)))
        .chartYScale(domain: rows.map(\.name))
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(position: .top, values: weekStarts) { value in
                AxisValueLabel(collisionResolution: .greedy) {
                    if let position = value.as(Double.self).map({ Int($0) }), labels.indices.contains(position) {
                        Text(wall.columns[columns[position]].run.date.formatted(Date.FormatStyle.perth.day().month(.abbreviated)))
                    }
                }
            }
        }
        .chartXAxis(isFull ? .visible : .hidden)
        .chartPlotStyle { $0.frame(height: CGFloat(rows.count) * rowHeight) }
        .chartGesture { proxy in
            SpatialTapGesture().onEnded { tap in
                if let name = proxy.value(atY: tap.location.y, as: String.self) { open(name) }
            }
        }
        .modifier(WallScrolling(isEnabled: isFull, columns: columns.count))
        // The name column must start where the plot does.
        .chartBackground { proxy in
            GeometryReader { geometry in
                let top = proxy.plotFrame.map { geometry[$0].minY } ?? 0
                Color.clear
                    .onAppear { plotTop = top }
                    .onChange(of: top) { _, top in plotTop = top }
            }
        }
    }

    /// The first column of each week, where the full Wall prints a date.
    private var weekStarts: [Double] {
        columns.indices.filter { position in
            position == 0 || wall.columns[columns[position]].run.date.startOfWeek
                != wall.columns[columns[position - 1]].run.date.startOfWeek
        }
        .map { Double($0) + 0.5 }
    }

    private func color(for mark: WallMark) -> Color {
        switch mark {
        case .missed: Color(.tertiarySystemFill)
        case .ran: Color.primary
        case .streak: accent
        }
    }

    private func description(of mark: WallMark) -> String {
        switch mark {
        case .missed: "Missed"
        case .ran: "Ran"
        case .streak: "Ran, in the current streak"
        }
    }
}

/// Sideways scrolling for the full Wall, opening at the latest run.
private struct WallScrolling: ViewModifier {
    let isEnabled: Bool
    let columns: Int

    func body(content: Content) -> some View {
        if isEnabled {
            let visible = min(columns, WallGrid.visibleColumns)
            content
                .chartScrollableAxes(.horizontal)
                .chartXVisibleDomain(length: Double(max(visible, 1)))
                .chartScrollPosition(initialX: Double(columns - visible))
        } else {
            content
        }
    }
}

/// What each colour means.
struct WallLegend: View {
    let accent: Color
    let showsSpecials: Bool

    var body: some View {
        HStack(spacing: 14) {
            key("Streak", accent)
            key("Ran", .primary)
            key("Missed", Color(.tertiarySystemFill))
            if showsSpecials { key("Special", accent.opacity(0.14)) }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    private func key(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(title)
        }
    }
}

/// Every runner against every run of the season.
struct WallView: View {
    /// Nil or empty before the season has a run.
    let wall: Wall?
    let accent: Color
    let open: (String) -> Void

    enum Order: String, CaseIterable, Identifiable {
        case runs = "Runs"
        case streak = "Streak"
        case name = "Name"
        var id: Self { self }
    }

    @State private var order = Order.runs

    var body: some View {
        Group {
            if let wall, !wall.columns.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Every runner against every run this season, latest on the right. Shaded columns are specials: off the club days, they never break a streak.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 12) {
                            WallGrid(wall: wall, rows: sorted(wall.rows), columns: Array(wall.columns.indices),
                                     accent: accent, isFull: true, open: open)
                            WallLegend(accent: accent, showsSpecials: true)
                        }
                        .dashboardCardStyle()
                    }
                    .padding(16)
                }
                .accessibilityIdentifier("wall-full")
            } else {
                ContentUnavailableView("No Runs Yet", systemImage: "square.grid.3x3",
                                       description: Text("The Wall fills in once a run is recorded."))
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("The Wall")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort by", selection: $order) {
                        ForEach(Order.allCases) { Text($0.rawValue).tag($0) }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .accessibilityIdentifier("wall-sort")
            }
        }
    }

    /// Runs order is the model's own (most runs, then name).
    private func sorted(_ rows: [WallRow]) -> [WallRow] {
        switch order {
        case .runs:
            rows
        case .streak:
            rows.enumerated()
                .sorted { ($1.element.current, $0.offset) < ($0.element.current, $1.offset) }
                .map(\.element)
        case .name:
            rows.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }
}
