//
//  UpcomingSections.swift
//  FCTCAttendance
//
//  The Events tab's forward-looking sections (R22): this week's club runs and
//  the specials ahead. Passive rows in the Home list style; `EventsBoard` has
//  already decided what goes in each, so these views only draw it:
//
//    [ MON ]  Intervals                    [ SUN ]  Xmas
//    [ 28  ]  Drift · 10 km                [ 13  ]  Alex 👑's · Dec · Mara / Half / 10k
//

import FCTCAttendanceKit
import SwiftUI

struct ThisWeekSection: View {
    let runs: [UpcomingRun]

    var body: some View {
        Section {
            if runs.isEmpty {
                EmptyLine(text: "No more runs this week.", identifier: "week-empty")
            } else {
                ForEach(runs) { run in
                    EventRow(date: run.date, title: run.title, detail: detail(for: run))
                        .accessibilityIdentifier("week-row-\(run.id)")
                }
            }
        } header: {
            Text("This week")
                .accessibilityIdentifier("events-this-week")
        }
    }

    /// "Drift · 10 km". Either half drops out when the sheet leaves it blank.
    private func detail(for run: UpcomingRun) -> String {
        let km = run.approxKm.map { "\($0.formatted(.number.precision(.fractionLength(0...2)))) km" }
        return [run.location, km].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

struct SpecialsSection: View {
    let specials: [SpecialDay]

    var body: some View {
        Section {
            if specials.isEmpty {
                EmptyLine(text: "No specials scheduled.", identifier: "specials-empty")
            } else {
                ForEach(specials) { special in
                    EventRow(date: special.date, title: special.title, detail: detail(for: special))
                        .accessibilityIdentifier("special-row-\(special.date.iso)")
                }
            }
        } header: {
            Text("Specials")
                .accessibilityIdentifier("events-specials")
        }
    }

    /// "Alex 👑's · Dec · Mara / Half / 10k". The month sits here because the
    /// date block shows only the weekday and day, and specials run months ahead.
    private func detail(for special: SpecialDay) -> String {
        [special.location, special.date.formatted(Date.FormatStyle.perth.month(.abbreviated)), special.optionsLabel]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

/// A date block, a title and one line of detail.
private struct EventRow: View {
    let date: ClubDate
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            DateBlock(date: date)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        // The block's "MON 28" reads badly aloud; say the whole date first.
        .accessibilityLabel(
            [date.formatted(Date.FormatStyle.perth.weekday(.wide).day().month(.wide)), title, detail]
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
        )
    }
}

/// The weekday over the day of the month, like a calendar page.
private struct DateBlock: View {
    let date: ClubDate
    /// Grows with Dynamic Type so large day numbers never clip.
    @ScaledMetric(relativeTo: .title2) private var width = 44

    var body: some View {
        VStack(spacing: 0) {
            Text(date.formatted(Date.FormatStyle.perth.weekday(.abbreviated)).uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.6)
                .foregroundStyle(.tint)
            Text(date.day, format: .number)
                .font(.title2)
                .monospacedDigit()
        }
        .frame(width: width)
        .accessibilityHidden(true)
    }
}

/// The secondary one-liner an empty section shows, as Birthdays does.
private struct EmptyLine: View {
    let text: String
    let identifier: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier(identifier)
    }
}

extension Date.FormatStyle {
    /// An empty style on the club's calendar and zone. Add fields to it.
    static var perth: Self {
        Date.FormatStyle(calendar: BirthdayBoard.calendar, timeZone: BirthdayBoard.calendar.timeZone)
    }
}

extension ClubDate {
    /// This day formatted in Perth. Noon keeps every zone on the same day.
    func formatted(_ style: Date.FormatStyle) -> String {
        let noon = BirthdayBoard.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))
        return noon?.formatted(style) ?? iso
    }
}
