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
    var activeState: SheetState?
    private(set) var accent: AccentChoice
    private(set) var runRemindersEnabled: Bool
    private(set) var reminderMessage: String?
    let reminderService: any RunReminderManaging
    let sharedScreenshotInbox: SharedScreenshotInbox

    /// This launch's Milestones empty-state line, chosen once at startup.
    let milestoneEmptyPhrase: String

    /// The Events tab's clock. Real time, except a `-ui-events` UI-test launch,
    /// which pins it (`UITestSupport.now`) so that fixture's week has the same
    /// shape on whatever day the suite runs.
    let now: () -> Date

    @ObservationIgnored private let appearanceStore: any AppearanceStoring

    init(
        modelContainer: ModelContainer,
        configPersistence: any AppConfigPersisting = UserDefaultsAppConfigPersistence(),
        appearanceStore: any AppearanceStoring = UserDefaultsAppearanceStore(),
        reminderService: (any RunReminderManaging)? = nil,
        sharedScreenshotInbox: SharedScreenshotInbox = SharedScreenshotInbox(),
        engineOverride: (any SyncEngineClient)? = nil,
        configOverride: AppConfig? = nil,
        now: @escaping () -> Date = { .now }
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
        self.now = now
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

    /// Historic navigation refreshes another season without changing Home's scope.
    var activeSheetState: SheetState? {
        activeSheetCache?.state
    }

    /// The active season's state with its cache row's last refresh, which the
    /// outbox overlay needs (`EffectiveRuns`, KTD11). `refreshedAt` is nil when
    /// only the in-memory state exists, as on a legacy endpoint. It fetches and
    /// decodes the cache, so read it once per data change, never per render.
    var activeSheetCache: (state: SheetState, refreshedAt: Date?)? {
        let endpoint = config.endpoint?.absoluteString
        let caches = (try? modelContainer.mainContext.fetch(FetchDescriptor<SharedSheetCache>())) ?? []
        if let activeState {
            let row = caches.first { $0.endpointIdentity == endpoint
                && $0.spreadsheetId == activeState.spreadsheetId && $0.seasonSheetId == activeState.seasonSheetId }
            return (row?.state ?? activeState, row?.refreshedAt)
        }
        // The highest season year wins; the first such row breaks a tie. Each
        // row decodes once.
        let rows = caches.filter { $0.endpointIdentity == endpoint }.map { (state: $0.state, refreshedAt: $0.refreshedAt) }
        guard let newest = rows.max(by: { ($0.state?.seasonYear ?? 0) < ($1.state?.seasonYear ?? 0) }),
              let state = newest.state else { return nil }
        return (state, newest.refreshedAt)
    }

    /// The cached runs that belong to this connection's active season. The run
    /// cache can hold other endpoints' and seasons' rows, so Runs, Events and
    /// route handling all scope it the same way before reading it. It reads
    /// `activeSheetState`, so call it once per `activeRunsFingerprint` change.
    func activeRuns(in cachedRuns: [ScheduledRun]) -> [ScheduledRun] {
        let endpoint = config.endpoint?.absoluteString
        let ids = Set(RunCacheScope.runs(cachedRuns.map(RunSnapshot.init), endpoint: endpoint,
                                        state: activeSheetState).map(\.id))
        return cachedRuns.filter { ids.contains($0.cacheKey) && ($0.identity == nil || $0.endpointIdentity == endpoint) }
    }

    /// A cheap key for `activeRuns(in:)`: it changes whenever that answer can,
    /// and it decodes no JSON, so a view builds it per render and resolves the
    /// runs only when it moves (KTD10):
    ///
    ///   @Query rows ──> activeRunsFingerprint (cheap) ──changed──> activeRuns(in:)
    ///                                                              (fetch + decode)
    ///
    /// It covers the connection, the live state, every cached run (each cache
    /// write stamps the sheet's revision, a hash of the run rows) and each
    /// refresh of this connection's season caches, which can move the scope.
    func activeRunsFingerprint(runs: [ScheduledRun], caches: [SharedSheetCache]) -> String {
        let endpoint = config.endpoint?.absoluteString ?? ""
        let live = activeState.map { "\($0.spreadsheetId ?? ""):\($0.seasonSheetId ?? 0):\($0.sheetRevision)" }
        let runs = runs.map { "\($0.cacheKey):\($0.cachedRevision ?? ""):\($0.attendees.count):\($0.plusOnes)" }
        let caches = caches.filter { $0.endpointIdentity == endpoint }
            .map { "\($0.key):\($0.refreshedAt.timeIntervalSinceReferenceDate)" }
        return ([endpoint, live ?? ""] + runs + caches).joined(separator: "|")
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
        activeState = nil
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
