//
//  AppearanceTests.swift
//  FCTCAttendanceKitTests
//

import FCTCAttendanceKit
import Foundation
import Testing

@Suite("Appearance store")
struct AppearanceTests {

    /// Runs `body` against a throwaway defaults suite and drops its domain after.
    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let name = "appearance-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    @Test("The default accent is the shipped green")
    func defaultAccent() throws {
        try withDefaults { defaults in
            let store = UserDefaultsAppearanceStore(defaults: defaults)
            #expect(store.loadAccent() == .standard)
            #expect(AccentChoice.standard == .green)
        }
    }

    @Test("A saved accent choice round-trips")
    func roundTrip() throws {
        try withDefaults { defaults in
            let store = UserDefaultsAppearanceStore(defaults: defaults)
            store.saveAccent(.purple)
            #expect(store.loadAccent() == .purple)
        }
    }

    @Test("Garbage persistence falls back to the default")
    func garbageFallsBack() throws {
        try withDefaults { defaults in
            defaults.set("mauve-ish", forKey: "fctc.accentColor")
            let store = UserDefaultsAppearanceStore(defaults: defaults)
            #expect(store.loadAccent() == .standard)
        }
    }
}
