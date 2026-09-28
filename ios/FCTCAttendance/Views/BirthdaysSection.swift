import Combine
import FCTCAttendanceKit
import SwiftUI
import UIKit

/// Day/month only: the organiser needs the occasion, not an age or birth year.
struct BirthdaysSection: View {
    let birthdays: [MemberBirthday]?
    @Environment(\.scenePhase) private var scenePhase
    @State private var now = Date.now

    private var upcoming: [UpcomingBirthday] {
        BirthdayBoard.upcoming(from: birthdays ?? [], now: now)
    }

    var body: some View {
        let upcoming = upcoming
        Section {
            if upcoming.isEmpty {
                Text(birthdays == nil ? "Birthdays are not available yet." : "No birthdays in the next 30 days.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("birthday-empty")
            } else {
                ForEach(upcoming) { birthday in
                    BirthdayRow(birthday: birthday)
                        .accessibilityIdentifier("birthday-row-\(birthday.name)")
                }
            }
        } header: {
            Text("Birthdays")
        } footer: {
            Text("Today and the next 30 days")
        }
        // Device midnight may differ from Perth midnight while travelling.
        // Refresh the local window while active; this never fetches sheet data.
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { date in
            if scenePhase == .active { now = date }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            now = .now
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { now = .now }
        }
    }
}

private struct BirthdayRow: View {
    let birthday: UpcomingBirthday
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Set on first appear so today's cake gives one small wiggle, not one per
    /// return to Home.
    @State private var celebrations = 0

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        layout {
            Text(birthday.name)
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
            VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
                if birthday.daysUntil == 0 {
                    Label("Today", systemImage: "birthday.cake.fill")
                        .foregroundStyle(Color.accentColor)
                        .symbolEffect(.wiggle, value: celebrations)
                        .onAppear { if celebrations == 0 { celebrations = 1 } }
                } else {
                    Text(relativeDay)
                        .foregroundStyle(.secondary)
                }
                Text(recordedDate)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Future days only; today renders as the cake label above.
    private var relativeDay: String {
        birthday.daysUntil == 1 ? "Tomorrow" : "In \(birthday.daysUntil) days"
    }

    private var recordedDate: String {
        // Leap-year reference preserves the recorded 29 Feb on non-leap years.
        let date = BirthdayBoard.calendar.date(from: DateComponents(year: 2000, month: birthday.month, day: birthday.day))!
        // A value-type format style: no DateFormatter built on every body pass.
        let style = Date.FormatStyle(calendar: BirthdayBoard.calendar, timeZone: BirthdayBoard.calendar.timeZone)
            .day()
            .month(.abbreviated)
        return date.formatted(style)
    }
}
