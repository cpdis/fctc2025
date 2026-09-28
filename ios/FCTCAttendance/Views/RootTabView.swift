//
//  RootTabView.swift
//  FCTCAttendance
//
//  The configured app's top level: a Liquid Glass tab bar with Runs, Events and
//  Dashboard (R19). It owns the selected tab, one navigation path per tab, and
//  route handling (KTD14), so a route lands on Runs from whichever tab is showing:
//
//    notification tap ─┐                       ┌─ run cached ──▶ selection = .runs
//    App Intent ───────┴▶ PendingRouteStore ──▶┤                runsPath = [checklist]
//                         (consume on change,  └─ not yet ───▶ deferredRoute, retried
//                          launch, activation)                  as the cache fills
//
//  Events and Dashboard keep their stacks. An engine swap (a new connection)
//  resets every tab's path, because pushed screens hold the old connection's runs.
//

import FCTCAttendanceKit
import SwiftData
import SwiftUI

/// The app's top-level destinations, in tab-bar order.
enum AppTab: Hashable {
    case runs
    case events
    case dashboard
}

struct RootTabView: View {
    let runtime: AppRuntime
    let pendingRoutes: PendingRouteStore

    @Query(sort: \ScheduledRun.rowIndex) private var cachedRuns: [ScheduledRun]
    /// Home's model lives here so a "today" route resolves to the very run the
    /// Runs hero shows, and the Dashboard shares its first-load state. HomeView
    /// still drives its refreshes.
    @State private var runsModel: HomeViewModel
    @State private var selection: AppTab = .runs
    @State private var runsPath: [HomeRoute] = []
    @State private var eventsPath = NavigationPath()
    @State private var dashboardPath = NavigationPath()
    /// A route whose run is not cached yet (setup just finished, the season is
    /// still loading). It waits here until the run arrives or a newer route
    /// replaces it.
    @State private var deferredRoute: PendingAppRoute?
    @State private var sharedScreenshotCount = 0
    @State private var showingSharedScreenshotOffer = false

    init(runtime: AppRuntime, pendingRoutes: PendingRouteStore) {
        self.runtime = runtime
        self.pendingRoutes = pendingRoutes
        _runsModel = State(initialValue: HomeViewModel(engine: runtime.engine))
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("Runs", systemImage: "figure.run", value: AppTab.runs) {
                HomeView(runtime: runtime, viewModel: runsModel, path: $runsPath)
            }
            .accessibilityIdentifier("tab-runs")

            Tab("Events", systemImage: "calendar", value: AppTab.events) {
                EventsView(runtime: runtime, path: $eventsPath)
            }
            .accessibilityIdentifier("tab-events")

            Tab("Dashboard", systemImage: "chart.bar", value: AppTab.dashboard) {
                DashboardView(runtime: runtime, home: runsModel, path: $dashboardPath)
            }
            .accessibilityIdentifier("tab-dashboard")
        }
        .task {
            handlePendingRoute()
            offerSharedScreenshots()
        }
        // Today's run appears once Home reads the cache or finishes its first
        // refresh: the moment a waiting "today" route can land and the shared
        // screenshots can be offered.
        .onChange(of: runsModel.todayRun?.id) { _, _ in
            handlePendingRoute()
            offerSharedScreenshots()
        }
        // A reminder names one specific run, which can arrive with any sync.
        .onChange(of: routeTargets) { _, _ in handlePendingRoute() }
        .onChange(of: runtime.generation) { _, _ in resetAllPaths() }
        .onReceive(NotificationCenter.default.publisher(for: PendingRouteStore.changed)) { _ in
            handlePendingRoute()
        }
        .onReceive(NotificationCenter.default.publisher(for: .fctcAppDidActivate)) { _ in
            handlePendingRoute()
            offerSharedScreenshots()
        }
        .alert(
            "Import \(sharedScreenshotCount) shared screenshot\(sharedScreenshotCount == 1 ? "" : "s")?",
            isPresented: $showingSharedScreenshotOffer
        ) {
            Button("Import") {
                guard let todayRun = runsModel.todayRun else { return }
                selection = .runs
                runsPath.append(.checklist(todayRun, .sharedScreenshots))
            }
            Button("Dismiss", role: .cancel) {
                try? runtime.sharedScreenshotInbox.clear()
            }
        } message: {
            Text("Open today's checklist and review the imported poll.")
        }
    }

    /// The runs a reminder route can name: the active season's cache.
    private var routeTargets: [RunSnapshot] {
        runtime.activeRuns(in: cachedRuns).map(RunSnapshot.init)
    }

    /// Takes a newly stored route, or retries the waiting one, and lands it on
    /// Runs: select the tab, pop its stack to root and push the checklist.
    private func handlePendingRoute() {
        // The newest route wins. Retrying the waiting route first let one that
        // could never resolve (a reminder for a run the sheet no longer has)
        // block every later tap for the rest of the session.
        let incoming = pendingRoutes.consume()
        guard let route = incoming ?? deferredRoute else { return }
        // Switch at once, so a route that must wait shows the season loading
        // on Runs instead of nothing happening on another tab.
        if incoming != nil { selection = .runs }
        guard let checklist = checklistRoute(for: route) else {
            deferredRoute = route
            return
        }
        deferredRoute = nil
        selection = .runs
        runsPath = [checklist]
    }

    /// The checklist a route opens, or nil while its run is not cached yet.
    private func checklistRoute(for route: PendingAppRoute) -> HomeRoute? {
        switch route {
        case .todayChecklist:
            runsModel.todayRun.map { .checklist($0, .standard) }
        case .todayDictation:
            runsModel.todayRun.map { .checklist($0, .dictation) }
        case .checklist(let rowIndex, let date, let run):
            routeTargets
                .first { $0.rowIndex == rowIndex && $0.date == date && $0.run == run }
                .map { .checklist($0, .standard) }
        }
    }

    /// Offers screenshots shared into the app for today's checklist. Only while
    /// Runs sits at its root, so the offer never interrupts a pushed screen.
    private func offerSharedScreenshots() {
        guard !showingSharedScreenshotOffer,
              runsPath.isEmpty, runsModel.todayRun != nil,
              let count = try? runtime.sharedScreenshotInbox.list().count,
              count > 0
        else { return }
        sharedScreenshotCount = count
        showingSharedScreenshotOffer = true
    }

    /// Every tab back to its root. The selected tab stays where it is.
    private func resetAllPaths() {
        runsPath = []
        eventsPath = NavigationPath()
        dashboardPath = NavigationPath()
    }
}
