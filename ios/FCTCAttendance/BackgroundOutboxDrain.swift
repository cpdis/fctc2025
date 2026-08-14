//
//  BackgroundOutboxDrain.swift
//  FCTCAttendance
//
//  BGAppRefreshTask adapter and fresh-engine factory.
//

import BackgroundTasks
import FCTCAttendanceKit
import Foundation
import SwiftData

struct SystemBackgroundRefreshScheduler: BackgroundRefreshScheduling, @unchecked Sendable {
    func register(
        identifier: String,
        handler: @escaping @Sendable (any BackgroundRefreshTaskHandle) -> Void
    ) -> Bool {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            handler(SystemBackgroundRefreshTask(task: task))
        }
    }

    func submit(identifier: String, earliestBeginDate: Date?) throws {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = earliestBeginDate
        try BGTaskScheduler.shared.submit(request)
    }
}

private final class SystemBackgroundRefreshTask: BackgroundRefreshTaskHandle, @unchecked Sendable {
    private let task: BGTask

    init(task: BGTask) {
        self.task = task
    }

    func setExpirationHandler(_ handler: @escaping @Sendable () -> Void) {
        task.expirationHandler = handler
    }

    func complete(success: Bool) {
        task.setTaskCompleted(success: success)
    }
}

enum BackgroundOutboxDrainFactory {
    static func make(
        modelContainer: ModelContainer,
        persistence: any AppConfigPersisting
    ) -> BackgroundOutboxDrainCoordinator {
        let reader = BackgroundOutboxStateReader(modelContainer: modelContainer)
        return BackgroundOutboxDrainCoordinator(
            scheduler: SystemBackgroundRefreshScheduler(),
            makeEngine: {
                guard let config = try? persistence.load(), config.isConfigured else { return nil }
                return SyncEngine(
                    modelContainer: modelContainer,
                    api: SheetAPI(config: config)
                )
            },
            loadState: {
                let configured = ((try? persistence.load()) ?? AppConfig()).isConfigured
                return (try? await reader.state(isConfigured: configured))
                    ?? BackgroundOutboxState(isConfigured: configured, outstandingCount: 0)
            }
        )
    }
}
