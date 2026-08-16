//
//  AppearanceStore.swift
//  FCTCAttendanceKit
//
//  The user's accent-color choice (Colin's review, 2026-08-14). Pure preference:
//  it never travels in the setup QR and never touches the sheet config.
//

import Foundation

/// The Reminders-style accent palette. Raw values are the persistence format.
public enum AccentChoice: String, CaseIterable, Codable, Sendable {
    case green
    case blue
    case orange
    case pink
    case purple
    case red
    case teal

    /// The shipped default matches the asset-catalog AccentColor.
    public static let standard = AccentChoice.green

    /// Human label for the picker row and VoiceOver.
    public var label: String { rawValue.capitalized }
}

public protocol AppearanceStoring: Sendable {
    func loadAccent() -> AccentChoice
    func saveAccent(_ choice: AccentChoice)
}

public final class UserDefaultsAppearanceStore: AppearanceStoring, @unchecked Sendable {
    private static let key = "fctc.accentColor"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func loadAccent() -> AccentChoice {
        defaults.string(forKey: Self.key)
            .flatMap(AccentChoice.init(rawValue:)) ?? .standard
    }

    public func saveAccent(_ choice: AccentChoice) {
        defaults.set(choice.rawValue, forKey: Self.key)
    }
}
