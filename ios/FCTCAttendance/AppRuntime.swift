//
//  AppRuntime.swift
//  FCTCAttendance
//
//  Owns the replaceable SyncEngine client. Saving Settings creates a new engine so
//  the immutable SheetAPI configuration changes without restarting the app.
//

import FCTCAttendanceKit
import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class AppRuntime {
    let modelContainer: ModelContainer
    let configPersistence: any AppConfigPersisting
    private(set) var config: AppConfig
    private(set) var engine: any SyncEngineClient
    private(set) var generation = 0
    private(set) var accent: AccentChoice
    private(set) var runRemindersEnabled: Bool
    private(set) var reminderMessage: String?
    let reminderService: any RunReminderManaging
    let sharedScreenshotInbox: SharedScreenshotInbox

    /// This launch's Milestones empty-state line, chosen once at startup.
    let milestoneEmptyPhrase: String

    @ObservationIgnored private let appearanceStore: any AppearanceStoring

    init(
        modelContainer: ModelContainer,
        configPersistence: any AppConfigPersisting = UserDefaultsAppConfigPersistence(),
        appearanceStore: any AppearanceStoring = UserDefaultsAppearanceStore(),
        reminderService: (any RunReminderManaging)? = nil,
        sharedScreenshotInbox: SharedScreenshotInbox = SharedScreenshotInbox(),
        engineOverride: (any SyncEngineClient)? = nil,
        configOverride: AppConfig? = nil
    ) {
        self.modelContainer = modelContainer
        self.configPersistence = configPersistence
        self.appearanceStore = appearanceStore
        self.accent = appearanceStore.loadAccent()
        let reminders = reminderService ?? RunReminderService()
        self.reminderService = reminders
        self.runRemindersEnabled = reminders.isEnabled
        self.reminderMessage = nil
        self.sharedScreenshotInbox = sharedScreenshotInbox
        // Drawn once per launch and held. Rolling this inside a view body would
        // change the line on every state change while the app is in use.
        var generator = SystemRandomNumberGenerator()
        self.milestoneEmptyPhrase = MilestonePhrases.drawForLaunch(generator: &generator)
        let loaded = configOverride ?? (try? configPersistence.load()) ?? AppConfig()
        self.config = loaded
        self.engine = engineOverride ?? SyncEngine(
            modelContainer: modelContainer,
            api: SheetAPI(config: loaded),
            runReminderScheduler: reminders
        )
    }

    func setAccent(_ choice: AccentChoice) {
        accent = choice
        appearanceStore.saveAccent(choice)
    }

    func apply(_ config: AppConfig, engineOverride: (any SyncEngineClient)? = nil) {
        self.config = config
        engine = engineOverride ?? SyncEngine(
            modelContainer: modelContainer,
            api: SheetAPI(config: config),
            runReminderScheduler: reminderService
        )
        generation += 1
    }

    func setRunRemindersEnabled(_ enabled: Bool) async {
        reminderMessage = nil
        let result = await reminderService.setEnabled(enabled)
        runRemindersEnabled = reminderService.isEnabled
        switch result {
        case .enabled:
            do {
                _ = try await engine.refreshState()
                reminderMessage = if await reminderService.lastReconcileResult == .failed {
                    "Run reminders are on, but scheduling failed. Try again."
                } else {
                    "Run reminders are on."
                }
            } catch {
                reminderMessage = "Run reminders are on. Connect to refresh the schedule."
            }
        case .disabled:
            reminderMessage = "Run reminders are off."
        case .denied:
            reminderMessage = "Notifications are off in system settings."
        case .failed:
            reminderMessage = "The app could not update notification permission."
        }
    }
}
