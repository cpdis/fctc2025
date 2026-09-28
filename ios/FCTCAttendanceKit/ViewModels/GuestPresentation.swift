import Foundation

/// Names are search labels. Only an explicit choice binds a label to a guest ID.
public enum GuestNames {
    public static func canonical(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
    }
}

public struct GuestAttendanceDiff: Equatable, Sendable {
    public var added: [String]
    public var removed: [String]
    public var unnamedBefore: Int
    public var unnamedAfter: Int
    public var summary: String {
        var parts: [String] = []
        if !added.isEmpty { parts.append("Add guests: \(added.joined(separator: ", "))") }
        if !removed.isEmpty { parts.append("Remove guests: \(removed.joined(separator: ", "))") }
        if unnamedBefore != unnamedAfter { parts.append("Unnamed guests: \(unnamedBefore) → \(unnamedAfter)") }
        return parts.isEmpty ? "Guest attendance stays the same" : parts.joined(separator: ". ")
    }
}

extension RunSnapshot {
    public init(record: RunRecord, state: SheetState, endpointIdentity: String?) {
        self.init(rowIndex: record.rowIndex, date: record.date,
                  scheduledAt: Self.guestRunDate(record.date, season: state.seasonYear),
                  meet: record.meet, run: record.run, approxKm: record.approxKm, actualKm: record.actualKm,
                  attendees: record.attendees, plusOnes: record.plusOnes, cachedRevision: state.sheetRevision,
                  runIdentity: record.identity, endpointIdentity: endpointIdentity,
                  namedGuestIds: record.namedGuestIds ?? [], unnamedGuests: record.unnamedGuests,
                  seasonYear: record.seasonYear ?? state.seasonYear)
    }
    /// Midnight of the run's day on the device, as the run cache stores it.
    private static func guestRunDate(_ value: String, season: Int) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return ClubDate(sheetDate: value, season: season)?.startOfDay(in: calendar)
    }
}

/// Cache navigation must never combine two workbooks or two seasons with equal row numbers.
public enum RunCacheScope {
    public static func runs(_ runs: [RunSnapshot], endpoint: String?, state: SheetState?) -> [RunSnapshot] {
        guard let state, let book = state.spreadsheetId, let season = state.seasonSheetId else {
            return runs.filter { $0.runIdentity == nil }
        }
        return runs.filter {
            $0.endpointIdentity == endpoint && $0.runIdentity?.spreadsheetId == book && $0.runIdentity?.seasonSheetId == season
        }
    }
}
