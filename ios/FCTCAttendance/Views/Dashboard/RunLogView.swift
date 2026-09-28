//
//  RunLogView.swift
//  FCTCAttendance
//
//  Every run of the season, newest first and grouped by month, in the Events
//  list style (R23). Search matches the run type, event, place or a runner, so
//  "Aaron" lists the runs Aaron ran. A run opens its runners, and a runner opens
//  their screen (R24).
//

import FCTCAttendanceKit
import SwiftUI

struct RunLogView: View {
    /// The season's runs, oldest first (`DashboardModel.runs`).
    let runs: [DashboardRun]

    @State private var query = ""

    var body: some View {
        let months = self.months
        List {
            ForEach(months, id: \.title) { month in
                Section(month.title) {
                    ForEach(month.runs) { entry in
                        NavigationLink(value: DashboardRoute.run(entry.id)) {
                            EventRow(date: entry.run.date, title: Self.title(of: entry), detail: Self.detail(of: entry))
                        }
                        .accessibilityIdentifier("run-log-row-\(entry.id)")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if months.isEmpty {
                if query.isEmpty {
                    ContentUnavailableView("No Runs Yet", systemImage: "list.bullet")
                } else {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
        // The navigation bar, not the bottom edge: a bottom search field and the
        // tab bar fight over that edge inside a TabView (U11).
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Type, place or runner")
        .navigationTitle("Run log")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Matching runs, newest first, one section per month.
    private var months: [(title: String, runs: [DashboardRun])] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var sections: [(title: String, runs: [DashboardRun])] = []
        for entry in runs.reversed() where needle.isEmpty || Self.matches(entry, needle) {
            let title = entry.run.date.formatted(Date.FormatStyle.perth.month(.wide).year())
            if sections.last?.title == title {
                sections[sections.count - 1].runs.append(entry)
            } else {
                sections.append((title, [entry]))
            }
        }
        return sections
    }

    private static func matches(_ entry: DashboardRun, _ needle: String) -> Bool {
        let run = entry.run
        return ([run.label.type, run.label.event, run.location, run.run].compactMap { $0 } + run.attendees)
            .contains { $0.localizedStandardContains(needle) }
    }

    /// "Half Marathon · Xmas", or the type alone.
    static func title(of entry: DashboardRun) -> String {
        [entry.run.label.type, entry.run.label.event].compactMap { $0 }.joined(separator: " · ")
    }

    /// "Drift · 10 km · 18 runners". A run with no distance shows none.
    private static func detail(of entry: DashboardRun) -> String {
        let run = entry.run
        let km = run.actualKm.map { "\($0.formatted(.number.precision(.fractionLength(0...1)))) km" }
        let runners = run.headcount == 1 ? "1 runner" : "\(run.headcount) runners"
        let special = entry.isSpecial ? "special" : nil
        return [run.location, km, runners, special].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// One run: where, how far, and who ran it.
struct RunDetailView: View {
    /// Nil when the run left the season (a refresh removed its row).
    let entry: DashboardRun?

    var body: some View {
        if let entry {
            let run = entry.run
            List {
                Section {
                    LabeledContent("Date", value: run.date.formatted(Date.FormatStyle.perth.weekday(.wide).day().month(.wide)))
                    LabeledContent("Place", value: run.location.isEmpty ? "—" : run.location)
                    // A run with attendance but no km adds 0 km and shows "—".
                    LabeledContent("Distance", value: run.actualKm.map { "\($0.formatted(.number.precision(.fractionLength(0...1)))) km" } ?? "—")
                    LabeledContent("Club day", value: entry.isSpecial ? "No, a special" : "Yes")
                }
                Section {
                    ForEach(run.attendees.sorted { $0.localizedStandardCompare($1) == .orderedAscending }, id: \.self) { name in
                        NavigationLink(value: DashboardRoute.runner(name)) { Text(name) }
                            .accessibilityIdentifier("run-runner-\(name)")
                    }
                    if run.plusOnes > 0 {
                        Text(run.plusOnes == 1 ? "+1 guest" : "+\(run.plusOnes) guests")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(run.headcount == 1 ? "1 runner" : "\(run.headcount) runners")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(RunLogView.title(of: entry))
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("Run Not Found", systemImage: "questionmark.circle",
                                   description: Text("This run is no longer in the season."))
        }
    }
}
