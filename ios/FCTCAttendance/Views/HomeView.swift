//
//  HomeView.swift
//  FCTCAttendance
//
//  The Reminders-style "list of lists" backed by the offline SwiftData cache.
//

import FCTCAttendanceKit
import SwiftData
import SwiftUI

/// Value-based routes for the screens that must pop back to Home after a
/// confirmed submission (packet R6: Confirm returns Home). Clearing `path`
/// is the only pop-to-root mechanism SwiftUI guarantees.
enum HomeRoute: Hashable {
    case checklist(RunSnapshot)
    case runPicker(RunPickerScope)
}

struct HomeView: View {
    let runtime: AppRuntime

    @Query(sort: \ScheduledRun.rowIndex) private var cachedRuns: [ScheduledRun]
    @Query(
        filter: #Predicate<PendingSubmission> { $0.stateRaw != "done" },
        sort: \PendingSubmission.createdAt
    ) private var cachedSubmissions: [PendingSubmission]
    @State private var viewModel: HomeViewModel
    @State private var path: [HomeRoute] = []

    init(runtime: AppRuntime) {
        self.runtime = runtime
        _viewModel = State(initialValue: HomeViewModel(engine: runtime.engine))
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                summarySection

                Section("Runs") {
                    if let todayRun = viewModel.todayRun {
                        NavigationLink(value: HomeRoute.checklist(todayRun)) {
                            HomeRow(
                                title: "Today's Run",
                                subtitle: todayRun.detailLabel,
                                systemImage: "calendar.badge.clock",
                                tint: .accentColor
                            )
                        }
                        .accessibilityIdentifier("home-todays-run")
                    } else {
                        NavigationLink(value: HomeRoute.runPicker(.all)) {
                            HomeRow(
                                title: "Today's Run",
                                subtitle: "Choose a scheduled run",
                                systemImage: "calendar.badge.clock",
                                tint: .accentColor
                            )
                        }
                        .accessibilityIdentifier("home-todays-run")
                    }

                    NavigationLink(value: HomeRoute.runPicker(.all)) {
                        HomeRow(
                            title: "All Runs",
                            subtitle: "Scheduled and recorded runs",
                            systemImage: "calendar",
                            tint: .blue
                        )
                    }
                    .accessibilityIdentifier("home-all-runs")

                    NavigationLink(value: HomeRoute.runPicker(.past)) {
                        HomeRow(
                            title: "Past Runs",
                            subtitle: "Fill in a missed row",
                            systemImage: "clock.arrow.circlepath",
                            tint: .gray
                        )
                    }
                    .accessibilityIdentifier("home-past-runs")
                }

                Section("Sync") {
                    NavigationLink {
                        OutboxView(runtime: runtime)
                    } label: {
                        HomeRow(
                            title: "Outbox",
                            subtitle: outboxSubtitle,
                            systemImage: "tray.and.arrow.up",
                            tint: .orange,
                            badge: viewModel.unsyncedCount
                        )
                    }
                    .accessibilityIdentifier("home-outbox")

                    NavigationLink {
                        SettingsView(runtime: runtime)
                    } label: {
                        HomeRow(
                            title: "Settings",
                            subtitle: "Endpoint, secret, and device name",
                            systemImage: "gearshape",
                            tint: .secondary
                        )
                    }
                    .accessibilityIdentifier("home-settings")
                }

                if let message = viewModel.lastSyncMessage {
                    Section {
                        Label(message, systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("FCTC")
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .checklist(let run):
                    // Confirm must land back on Home (R6), from any depth.
                    ChecklistView(runtime: runtime, run: run) { path.removeAll() }
                case .runPicker(let scope):
                    RunPickerView(runtime: runtime, scope: scope)
                }
            }
            .refreshable {
                await viewModel.refresh()
                updateFromCache()
            }
            .task {
                updateFromCache()
                await viewModel.refresh()
                updateFromCache()
            }
            .onChange(of: cacheFingerprint) { _, _ in updateFromCache() }
            .onChange(of: runtime.generation) { _, _ in
                viewModel.replaceEngine(runtime.engine)
                Task {
                    await viewModel.refresh()
                    updateFromCache()
                }
            }
        }
    }

    private var summarySection: some View {
        Section {
            HStack(spacing: 12) {
                NavigationLink(value: HomeRoute.runPicker(.thisWeek)) {
                    SummaryTile(
                        title: "This Week",
                        value: viewModel.thisWeekCount,
                        systemImage: "figure.run",
                        tint: .accentColor
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("This Week, \(viewModel.thisWeekCount) runs")
                .accessibilityIdentifier("home-this-week")

                NavigationLink {
                    OutboxView(runtime: runtime)
                } label: {
                    SummaryTile(
                        title: "Unsynced",
                        value: viewModel.unsyncedCount,
                        systemImage: "arrow.trianglehead.2.clockwise",
                        tint: .orange
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Unsynced, \(viewModel.unsyncedCount) submissions")
                .accessibilityIdentifier("home-unsynced")
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }

    private var outboxSubtitle: String {
        viewModel.unsyncedCount == 0
            ? "Nothing waiting"
            : "\(viewModel.unsyncedCount) waiting"
    }

    private var cacheFingerprint: String {
        let runs = cachedRuns.map {
            "\($0.rowIndex):\($0.attendees.count):\($0.plusOnes):\($0.cachedRevision ?? "")"
        }.joined(separator: "|")
        let submissions = cachedSubmissions.map { "\($0.id):\($0.stateRaw)" }.joined(separator: "|")
        return runs + "#" + submissions
    }

    private func updateFromCache() {
        viewModel.update(
            runs: cachedRuns.map(RunSnapshot.init),
            submissions: cachedSubmissions.map(PendingSubmissionSnapshot.init)
        )
    }
}

private struct HomeRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    var badge: Int = 0

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(tint, in: .circle)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if badge > 0 {
                Text(badge, format: .number)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.orange, in: .capsule)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

private struct SummaryTile: View {
    let title: String
    let value: Int
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(tint, in: .circle)
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
                Text(value, format: .number)
                    .font(.title.weight(.semibold))
                    .monospacedDigit()
            }
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
        .contentShape(.rect)
    }
}
