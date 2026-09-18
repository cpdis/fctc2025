import Foundation

public struct UpcomingBirthday: Hashable, Sendable, Identifiable {
    public var name: String
    public var month: Int
    public var day: Int
    public var daysUntil: Int
    public var id: String { name }
}

/// Passive Home list. Today counts as day zero and the final day is included.
public enum BirthdayBoard {
    public static let daysAhead = 30

    /// Club dates remain consistent when a recorder travels or changes device zone.
    public static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Australia/Perth")!
        return calendar
    }

    public static func upcoming(from birthdays: [MemberBirthday], now: Date = .now) -> [UpcomingBirthday] {
        let calendar = Self.calendar
        let today = calendar.startOfDay(for: now)
        let year = calendar.component(.year, from: today)
        return birthdays.filter(\.isValid).compactMap { birthday in
            guard var date = occurrence(of: birthday, year: year, calendar: calendar) else { return nil }
            if date < today {
                guard let next = occurrence(of: birthday, year: year + 1, calendar: calendar) else { return nil }
                date = next
            }
            guard let days = calendar.dateComponents([.day], from: today, to: date).day,
                  (0...daysAhead).contains(days) else { return nil }
            return UpcomingBirthday(name: birthday.name, month: birthday.month, day: birthday.day, daysUntil: days)
        }.sorted {
            $0.daysUntil == $1.daysUntil
                ? Member.sheetOrder($0.name, $1.name)
                : $0.daysUntil < $1.daysUntil
        }
    }

    private static func occurrence(of birthday: MemberBirthday, year: Int, calendar: Calendar) -> Date? {
        var day = birthday.day
        // Keep the saved 29 February; observe it on 28 February in other years.
        let leapYear = year.isMultiple(of: 4) && (!year.isMultiple(of: 100) || year.isMultiple(of: 400))
        if birthday.month == 2 && day == 29 && !leapYear { day = 28 }
        return calendar.date(from: DateComponents(year: year, month: birthday.month, day: day))
    }
}
