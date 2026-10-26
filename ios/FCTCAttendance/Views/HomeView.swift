//
//  HomeView.swift
//  FCTCAttendance
//
//  The Runs tab root (R20): the Reminders-style "list of lists" backed by the
//  offline SwiftData cache. RootTabView owns its navigation path and its model,
//  because notification and App Intent routes land here from any tab (KTD14).
//

import FCTCAttendanceKit
import SwiftData
import SwiftUI

/// Value-based routes for the screens that must pop back to Home after a
/// confirmed submission (packet R6: Confirm returns Home). Clearing `path`
/// is the only pop-to-root mechanism SwiftUI guarantees.
enum HomeRoute: Hashable {
    case checklist(RunSnapshot, ChecklistPresentation)
    case runPicker(RunPickerScope)
    case outbox
    case settings
}

enum ChecklistPresentation: Hashable {
    case standard
    case dictation
    case sharedScreenshots
}

struct HomeView: View {
    let runtime: AppRuntime
    /// Owned by RootTabView, which reads `todayRun` to resolve routes.
    let viewModel: HomeViewModel
    /// The Runs tab's stack, owned by RootTabView so routes and engine swaps
    /// can reset it.
    @Binding var path: [HomeRoute]

    @Query(sort: \ScheduledRun.rowIndex) private var cachedRuns: [ScheduledRun]
    @Query private var guestOperations: [PendingGuestOperation]
    @Query(
        filter: PendingSubmission.outstandingPredicate,
        sort: \PendingSubmission.createdAt
    ) private var cachedSubmissions: [PendingSubmission]
    @Query private var sheetCaches: [SharedSheetCache]
    /// The active season's runs. Resolving them fetches and decodes the season
    /// cache, so `updateFromCache()` stores them once per data change
    /// (`cacheFingerprint`) and a render only reads this copy.
    @State private var activeRuns: [RunSnapshot] = []
    @State private var recovery: [GuestRecoverySnapshot] = []
    /// Flips once per launch so the header cards stagger in on first sight only.
    @State private var hasEntered = false
    /// Bumped to restart the refresh task: the Sync button, an activation
    /// after a failed or stale refresh, or an engine swap. The task also runs
    /// on every appear.
    @State private var refreshRequest = 0
    /// The `refreshRequest` whose read finished. A newer value is a request
    /// still owed a read; a plain appear reads only stale data.
    @State private var servedRequest = 0

    var body: some View {
        NavigationStack(path: $path) {
            List {
                // The tab header: the large title, Sync and the gear share one
                // line (Colin's review), which the system large-title bar cannot do.
                Section {
                    TabHeader(title: "FCTC", identifier: "home-title") {
                        HStack(spacing: 12) {
                            SyncButton(status: viewModel.syncStatus) {
                                // Pull-to-refresh may already be reading the sheet.
                                guard !viewModel.isRefreshing else { return }
                                refreshRequest += 1
                            }

                            Button {
                                path.append(HomeRoute.settings)
                            } label: {
                                HeaderCircleIcon(systemImage: "gearshape")
                            }
                            .buttonStyle(.pressable)
                            .accessibilityLabel("Settings")
                            .accessibilityIdentifier("home-settings")
                        }
                    }
                    .staggeredEntrance(0, hasEntered: hasEntered)
                    .tabHeaderRow()
                }

                if viewModel.isInitialLoading && activeRuns.isEmpty {
                    Section {
                        SeasonLoadingView(identifier: "home-initial-loading")
                    }
                } else {
                    summarySection

                    // The hero floats in its own section: sharing one with the
                    // run rows fused the card's bottom edge to the grouped
                    // rectangle behind it (Colin's review).
                    if !(viewModel.initialLoadFailed && activeRuns.isEmpty),
                       let todayRun = viewModel.todayRun {
                        Section {
                            Button {
                                path.append(.checklist(todayRun, .standard))
                            } label: {
                                TodayRunHero(run: todayRun)
                            }
                            .buttonStyle(.pressable)
                            .staggeredEntrance(2, hasEntered: hasEntered)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .accessibilityIdentifier("home-todays-run")
                        }
                    }

                    Section {
                        if viewModel.initialLoadFailed && activeRuns.isEmpty {
                            SeasonUnavailableView(
                                identifier: "home-runs-unavailable",
                                detail: "The app could not load the season. Check the message below and try again."
                            ) {
                                await viewModel.retry(hasCachedState: false)
                                updateFromCache()
                            }
                        } else {
                            if viewModel.todayRun == nil {
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
                                    title: "Season",
                                    subtitle: "Every scheduled and recorded run",
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
                    } header: {
                        Text("Runs")
                    } footer: {
                        // Colin is trialling this line; delete this footer block
                        // (and seasonProgress below) to remove it.
                        if let progress = seasonProgress {
                            Text(progress)
                        }
                    }
                }

                if recovery.contains(where: { $0.status == .pending }) {
                    Section {
                        NavigationLink { GuestRecoveryView(runtime: runtime) } label: {
                            Label("Review local guest history", systemImage: "person.crop.circle.badge.clock")
                        }.accessibilityIdentifier("recover-guests-reminder")
                        Button("Dismiss reminder") {
                            Task {
                                for candidate in recovery where candidate.status == .pending {
                                    try? await runtime.engine.updateRecoveryCandidate(id: candidate.id, guestId: candidate.selectedGuestId, run: candidate.selectedRun, status: .dismissed)
                                }
                                await loadRecovery()
                            }
                        }
                    } footer: { Text("Names from this phone need review. You can recover them later in Settings.") }
                }

                if let banner = viewModel.syncBanner {
                    HomeSyncBanner(banner: banner) {
                        await viewModel.retry(hasCachedState: !activeRuns.isEmpty)
                        updateFromCache()
                    }
                }
            }
            .listStyle(.insetGrouped)
            .contentMargins(.top, 4, for: .scrollContent)
            // Above the tab bar, outside the List: glass inside a list row
            // smears (see `HeaderCircleIcon`).
            .overlay(alignment: .bottom) {
                SyncStatusPill(status: viewModel.syncStatus, failed: viewModel.syncFailed)
                    .padding(.bottom, 12)
                    // Status only: a tap on the row beneath must still land.
                    .allowsHitTesting(false)
            }
            // The custom header row IS the title bar; the system bar would
            // stack a second empty line above it.
            .navigationTitle("FCTC")
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .checklist(let run, let presentation):
                    // Confirm must land back on Home (R6), from any depth.
                    ChecklistView(
                        runtime: runtime,
                        run: run,
                        presentation: presentation
                    ) { nextRun in
                        if let nextRun {
                            // Collapse a picker -> checklist stack. The next
                            // catch-up screen must still have Home as its Back target.
                            path = [.checklist(nextRun, .standard)]
                        } else {
                            path.removeAll()
                        }
                    }
                case .runPicker(let scope):
                    RunPickerView(runtime: runtime, scope: scope)
                case .outbox:
                    OutboxView(runtime: runtime)
                case .settings:
                    SettingsView(runtime: runtime)
                }
            }
            .refreshable { await refresh() }
            .onAppear { hasEntered = true }
            // One refresh at a time: a new request cancels the one in flight,
            // and leaving Home cancels it too. A request always reads; a plain
            // return to Runs reads only when the last sync is stale (5 min).
            .task(id: refreshRequest) {
                updateFromCache()
                guard refreshRequest != servedRequest || viewModel.needsRefresh() else { return }
                await refresh()
                // A cancelled read (Runs left mid-request) leaves the request
                // owed, so the next appear reads.
                if !Task.isCancelled { servedRequest = refreshRequest }
            }
            .onChange(of: viewModel.activeState) { _, state in
                runtime.activeState = state
                updateFromCache()
            }
            // Recovery evidence can change with each refresh, so it reloads
            // with the season state.
            .task(id: viewModel.activeState) { await loadRecovery() }
            .onChange(of: cacheFingerprint) { _, _ in
                updateFromCache()
            }
            // Coming back to the app reads again after a failed refresh (a
            // dropped connection, the sheet waking up), so its banner clears
            // itself, or when the last sync is stale. A read in flight stays.
            .onReceive(NotificationCenter.default.publisher(for: .fctcAppDidActivate)) { _ in
                guard !viewModel.isRefreshing else { return }
                if viewModel.refreshFailed || viewModel.needsRefresh() { refreshRequest += 1 }
            }
            // RootTabView resets the path on a swap; the model follows the new
            // engine here, next to the refresh it drives.
            .onChange(of: runtime.generation) { _, _ in
                viewModel.replaceEngine(runtime.engine)
                refreshRequest += 1
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
                .buttonStyle(.pressable)
                .accessibilityLabel("This Week, \(DashboardFormat.runs(viewModel.thisWeekCount))")
                .accessibilityIdentifier("home-this-week")

                Button {
                    path.append(HomeRoute.outbox)
                } label: {
                    // The tile is the only Outbox entry point (the Sync-section
                    // row is gone), so it also carries the conflict signal.
                    SummaryTile(
                        title: viewModel.conflictCount > 0 ? "Conflicts" : "Unsynced",
                        value: viewModel.conflictCount > 0
                            ? viewModel.conflictCount
                            : viewModel.unsyncedCount,
                        systemImage: viewModel.conflictCount > 0
                            ? "exclamationmark.triangle.fill"
                            : "arrow.trianglehead.2.clockwise",
                        tint: viewModel.conflictCount > 0 ? .red : .orange,
                        // Only the sync arrows turn; a conflict triangle never spins.
                        isWorking: viewModel.isSyncing && viewModel.conflictCount == 0
                    )
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(
                    viewModel.conflictCount > 0
                        ? "Conflicts, \(viewModel.conflictCount) need review"
                        : "Unsynced, \(DashboardFormat.submissions(viewModel.unsyncedCount))\(viewModel.isSyncing ? ", syncing" : "")"
                )
                .accessibilityIdentifier("home-unsynced")
            }
            .staggeredEntrance(1, hasEntered: hasEntered)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }

    private var pendingGuestOperations: [PendingGuestOperation] {
        guestOperations.filter { $0.endpointIdentity == runtime.config.endpoint?.absoluteString && $0.phase != .completed && $0.phase != .superseded }
    }

    /// "94 of 163 runs recorded", or nil before the season has loaded.
    private var seasonProgress: String? {
        guard !activeRuns.isEmpty else { return nil }
        let recorded = activeRuns.filter(\.hasRecordedAttendance).count
        return "\(recorded) of \(DashboardFormat.runs(activeRuns.count)) recorded"
    }

    /// Changes whenever a Runs input does: the season's runs, an outbox row or
    /// a guest change. It decodes no JSON, so it is cheap to build per render.
    private var cacheFingerprint: String {
        let submissions = cachedSubmissions.map { "\($0.id):\($0.stateRaw)" }.joined(separator: "|")
        let guestChanges = pendingGuestOperations.map { "\($0.id):\($0.phaseRaw)" }.joined(separator: "|")
        return [runtime.activeRunsFingerprint(runs: cachedRuns, caches: sheetCaches), submissions, guestChanges]
            .joined(separator: "#")
    }

    /// Pending names from legacy rows, for the review reminder. Dismissed
    /// ones stay out: the reminder is only for names nobody has looked at.
    private func loadRecovery() async {
        let candidates = (try? await runtime.engine.recoveryCandidates(includeDismissed: false)) ?? []
        guard !Task.isCancelled else { return }
        recovery = candidates
    }

    /// Reads the sheet (the engine then sends the outbox) and redraws from the
    /// cache. Pull-to-refresh and the `refreshRequest` task both land here.
    private func refresh() async {
        await viewModel.refresh(hasCachedState: !activeRuns.isEmpty)
        updateFromCache()
    }

    /// The one place Runs resolves the season cache.
    private func updateFromCache() {
        activeRuns = runtime.activeRuns(in: cachedRuns).map(RunSnapshot.init)
        viewModel.update(
            runs: activeRuns,
            submissions: cachedSubmissions.map(PendingSubmissionSnapshot.init),
            pendingGuestChanges: pendingGuestOperations.count,
            guestConflicts: pendingGuestOperations.filter { $0.phase == .conflict || $0.phase == .rejected }.count
        )
    }
}
