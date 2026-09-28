import FCTCAttendanceKit
import SwiftUI

/// Day/month only: the organiser needs the occasion, not an age or birth year.
struct BirthdaysSection: View {
    /// Today and the next 30 days, from `EventsBoard`. Nil means an older server
    /// that sends no birthdays, which has its own empty text. EventsView keeps
    /// the clock, so the window moves at Perth midnight.
    let birthdays: [UpcomingBirthday]?

    var body: some View {
        Section {
            if let birthdays, !birthdays.isEmpty {
                ForEach(birthdays) { birthday in
                    BirthdayRow(birthday: birthday)
                        .accessibilityIdentifier("birthday-row-\(birthday.name)")
                }
            } else {
                Text(birthdays == nil ? "Birthdays are not available yet." : "No birthdays in the next 30 days.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("birthday-empty")
            }
        } header: {
            Text("Birthdays")
                .accessibilityIdentifier("events-birthdays")
        } footer: {
            Text("Today and the next 30 days")
        }
    }
}

private struct BirthdayRow: View {
    let birthday: UpcomingBirthday
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Set on first appear so today's cake gives one small wiggle, not one per
    /// return to the Events tab.
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
        // A value-type format style: no DateFormatter built on every body pass.
        ClubDate(year: 2000, month: birthday.month, day: birthday.day)?
            .formatted(Date.FormatStyle.perth.day().month(.abbreviated)) ?? ""
    }
}
