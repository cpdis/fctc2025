//
//  DashboardCards.swift
//  FCTCAttendance
//
//  The Dashboard's top cards and the card chrome every card shares. The look is
//  the app's Reminders theme (R27): grouped-background cards, system colours,
//  the user's accent, SF Pro with numbers in SF Pro Rounded bold. The cards only
//  draw what `DashboardModel` already decided.
//
//    ┌ headline ─────────────── [Runs|Km] ┐
//    │ 30  RUNS THIS SEASON               │   accent card, runners per recent run
//    └────────────────────────────────────┘
//    ┌ Together ─────┐ ┌ On a roll ───────┐
//    ┌ The Wall ────────── Last 5 weeks › ┐   top runners x recent club days
//

import Charts
import FCTCAttendanceKit
import SwiftUI

// MARK: - Chrome

/// A titled grouped card. The title is a header for VoiceOver, and `summary`
/// names the whole card for anyone entering it.
struct DashboardCard<Accessory: View, Content: View>: View {
    let title: String
    let summary: String
    @ViewBuilder let accessory: Accessory
    @ViewBuilder let content: Content

    init(
        _ title: String,
        summary: String,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.summary = summary
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                accessory
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            content
        }
        .dashboardCardStyle()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(summary)
    }
}

extension DashboardCard where Accessory == EmptyView {
    init(_ title: String, summary: String, @ViewBuilder content: () -> Content) {
        self.init(title, summary: summary, accessory: { EmptyView() }, content: content)
    }
}

extension View {
    /// The grouped card surface. 26 pt matches the Home tiles and the
    /// inset-grouped section radius.
    func dashboardCardStyle() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 26))
    }
}

/// The small uppercase label over a stat ("TOGETHER").
struct StatLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.bold))
            .tracking(0.8)
            .foregroundStyle(.secondary)
    }
}

/// Number and date wording shared by every Dashboard screen.
enum DashboardFormat {
    /// Whole kilometres with grouping: "4,213".
    static func km(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }

    /// "+12", "−3" or "0".
    static func signed(_ value: Int) -> String {
        if value > 0 { return "+\(value.formatted())" }
        if value < 0 { return "−\((-value).formatted())" }
        return "0"
    }

    /// "Wed 23 Sep" in the device's own order.
    static func day(_ date: ClubDate) -> String {
        date.formatted(Date.FormatStyle.perth.weekday(.abbreviated).day().month(.abbreviated))
    }

    /// "Wed 23 Sep, Lakes Loop": how VoiceOver names one run.
    static func run(_ entry: DashboardRun) -> String {
        "\(day(entry.run.date)), \(entry.run.label.type)"
    }

    /// "1 run", "3 runs".
    static func runs(_ count: Int) -> String {
        count == 1 ? "1 run" : "\(count.formatted()) runs"
    }

    /// "1 runner", "12 runners": everyone on one run, +1s included.
    static func runners(_ count: Int) -> String {
        count == 1 ? "1 runner" : "\(count.formatted()) runners"
    }

    /// One run's distance to a tenth, "12.4 km"; nil when the sheet has none.
    static func distance(_ km: Double?) -> String? {
        km.map { "\($0.formatted(.number.precision(.fractionLength(0...1)))) km" }
    }
}

// MARK: - Headline

/// Runs or km this season on an accent card, the same-date comparison with
/// last season, and runners per recent run as columns.
struct HeadlineCard: View {
    let headline: Headline
    let recentRuns: [DashboardRun]
    let unsyncedCount: Int
    let accent: Color

    enum Metric: String, CaseIterable, Identifiable {
        case runs = "Runs"
        case km = "Km"
        var id: Self { self }
    }

    @State private var metric = Metric.runs
    /// Scales with Dynamic Type from a 60 pt headline number.
    @ScaledMetric(relativeTo: .largeTitle) private var numberSize: CGFloat = 60

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(value)
                        .font(.system(size: numberSize, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .contentTransition(.numericText())
                    Text(caption.uppercased())
                        .font(.caption.weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(caption)
                .accessibilityValue(value)
                .accessibilityIdentifier("headline-value")

                Spacer(minLength: 12)

                Picker("Headline", selection: $metric.animation(Motion.snappy)) {
                    ForEach(Metric.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .accessibilityIdentifier("headline-metric")
            }

            if let comparison {
                Text(comparison)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .accessibilityIdentifier("headline-comparison")
            }

            if unsyncedCount > 0 {
                Label("Includes \(unsyncedCount) unsynced", systemImage: "arrow.trianglehead.2.clockwise")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.22), in: .capsule)
                    // One element, so VoiceOver skips the symbol's own name.
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Includes \(unsyncedCount) unsynced")
                    .accessibilityIdentifier("dashboard-unsynced")
            }

            RunnersSparkline(runs: recentRuns)
                .frame(height: 64)

            Text("Runners per run · last \(recentRuns.count)".uppercased())
                .font(.caption.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.8))
                .accessibilityHidden(true)
        }
        .foregroundStyle(.white)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.gradient, in: .rect(cornerRadius: 26))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Headline")
    }

    private var value: String {
        switch metric {
        case .runs: headline.runs.formatted()
        case .km: "\(DashboardFormat.km(headline.memberKm)) km"
        }
    }

    private var caption: String {
        switch metric {
        case .runs: "Runs this season"
        case .km: "Km together this season"
        }
    }

    /// "+12 runs on 2025 by this date". Nil without a last season.
    private var comparison: String? {
        guard let vs = headline.vsPrevious else { return nil }
        let delta: String? = switch metric {
        case .runs: vs.runsDelta == 0 ? nil : "\(DashboardFormat.signed(vs.runsDelta)) runs"
        case .km: vs.memberKmDelta.rounded() == 0
            ? nil : "\(DashboardFormat.signed(Int(vs.memberKmDelta.rounded()))) km"
        }
        return delta.map { "\($0) on \(String(vs.year)) by this date" } ?? "Level with \(String(vs.year)) by this date"
    }
}

/// Everyone on each recent run (members and guests) as white columns; specials
/// are fainter, so the club days read as the rhythm.
private struct RunnersSparkline: View {
    let runs: [DashboardRun]

    var body: some View {
        Chart(runs) { entry in
            BarMark(x: .value("Run", entry.id), y: .value("Runners", entry.run.headcount), width: .ratio(0.7))
                .foregroundStyle(Color.white.opacity(entry.isSpecial ? 0.5 : 0.92))
                .cornerRadius(3)
                .accessibilityLabel(DashboardFormat.run(entry))
                .accessibilityValue("\(entry.run.headcount) runners")
        }
        .chartXScale(domain: runs.map(\.id))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .accessibilityLabel("Runners per run, last \(runs.count) runs")
    }
}

// MARK: - Together and On a roll

/// Member-km this season ("km together"), against last season by this date.
struct TogetherCard: View {
    let headline: Headline

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            StatLabel(text: "Together")
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(DashboardFormat.km(headline.memberKm))
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("km")
                    .font(.system(.title3, design: .rounded, weight: .bold))
            }
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .dashboardCardStyle()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Together")
        .accessibilityValue("\(DashboardFormat.km(headline.memberKm)) km, \(detail)")
        .accessibilityIdentifier("together")
    }

    private var detail: String {
        guard let vs = headline.vsPrevious else { return "Member-km this season" }
        return "\(DashboardFormat.signed(Int(vs.memberKmDelta.rounded()))) on \(String(vs.year))"
    }
}

/// The longest current club-day streak, its runner and the streak rule's
/// weekdays, with one square per club day. Opens that runner's screen.
struct OnARollCard: View {
    let onARoll: OnARoll
    let accent: Color

    /// Squares past this would wrap into a wall of their own.
    private static let maxSquares = 40

    var body: some View {
        if let leader = onARoll.current.first {
            NavigationLink(value: DashboardRoute.runner(leader.name)) {
                card(leader)
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("On a roll")
            .accessibilityValue("\(leader.name), \(leader.length) club days in a row")
            .accessibilityHint("Opens \(leader.name)'s runs")
            .accessibilityIdentifier("on-a-roll")
        } else {
            card(nil)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("on-a-roll")
        }
    }

    private func card(_ leader: StreakLine?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            StatLabel(text: "On a roll")
            Text(leader.map { String($0.length) } ?? "—")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(accent)
            Text(leader.map { "\($0.name) · \(weekdays)" } ?? "No current streaks")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if let leader {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 8, maximum: 8), spacing: 3)], alignment: .leading, spacing: 3) {
                    ForEach(0..<min(leader.length, Self.maxSquares), id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 2).fill(accent).frame(width: 8, height: 8)
                    }
                }
                .accessibilityHidden(true)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.primary)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .dashboardCardStyle()
    }

    /// "Mon/Wed/Fri": the weekdays the streak counts (2025: Wed/Fri).
    private var weekdays: String {
        onARoll.weekdays.map(\.shortName).joined(separator: "/")
    }
}

// MARK: - The Wall card

/// The top runners against the last five weeks of club days. Specials sit on
/// the full Wall, which the header opens.
struct WallCard: View {
    let wall: Wall
    let accent: Color
    let open: (String) -> Void

    /// Rows the card shows: the season's top runners by runs.
    static let rows = 10

    var body: some View {
        DashboardCard("The Wall", summary: summary) {
            NavigationLink(value: DashboardRoute.wall) {
                HStack(spacing: 3) {
                    Text("Last 5 weeks")
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                }
            }
            .accessibilityLabel("Open the full Wall")
            .accessibilityIdentifier("wall-open")
        } content: {
            if clubColumns.isEmpty {
                Text("No club days in the last five weeks.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                WallGrid(wall: wall, rows: Array(wall.rows.prefix(Self.rows)), columns: clubColumns,
                         accent: accent, isFull: false, open: open)
                WallLegend(accent: accent, showsSpecials: false)
            }
        }
        .accessibilityIdentifier("wall-card")
    }

    /// Club-day columns only, oldest first.
    private var clubColumns: [Int] {
        wall.columns.indices.filter { !wall.columns[$0].isSpecial }
    }

    private var summary: String {
        guard let first = clubColumns.first, let last = clubColumns.last else { return "The Wall" }
        let leader = wall.rows.max { $0.current < $1.current }
        let streak = leader.map { $0.current > 0 ? ". Longest streak: \($0.name), \($0.current)" : "" } ?? ""
        return "The Wall: top \(min(wall.rows.count, Self.rows)) runners, club days \(DashboardFormat.day(wall.columns[first].run.date)) to \(DashboardFormat.day(wall.columns[last].run.date))\(streak)"
    }
}

// MARK: - Run log and missing last season

/// The row that opens every run of the season.
struct RunLogLink: View {
    let count: Int

    var body: some View {
        NavigationLink(value: DashboardRoute.runLog) {
            HStack(spacing: 8) {
                HomeRow(
                    title: "Run log",
                    subtitle: count == 1 ? "1 run, searchable" : "All \(count) runs, searchable",
                    systemImage: "list.bullet",
                    tint: .gray
                )
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 26))
        }
        .buttonStyle(.pressable)
        .accessibilityIdentifier("dashboard-run-log")
    }
}

/// Vs last year while last season has never been downloaded (offline).
struct LastSeasonMissingCard: View {
    var body: some View {
        DashboardCard("Vs last year", summary: "Vs last year: last season not downloaded") {
            VStack(alignment: .leading, spacing: 4) {
                Label("Last season not downloaded", systemImage: "icloud.slash")
                    .font(.subheadline.weight(.semibold))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Last season not downloaded")
                    .accessibilityIdentifier("vs-last-year-not-downloaded")
                Text("Connect once to compare this season with the last.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
