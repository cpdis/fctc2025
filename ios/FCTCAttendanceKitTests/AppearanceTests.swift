//
//  AppearanceTests.swift
//  FCTCAttendanceKitTests
//

import FCTCAttendanceKit
import Foundation
import Testing

@Suite("Appearance store")
struct AppearanceTests {

    private func makeDefaults() -> UserDefaults {
        let name = "appearance-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("The default accent is the shipped green")
    func defaultAccent() {
        let store = UserDefaultsAppearanceStore(defaults: makeDefaults())
        #expect(store.loadAccent() == .standard)
        #expect(AccentChoice.standard == .green)
    }

    @Test("A saved accent choice round-trips")
    func roundTrip() {
        let store = UserDefaultsAppearanceStore(defaults: makeDefaults())
        store.saveAccent(.purple)
        #expect(store.loadAccent() == .purple)
    }

    @Test("Garbage persistence falls back to the default")
    func garbageFallsBack() {
        let defaults = makeDefaults()
        defaults.set("mauve-ish", forKey: "fctc.accentColor")
        let store = UserDefaultsAppearanceStore(defaults: defaults)
        #expect(store.loadAccent() == .standard)
    }
}
