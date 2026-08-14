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
    case outbox
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
                if viewModel.isInitialLoading && cachedRuns.isEmpty {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Loading the season")
                                    .font(.headline)
                                Text("Fetching the roster and scheduled runs…")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 10)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Loading the season")
                        .accessibilityIdentifier("home-initial-loading")
                    }
                } else {
                    summarySection

                    Section("Runs") {
                        if viewModel.initialLoadFailed && cachedRuns.isEmpty {
                            ContentUnavailableView {
                                Label("Runs Unavailable", systemImage: "wifi.exclamationmark")
                            } description: {
                                Text("The app could not load the season. Check the message below and try again.")
                            } actions: {
                                Button("Try Again") {
                                    Task {
                                        await viewModel.retry(hasCachedState: false)
                                        updateFromCache()
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            .accessibilityIdentifier("home-runs-unavailable")
                        } else {
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
                                        title: "No Run Today",
                                        subtitle: "Choose another scheduled run",
                                        systemImage: "calendar.badge.exclamationmark",
                                        tint: .accentColor
                                    )
                                }
                                .accessibilityIdentifier("home-no-run-today")
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
                    }
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
                            badge: viewModel.conflictCount > 0
                                ? viewModel.conflictCount
                                : viewModel.unsyncedCount,
                            badgeTint: viewModel.conflictCount > 0 ? .red : .orange
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

                if let banner = viewModel.syncBanner {
                    HomeSyncBanner(banner: banner, runtime: runtime) {
                        await viewModel.retry(hasCachedState: !cachedRuns.isEmpty)
                        updateFromCache()
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
                case .outbox:
                    OutboxView(runtime: runtime)
                }
            }
            .refreshable {
                await viewModel.refresh(hasCachedState: !cachedRuns.isEmpty)
                updateFromCache()
            }
            .task {
                updateFromCache()
                await viewModel.refresh(hasCachedState: !cachedRuns.isEmpty)
                updateFromCache()
            }
            .onChange(of: cacheFingerprint) { _, _ in updateFromCache() }
            .onChange(of: runtime.generation) { _, _ in
                viewModel.replaceEngine(runtime.engine)
                Task {
                    await viewModel.refresh(hasCachedState: !cachedRuns.isEmpty)
                    updateFromCache()
                }
            }
        }
    }

    private var summarySection: some View {
        Section {
            // Buttons that drive the path, NOT NavigationLinks: two links inside
            // one List row activate as a pair (tap pushed Outbox, back revealed
            // This Week), and links also draw the disclosure chevron the
            // Reminders tiles deliberately lack.
            HStack(spacing: 12) {
                Button {
                    path.append(HomeRoute.runPicker(.thisWeek))
                } label: {
                    SummaryTile(
                        title: "This Week",
                        value: viewModel.thisWeekCount,
                        systemImage: "figure.run",
                        tint: .green
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("This Week, \(viewModel.thisWeekCount) runs")
                .accessibilityIdentifier("home-this-week")

                Button {
                    path.append(HomeRoute.outbox)
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
        if viewModel.conflictCount > 0 {
            return "\(viewModel.conflictCount) conflict\(viewModel.conflictCount == 1 ? "" : "s") needs review"
        }
        return viewModel.unsyncedCount == 0
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
    var badgeTint: Color = .orange

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
                    .background(badgeTint, in: .capsule)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

private struct HomeSyncBanner: View {
    let banner: SyncBanner
    let runtime: AppRuntime
    let retry: @MainActor () async -> Void

    var body: some View {
        Section {
            Label(banner.message, systemImage: icon)
                .font(.footnote)
                .foregroundStyle(tint)
                .accessibilityIdentifier("home-sync-banner")

            switch banner.kind {
            case .offline, .parked:
                Button("Retry Now", systemImage: "arrow.clockwise") {
                    Task { await retry() }
                }
                .accessibilityIdentifier("home-sync-retry")
            case .conflict:
                NavigationLink {
                    OutboxView(runtime: runtime)
                } label: {
                    Label("Review Conflict", systemImage: "exclamationmark.triangle")
                }
                .accessibilityIdentifier("home-review-conflict")
            case .authentication:
                NavigationLink {
                    SettingsView(runtime: runtime)
                } label: {
                    Label("Open Settings", systemImage: "gearshape")
                }
                .accessibilityIdentifier("home-open-settings")
            case .error:
                NavigationLink {
                    OutboxView(runtime: runtime)
                } label: {
                    Label("Open Outbox", systemImage: "tray.and.arrow.up")
                }
            case .success:
                EmptyView()
            }
        }
    }

    private var icon: String {
        switch banner.kind {
        case .success: "checkmark.circle.fill"
        case .offline: "wifi.slash"
        case .parked: "hourglass"
        case .conflict: "exclamationmark.triangle.fill"
        case .authentication: "key.slash"
        case .error: "exclamationmark.circle.fill"
        }
    }

    private var tint: Color {
        switch banner.kind {
        case .success: .green
        case .offline, .parked, .conflict: .orange
        case .authentication, .error: .red
        }
    }
}

/// Reminders-style summary tile: full-color rounded rect, glyph in a white
/// circle, big white count top-right, white label bottom-left. No chevron.
private struct SummaryTile: View {
    let title: String
    let value: Int
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(.white, in: .circle)
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
                Text(value, format: .number)
                    .font(.title.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.gradient, in: .rect(cornerRadius: 14))
        .contentShape(.rect)
    }
}
