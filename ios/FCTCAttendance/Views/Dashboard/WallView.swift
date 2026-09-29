//
//  WallView.swift
//  FCTCAttendance
//
//  The Wall (R24): runners against runs. The card and the full screen share
//  `WallGrid`. Names are real buttons in a column beside the grid, one row per
//  grid band, so they stay put while the full Wall scrolls sideways and
//  VoiceOver can reach every runner:
//
//    names (NavigationLinks)   Canvas (every cell, drawn in one pass)
//    ┌──────────────┐ ┌─────────────────────────────────────────┐
//    │ Aaron     14 │ │ ■ ■ ■ ▢ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ │ ← scrolls on the
//    │ Col       10 │ │ ■ ■ ■ ■ ■ ■ ▢ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ ■ │   full Wall, opening
//    └──────────────┘ └─────────────────────────────────────────┘   at the latest run
//
//  A Canvas, not Swift Charts: a season is ~30 runners × ~118 runs, and one
//  RectangleMark per cell cost ~550 ms of main thread per open or sort
//  (profiled at full size in Release). The Canvas fills one path per colour.
//
//  Tapping a cell opens its runner: the tap's y picks the row. Streak cells use
//  the accent, other runs the label colour.
//

import FCTCAttendanceKit
import SwiftUI

/// Runners against runs. Row `i` of the name column sits on grid band `i`.
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

    /// The full Wall's date band above the first row.
    private var dateBand: CGFloat { isFull ? rowHeight : 0 }
    private var gridHeight: CGFloat { dateBand + CGFloat(rows.count) * rowHeight }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            names
                .padding(.top, dateBand)
            GeometryReader { proxy in
                let shown = isFull ? min(columns.count, Self.visibleColumns) : columns.count
                let columnWidth = proxy.size.width / CGFloat(max(shown, 1))
                if isFull {
                    ScrollView(.horizontal, showsIndicators: false) {
                        grid(columnWidth: columnWidth)
                    }
                    .defaultScrollAnchor(.trailing)
                } else {
                    grid(columnWidth: columnWidth)
                }
            }
            .frame(height: gridHeight)
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

    /// Every cell, the full Wall's dates and its special stripes, in one Canvas.
    private func grid(columnWidth: CGFloat) -> some View {
        Canvas { context, size in
            let top = dateBand
            // A faint stripe behind each special: off the club days, it
            // neither adds to nor breaks a streak (R11).
            if isFull {
                var stripes = Path()
                for (position, index) in columns.enumerated() where wall.columns[index].isSpecial {
                    stripes.addRect(CGRect(x: CGFloat(position) * columnWidth, y: top, width: columnWidth, height: size.height - top))
                }
                context.fill(stripes, with: .color(accent.opacity(0.14)))
                // A date on each week's first column; one that would touch the
                // previous date is skipped (large text, narrow columns).
                var lastEnd = -CGFloat.infinity
                for position in weekStarts {
                    let label = context.resolve(
                        Text(wall.columns[columns[position]].run.date.formatted(Date.FormatStyle.perth.day().month(.abbreviated)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    )
                    let width = label.measure(in: size).width
                    let center = (CGFloat(position) + 0.5) * columnWidth
                    guard center - width / 2 >= lastEnd + 4 else { continue }
                    context.draw(label, at: CGPoint(x: center, y: top / 2))
                    lastEnd = center + width / 2
                }
            }
            // One path per colour, so the whole grid is three fills.
            var paths: [WallMark: Path] = [:]
            let cellWidth = columnWidth * 0.8
            let cellHeight = rowHeight * 0.78
            for (r, row) in rows.enumerated() {
                let y = top + CGFloat(r) * rowHeight + (rowHeight - cellHeight) / 2
                for (position, index) in columns.enumerated() {
                    let mark = row.cells[index]
                    // A special nobody expects you at is not a miss: leave it blank.
                    if mark == .missed && wall.columns[index].isSpecial { continue }
                    let cell = CGRect(x: CGFloat(position) * columnWidth + columnWidth * 0.1, y: y, width: cellWidth, height: cellHeight)
                    paths[mark, default: Path()].addRoundedRect(in: cell, cornerSize: CGSize(width: 2.5, height: 2.5))
                }
            }
            for (mark, path) in paths {
                context.fill(path, with: .color(color(for: mark)))
            }
        }
        .frame(width: columnWidth * CGFloat(columns.count), height: gridHeight)
        .contentShape(.rect)
        .onTapGesture { location in
            let row = Int((location.y - dateBand) / rowHeight)
            if location.y >= dateBand, rows.indices.contains(row) { open(rows[row].name) }
        }
        // The names column carries each runner for VoiceOver (a button that
        // opens their runs); the grid reads as one summary.
        .accessibilityElement()
        .accessibilityLabel("Attendance grid")
        .accessibilityValue("\(rows.count) runners, \(columns.count) runs")
        .accessibilityHint("Choose a runner's name to see their runs.")
        .accessibilityIdentifier(isFull ? "wall-grid" : "wall-card-grid")
    }

    /// The first column of each week, where the full Wall prints a date.
    private var weekStarts: [Int] {
        columns.indices.filter { position in
            position == 0 || wall.columns[columns[position]].run.date.startOfWeek
                != wall.columns[columns[position - 1]].run.date.startOfWeek
        }
    }

    private func color(for mark: WallMark) -> Color {
        switch mark {
        case .missed: Color(.tertiarySystemFill)
        case .ran: Color.primary
        case .streak: accent
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
