//
//  HomeComponents.swift
//  FCTCAttendance
//
//  The cards and rows that make up the Home list. HomeView owns the data and
//  navigation; these views only draw what they are given.
//

import FCTCAttendanceKit
import SwiftUI

struct TodayRunHero: View {
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

struct HomeRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color

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
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

struct HomeSyncBanner: View {
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
struct SummaryTile: View {
    let title: String
    let value: Int
    let systemImage: String
    let tint: Color
    /// Turns the glyph while real work runs, such as a sync drain.
    var isWorking = false

    /// The tile rounding. HomeView reuses it to clip the zoom transition source.
    static let cornerRadius: CGFloat = 26

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                    // Unsynced -> Conflicts swaps the glyph in place.
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.rotate, options: .repeating, isActive: isWorking)
                    .frame(width: 28, height: 28)
                    .background(.white, in: .circle)
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
                Text(value, format: .number)
                    .font(.title.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    // Digits roll to the new count instead of snapping.
                    .contentTransition(.numericText(value: Double(value)))
            }
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        // 26 matches the inset-grouped section radius the list masks outer row
        // edges with; a smaller radius leaves the inner corners visibly sharper
        // than the outer ones (Colin's review).
        .background(tint.gradient, in: .rect(cornerRadius: Self.cornerRadius))
        .contentShape(.rect)
        .animation(Motion.snappy, value: value)
        .animation(Motion.snappy, value: title)
    }
}
