//
//  DistanceText.swift
//  FCTCAttendanceKit
//
//  Kilometre text for distance fields that bind a String, so the model updates on
//  every keystroke. A `TextField(value:format:)` commits only when editing ends,
//  and the decimal pad has no Return key, so a typed distance was lost whenever
//  the user tapped the screen's primary action with the keyboard still up.
//

import Foundation

public enum DistanceText {
    /// Field text is pinned to ASCII digits and a point, with no grouping, so
    /// `format` always round-trips through `parse`. Formatting in the device
    /// locale would seed "٧٫١" on an Arabic-digit phone, which `parse` rejects,
    /// and the sheet's own distance would then read as malformed.
    private static let fieldStyle = FloatingPointFormatStyle<Double>(locale: Locale(identifier: "en_US_POSIX"))
        .precision(.fractionLength(0...2))
        .grouping(.never)

    /// The kilometres typed so far, or nil for blank or unparseable text. The
    /// decimal pad shows a comma in some locales, so both separators parse.
    /// "nan" and "inf" parse as `Double` but are not distances.
    public static func parse(_ text: String) -> Double? {
        let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines).replacing(",", with: "."))
        guard let value, value.isFinite else { return nil }
        return value
    }

    /// True when the user typed something that is not a number, such as "8..2".
    /// Blank text is not malformed: it means "no opinion", and the sheet's
    /// distance stands. A malformed entry must block the save and show why,
    /// or a typo would silently keep the old distance.
    public static func isMalformed(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && parse(text) == nil
    }

    /// The message shown under a malformed distance field.
    public static let malformedMessage = "Enter the kilometres as one number, such as 8.2."

    /// The sheet's distance as field text: up to two decimals, blank for nil.
    public static func format(_ value: Double?) -> String {
        guard let value else { return "" }
        return value.formatted(fieldStyle)
    }
}
