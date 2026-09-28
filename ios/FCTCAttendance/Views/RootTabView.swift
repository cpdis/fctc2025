//
//  RootTabView.swift
//  FCTCAttendance
//
//  The configured app's top level: a Liquid Glass tab bar with Runs, Events and
//  Dashboard (R19). Runs hosts the existing Home screen unchanged (R20). Events
//  and Dashboard are placeholders until their own units replace them.
//

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

    @State private var selection: AppTab = .runs

    var body: some View {
        TabView(selection: $selection) {
            Tab("Runs", systemImage: "figure.run", value: AppTab.runs) {
                HomeView(runtime: runtime, pendingRoutes: pendingRoutes)
            }
            .accessibilityIdentifier("tab-runs")

            Tab("Events", systemImage: "calendar", value: AppTab.events) {
                TabPlaceholderView(title: "Events")
            }
            .accessibilityIdentifier("tab-events")

            Tab("Dashboard", systemImage: "chart.bar", value: AppTab.dashboard) {
                TabPlaceholderView(title: "Dashboard")
            }
            .accessibilityIdentifier("tab-dashboard")
        }
    }
}

/// A titled, empty tab root. It keeps the tab bar honest (three real
/// destinations with their own navigation stacks) until the real screens land.
private struct TabPlaceholderView: View {
    let title: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                title,
                systemImage: "hammer",
                description: Text("Coming soon.")
            )
            .navigationTitle(title)
        }
    }
}
