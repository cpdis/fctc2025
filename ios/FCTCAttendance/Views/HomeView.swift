//
//  HomeView.swift
//  FCTCAttendance
//
//  PLACEHOLDER (U1). The real home screen — live counts, navigation into the
//  checklist / run picker / outbox — arrives in U4. This exists so the app target
//  compiles and runs, and so the Reminders-derived idioms from the plan's Design
//  Language section are established up front:
//
//    • large navigation title
//    • summary tiles at the top ("list of lists" header)
//    • grouped inset list of tinted circular-icon rows
//
//  Everything below is static; no networking, no SwiftData reads.
//

import SwiftUI

struct HomeView: View {

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        SummaryTile(
                            title: "This week",
                            value: "3",
                            systemImage: "figure.run",
                            tint: .accentColor
                        )
                        SummaryTile(
                            title: "Unsynced",
                            value: "0",
                            systemImage: "arrow.trianglehead.2.clockwise",
                            tint: .orange
                        )
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                Section("Runs") {
                    HomeRow(
                        title: "Today's Run",
                        subtitle: "Fri, Soft Sand — Il Lido",
                        systemImage: "calendar.badge.clock",
                        tint: .accentColor
                    )
                    HomeRow(
                        title: "Upcoming",
                        subtitle: "Next scheduled runs",
                        systemImage: "calendar",
                        tint: .blue
                    )
                    HomeRow(
                        title: "Past Runs",
                        subtitle: "Fill in a missed row",
                        systemImage: "clock.arrow.circlepath",
                        tint: .gray
                    )
                }

                Section("Sync") {
                    HomeRow(
                        title: "Outbox",
                        subtitle: "Nothing waiting",
                        systemImage: "tray.and.arrow.up",
                        tint: .orange
                    )
                    HomeRow(
                        title: "Settings",
                        subtitle: "Endpoint, secret, device name",
                        systemImage: "gearshape",
                        tint: .secondary
                    )
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("FCTC Attendance")
        }
    }
}

/// Reminders-style row: tinted circular glyph, title, secondary subtitle, chevron.
private struct HomeRow: View {
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

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

/// Reminders' top-of-screen count tiles.
private struct SummaryTile: View {
    let title: String
    let value: String
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
                Spacer(minLength: 0)
                Text(value)
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
    }
}

#Preview {
    HomeView()
}
