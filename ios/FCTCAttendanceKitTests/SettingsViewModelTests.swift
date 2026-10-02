//
//  SettingsViewModelTests.swift
//  FCTCAttendanceKitTests
//
//  U4: settings actions and scanned-config persistence.
//

import Foundation
import Testing

@testable import FCTCAttendanceKit

extension ViewModelTests {
    @Test("Settings load, save, QR import, and refresh use their protocol seams")
    func settingsActions() async throws {
        let persistence = MemoryConfigPersistence(
            config: AppConfig(
                endpoint: URL(string: "https://example.test/exec"),
                secret: "old-secret",
                deviceName: "Colin's iPhone"
            )
        )
        let client = ViewModelSyncClient()
        let viewModel = SettingsViewModel(persistence: persistence, engine: client)

        #expect(viewModel.endpoint == "https://example.test/exec")
        let saved = try viewModel.importAndSaveSetupCode(
            """
            {"endpoint":"https://new.example/exec","secret":"new-secret","deviceName":"Run phone"}
            """
        )
        try await viewModel.refreshRoster()

        #expect(saved.secret == "new-secret")
        #expect(try persistence.load() == saved)
        #expect(await client.refreshCount == 1)
    }

    @Test("Scanned config persistence sends the secret only to its secure seam")
    func configPersistenceSeparatesSecret() throws {
        let suite = "FCTCAttendanceKitTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let secretStore = MemorySecretStore()
        let persistence = UserDefaultsAppConfigPersistence(
            defaults: defaults,
            secretStore: secretStore
        )
        let viewModel = SettingsViewModel(
            persistence: persistence,
            engine: ViewModelSyncClient()
        )

        let config = try viewModel.importAndSaveSetupCode(
            """
            {"endpoint":"https://example.test/exec","secret":"qr-secret-not-real","deviceName":"Run phone"}
            """
        )

        #expect(try persistence.load() == config)
        #expect(secretStore.value == "qr-secret-not-real")
        #expect(!defaults.dictionaryRepresentation().values.contains {
            ($0 as? String) == "qr-secret-not-real"
        })
    }

    @Test("Saving an empty secret deletes the stored one")
    func emptySecretDeletes() throws {
        let suite = "FCTCAttendanceKitTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let secretStore = MemorySecretStore()
        secretStore.value = "old-secret-not-real"
        let persistence = UserDefaultsAppConfigPersistence(defaults: defaults, secretStore: secretStore)

        var config = try persistence.load()
        config.secret = ""
        try persistence.save(config)

        // Deleted (nil), not overwritten with an empty string.
        #expect(secretStore.value == nil)
        #expect(try persistence.load().secret == "")
    }
}
