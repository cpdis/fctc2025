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

    init(
        modelContainer: ModelContainer,
        configPersistence: any AppConfigPersisting = UserDefaultsAppConfigPersistence(),
        engineOverride: (any SyncEngineClient)? = nil,
        configOverride: AppConfig? = nil
    ) {
        self.modelContainer = modelContainer
        self.configPersistence = configPersistence
        let loaded = configOverride ?? (try? configPersistence.load()) ?? AppConfig()
        self.config = loaded
        self.engine = engineOverride ?? SyncEngine(
            modelContainer: modelContainer,
            api: SheetAPI(config: loaded)
        )
    }

    func apply(_ config: AppConfig, engineOverride: (any SyncEngineClient)? = nil) {
        self.config = config
        engine = engineOverride ?? SyncEngine(
            modelContainer: modelContainer,
            api: SheetAPI(config: config)
        )
        generation += 1
    }
}
