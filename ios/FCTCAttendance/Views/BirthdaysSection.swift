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

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        layout {
            Text(birthday.name)
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
            VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
                Text(relativeDay)
                    .foregroundStyle(birthday.daysUntil == 0 ? Color.accentColor : .secondary)
                Text(recordedDate)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var relativeDay: String {
        switch birthday.daysUntil {
        case 0: "Today"
        case 1: "Tomorrow"
        default: "In \(birthday.daysUntil) days"
        }
    }

    private var recordedDate: String {
        // Leap-year reference preserves the recorded 29 Feb on non-leap years.
        let date = BirthdayBoard.calendar.date(from: DateComponents(year: 2000, month: birthday.month, day: birthday.day))!
        let formatter = DateFormatter()
        formatter.calendar = BirthdayBoard.calendar
        formatter.timeZone = BirthdayBoard.calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("dMMM")
        return formatter.string(from: date)
    }
}
