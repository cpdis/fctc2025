import Foundation

/// A recurring date from the sheet. Birth years and ages are never stored.
public struct MemberBirthday: Codable, Hashable, Sendable {
    public var name: String
    public var month: Int
    public var day: Int

    public init(name: String, month: Int, day: Int) {
        self.name = name
        self.month = month
        self.day = day
    }

    /// Validate before constructing dates; Calendar otherwise normalizes 31 April.
    public var isValid: Bool {
        let maximumDays = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        guard (1...12).contains(month), !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return (1...maximumDays[month - 1]).contains(day)
    }
}
