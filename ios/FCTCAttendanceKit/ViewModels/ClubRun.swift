//
//  ClubRun.swift
//  FCTCAttendanceKit
//
//  The UI-free run value the club-day rules and the Dashboard consume.
//
//  Dates are civil calendar days, never instants. The sheet writes "Fri, 25-Sep"
//  and the season supplies the year, so a run's day comes straight from that text
//  and no time zone can move it:
//
//    RunRecord / RunSnapshot   "Fri, 25-Sep" + season 2026
//          | ClubDate(sheetDate:season:)
//          v
//    ClubDate 2026-09-25, weekday .fri   (Gregorian, Australia/Perth)
//
//  The app's `SyncEngine.parseDate` reads the same text into `scheduledAt` at
//  midnight in the DEVICE zone. The snapshot adapter prefers the text; when a row
//  has no season year it reads `scheduledAt` back in the device calendar, the zone
//  that parse used, so the two paths always land on the same day. Weekdays and day
//  arithmetic use a Gregorian calendar pinned to Australia/Perth, the club's zone.
//  For a civil date any fixed zone gives the same answer; pinning one keeps the
//  maths independent of the phone's settings.
//

import Foundation

/// A day of the week in calendar order, Monday first (the club's week).
public enum Weekday: Int, CaseIterable, Comparable, Hashable, Sendable {
    case mon = 1, tue, wed, thu, fri, sat, sun

    /// The sheet's three-letter name ("Mon"), also the web's `dayOfWeek`.
    public var shortName: String {
        switch self {
        case .mon: "Mon"
        case .tue: "Tue"
        case .wed: "Wed"
        case .thu: "Thu"
        case .fri: "Fri"
        case .sat: "Sat"
        case .sun: "Sun"
        }
    }

    public init?(shortName: String) {
        guard let match = Self.allCases.first(where: { $0.shortName == shortName }) else { return nil }
        self = match
    }

    /// Foundation's weekday component counts Sunday = 1 ... Saturday = 7.
    init(foundationWeekday: Int) {
        self = Weekday(rawValue: (foundationWeekday + 5) % 7 + 1) ?? .mon
    }

    public static func < (lhs: Weekday, rhs: Weekday) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// A calendar day with no time and no zone: the unit every club rule counts in.
public struct ClubDate: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int
    public let weekday: Weekday

    /// Gregorian in the club's zone. Perth has no daylight saving, and every
    /// conversion goes through noon, so no day ever slips across midnight.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        // GMT is only a never-taken fallback; civil-date maths is right in any fixed zone.
        calendar.timeZone = TimeZone(identifier: "Australia/Perth") ?? .gmt
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()

    /// Lowercased month prefixes, the web's `MONTHS` and Apps Script's `MONTH_ABBREVS`.
    private static let months = ["jan", "feb", "mar", "apr", "may", "jun",
                                 "jul", "aug", "sep", "oct", "nov", "dec"]

    /// A real calendar day, or nil ("31-Sep" never rolls into October).
    public init?(year: Int, month: Int, day: Int) {
        let noon = DateComponents(year: year, month: month, day: day, hour: 12)
        guard let date = Self.calendar.date(from: noon) else { return nil }
        let back = Self.calendar.dateComponents([.year, .month, .day, .weekday], from: date)
        guard back.year == year, back.month == month, back.day == day,
              let weekday = back.weekday else { return nil }
        self.year = year
        self.month = month
        self.day = day
        self.weekday = Weekday(foundationWeekday: weekday)
    }

    /// Parse an ISO "YYYY-MM-DD" day, as the parity fixtures write it.
    public init?(iso: String) {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    /// Parse the sheet's run-date cell for a season year, exactly as the web's
    /// `parseRunDate` and Apps Script's `parseSheetDate` read it: the first
    /// 1-2 digit day, a "-", "/" or space (optionally padded), then a month word
    /// of 3+ letters, anywhere in the cell. The month is that word's first three
    /// letters in any case, so "Fri, 25-Sep", "Fri 25-Sep", "25-Sep",
    /// "Thurs, 1-Oct" and "Fri, 25-Sept" are all 25 Sep or 1 Oct.
    ///
    /// The weekday comes from the calendar, never the typed text: a copied row
    /// reading "Wed, 2-Oct" in 2026 is a Friday. Metadata labels ("BIRTHDAY",
    /// "Notes"), unknown months ("3-Foo") and impossible days ("31-Sep",
    /// "0-Oct") return nil, as does a missing season (0 or less).
    ///
    /// This is the app's only sheet-date parser: the run cache's `scheduledAt`,
    /// the reminders and the Dashboard all read dates through it.
    public init?(sheetDate: String, season: Int) {
        // `[0-9]`, not `\d`: Swift's `\d` also takes non-ASCII digits, JS's does not.
        guard season > 0,
              let match = sheetDate.firstMatch(of: /([0-9]{1,2})\s*[-\/ ]\s*([A-Za-z]{3,})/),
              let day = Int(match.1),
              let month = Self.months.firstIndex(of: match.2.prefix(3).lowercased()) else { return nil }
        // The calendar round-trip in `init(year:month:day:)` rejects 31-Sep and 0-Oct.
        self.init(year: season, month: month + 1, day: day)
    }

    /// Read an instant back into the day it names in `calendar`. Pass the
    /// calendar that made the instant (the device calendar for `scheduledAt`).
    public init?(_ date: Date, calendar: Calendar) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
        self.init(year: year, month: month, day: day)
    }

    /// Midnight at the start of this day in `calendar`'s time zone. The run
    /// cache's `scheduledAt` and the reminders store this instant; pass the
    /// same calendar to `init(_:calendar:)` to read the day back.
    public func startOfDay(in calendar: Calendar) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    /// "2026-09-25": the web's `isoDate` and the fixtures' key.
    public var iso: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public var description: String { iso }

    /// Days since 1 Jan of this date's own year (1 Jan is 0), for season overlays.
    public var dayOfYear: Int {
        (Self.calendar.ordinality(of: .day, in: .year, for: noon) ?? 1) - 1
    }

    /// The Monday of this date's week.
    public var startOfWeek: ClubDate {
        adding(days: -(weekday.rawValue - 1))
    }

    /// The day `days` later (earlier when negative).
    public func adding(days: Int) -> ClubDate {
        guard let moved = Self.calendar.date(byAdding: .day, value: days, to: noon),
              let result = ClubDate(moved, calendar: Self.calendar) else { return self }
        return result
    }

    /// True when this day falls on or before the same month and day of any year.
    /// Month and day (not day of year) keep 25 Sep against 25 Sep across a leap year.
    public func isOnOrBefore(monthDayOf other: ClubDate) -> Bool {
        (month, day) <= (other.month, other.day)
    }

    public static func < (lhs: ClubDate, rhs: ClubDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    private var noon: Date {
        Self.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? .distantPast
    }
}

/// One sheet run as the club-day rules and the Dashboard see it (KTD10).
///
/// The app adapts its cached or effective runs into this; the parity tests build
/// it straight from the golden fixtures. `label` and `location` are parsed once
/// here, so every card reads the same normalized names (R7).
public struct ClubRun: Hashable, Sendable, Identifiable {
    /// Stable within a season: the run's cache key, or the fixture's run id.
    public let id: String
    public let date: ClubDate
    /// The season year, which picks the club weekdays (KTD2).
    public let season: Int
    /// The "Run" cell as typed ("**Cruise").
    public let run: String
    /// The "Meet" cell as typed ("Some-day").
    public let meet: String
    public let label: RunLabel
    public let location: String
    /// Nil when the sheet has no distance; such a run adds 0 km.
    public let actualKm: Double?
    /// Member names, trimmed and NFC-normalized, in the order given.
    public let attendees: [String]
    public let plusOnes: Int

    public init(
        id: String,
        date: ClubDate,
        season: Int,
        run: String,
        meet: String,
        actualKm: Double?,
        attendees: [String],
        plusOnes: Int
    ) {
        self.id = id
        self.date = date
        self.season = season
        self.run = run
        self.meet = meet
        self.label = RunLabel(run)
        self.location = RunLabel.location(meet)
        self.actualKm = actualKm
        self.attendees = attendees.map(Self.memberName)
        self.plusOnes = plusOnes
    }

    /// Adapt a cached (or effective) run. The day comes from the sheet's date
    /// text and season year, the inputs `SyncEngine.parseDate` reads. A row with
    /// no season year falls back to `scheduledAt` in `deviceCalendar`, the zone
    /// that parse used. Nil when the row has no usable date at all.
    public init?(_ snapshot: RunSnapshot, deviceCalendar: Calendar = .current) {
        let season = snapshot.seasonYear.flatMap { $0 > 0 ? $0 : nil }
        guard let date = season.flatMap({ ClubDate(sheetDate: snapshot.date, season: $0) })
            ?? snapshot.scheduledAt.flatMap({ ClubDate($0, calendar: deviceCalendar) })
        else { return nil }
        self.init(
            id: snapshot.id, date: date, season: season ?? date.year,
            run: snapshot.run, meet: snapshot.meet, actualKm: snapshot.actualKm,
            attendees: snapshot.attendees, plusOnes: snapshot.plusOnes
        )
    }

    /// Adapt a server run from a `SheetState` (last season's snapshot).
    public init?(_ record: RunRecord, season: Int) {
        guard let date = ClubDate(sheetDate: record.date, season: season) else { return nil }
        self.init(
            id: record.identity?.cacheKey ?? "legacy:\(record.rowIndex)", date: date, season: season,
            run: record.run, meet: record.meet, actualKm: record.actualKm,
            attendees: record.attendees, plusOnes: record.plusOnes
        )
    }

    public var weekday: Weekday { date.weekday }

    /// A run is a row with at least one attendee or +1 (R2). Planned rows and
    /// blank past rows are not runs.
    public var isRecorded: Bool { !attendees.isEmpty || plusOnes > 0 }

    /// Actual km once per attending member, +1s excluded ("km together").
    public var memberKm: Double { (actualKm ?? 0) * Double(attendees.count) }

    /// Members plus +1s: everyone on the run.
    public var headcount: Int { attendees.count + plusOnes }

    /// The one member-name form every rule compares: trimmed and NFC, matching
    /// the web parser. Swift's `==` already ignores NFC/NFD; the fixed form keeps
    /// code-unit sorting stable too.
    public static func memberName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
    }
}

/// Plain UTF-16 code-unit order, the JS `<` on strings, so names sort exactly as
/// the web and the fixtures sort them (not locale collation).
func codeUnitPrecedes(_ lhs: String, _ rhs: String) -> Bool {
    lhs.utf16.lexicographicallyPrecedes(rhs.utf16)
}
