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
    case checklist(RunSnapshot, ChecklistPresentation)
    case runPicker(RunPickerScope)
    case outbox
}

enum ChecklistPresentation: Hashable {
    case standard
    case dictation
    case sharedScreenshots
}

struct HomeView: View {
    let runtime: AppRuntime
    let pendingRoutes: PendingRouteStore

    @Query(sort: \ScheduledRun.rowIndex) private var cachedRuns: [ScheduledRun]
    @Query(
        filter: #Predicate<PendingSubmission> { $0.stateRaw != "done" },
        sort: \PendingSubmission.createdAt
    ) private var cachedSubmissions: [PendingSubmission]
    @State private var viewModel: HomeViewModel
    @State private var path: [HomeRoute] = []
    @State private var deferredRoute: PendingAppRoute?
    @State private var sharedScreenshotCount = 0
    @State private var showingSharedScreenshotOffer = false

    init(runtime: AppRuntime, pendingRoutes: PendingRouteStore = .shared) {
        self.runtime = runtime
        self.pendingRoutes = pendingRoutes
        _viewModel = State(initialValue: HomeViewModel(engine: runtime.engine))
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if viewModel.isInitialLoading && cachedRuns.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "Loading Season",
                            systemImage: "calendar.badge.clock",
                            description: Text("Fetching the roster and scheduled runs.")
                        )
                        .accessibilityIdentifier("home-initial-loading")
                    }
                } else {
                    summarySection

                    // The hero floats in its own section: sharing one with the
                    // run rows fused the card's bottom edge to the grouped
                    // rectangle behind it (Colin's review).
                    if !(viewModel.initialLoadFailed && cachedRuns.isEmpty),
                       let todayRun = viewModel.todayRun {
                        Section {
                            Button {
                                path.append(.checklist(todayRun, .standard))
                            } label: {
                                TodayRunHero(run: todayRun)
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .accessibilityIdentifier("home-todays-run")
                        }
                    }

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
                }
            }
            .refreshable {
                await viewModel.refresh(hasCachedState: !cachedRuns.isEmpty)
                updateFromCache()
            }
            .task {
                updateFromCache()
                handlePendingRoute()
                checkSharedScreenshotInbox()
                await viewModel.refresh(hasCachedState: !cachedRuns.isEmpty)
                updateFromCache()
                handlePendingRoute()
                checkSharedScreenshotInbox()
            }
            .onChange(of: cacheFingerprint) { _, _ in
                updateFromCache()
                handlePendingRoute()
            }
            .onChange(of: runtime.generation) { _, _ in
                viewModel.replaceEngine(runtime.engine)
                Task {
                    await viewModel.refresh(hasCachedState: !cachedRuns.isEmpty)
                    updateFromCache()
                    handlePendingRoute()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: PendingRouteStore.changed)) { _ in
                handlePendingRoute()
            }
            .onReceive(NotificationCenter.default.publisher(for: .fctcAppDidActivate)) { _ in
                handlePendingRoute()
                checkSharedScreenshotInbox()
            }
            .alert(
                "Import \(sharedScreenshotCount) shared screenshot\(sharedScreenshotCount == 1 ? "" : "s")?",
                isPresented: $showingSharedScreenshotOffer
            ) {
                Button("Import") {
                    guard let todayRun = viewModel.todayRun else { return }
                    path.append(.checklist(todayRun, .sharedScreenshots))
                }
                Button("Dismiss", role: .cancel) {
                    try? runtime.sharedScreenshotInbox.clear()
                }
            } message: {
                Text("Open today's checklist and review the imported poll.")
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

    private func handlePendingRoute() {
        let route = deferredRoute ?? pendingRoutes.consume()
        guard let route else { return }
        let target: RunSnapshot?
        let presentation: ChecklistPresentation
        switch route {
        case .todayChecklist:
            target = viewModel.todayRun
            presentation = .standard
        case .todayDictation:
            target = viewModel.todayRun
            presentation = .dictation
        case .checklist(let rowIndex, let date, let run):
            target = cachedRuns.map(RunSnapshot.init).first {
                $0.rowIndex == rowIndex && $0.date == date && $0.run == run
            }
            presentation = .standard
        }
        guard let target else {
            deferredRoute = route
            return
        }
        deferredRoute = nil
        path = [.checklist(target, presentation)]
    }

    private func checkSharedScreenshotInbox() {
        guard !showingSharedScreenshotOffer,
              path.isEmpty, viewModel.todayRun != nil,
              let count = try? runtime.sharedScreenshotInbox.list().count,
              count > 0
        else { return }
        sharedScreenshotCount = count
        showingSharedScreenshotOffer = true
    }
}

private struct TodayRunHero: View {
    let run: RunSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TODAY'S RUN")
                        .font(.caption.weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.78))
                    Text(run.run)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                }
                Spacer(minLength: 12)
                Text(run.date)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(run.meet)
                        .font(.headline)
                        .foregroundStyle(.white)
                    if let km = run.approxKm {
                        Text("About \(km.formatted(.number.precision(.fractionLength(0...2)))) km")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                Spacer(minLength: 12)
                Text("Record")
                    .font(.headline)
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(.white, in: .capsule)
                    .accessibilityHidden(true)
            }
        }
        .padding(18)
        .background(Color.accentColor.gradient, in: .rect(cornerRadius: 18))
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Today's Run, \(run.detailLabel), \(run.date), Record")
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
