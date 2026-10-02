//
//  BackgroundOutboxDrain.swift
//  FCTCAttendance
//
//  BGAppRefreshTask adapter, and the factory that lends the background task
//  the runtime's one engine.
//

import BackgroundTasks
import FCTCAttendanceKit
import Foundation
import SwiftData

/// Stateless, so plainly `Sendable`.
struct SystemBackgroundRefreshScheduler: BackgroundRefreshScheduling {
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

/// `BGTask` is not `Sendable`, but the system documents its expiration handler
/// and `setTaskCompleted` as callable from any thread, so this wrapper is the
/// one place `@unchecked` is earned.
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
    /// The background task drains through `runtime.engine`, the process's
    /// one drain owner, and reads the settings the runtime already holds
    /// instead of reading the keychain again (CC-2, PLAT-2).
    @MainActor
    static func make(runtime: AppRuntime) -> BackgroundOutboxDrainCoordinator {
        let reader = BackgroundOutboxStateReader(modelContainer: runtime.modelContainer)
        return BackgroundOutboxDrainCoordinator(
            scheduler: SystemBackgroundRefreshScheduler(),
            makeEngine: {
                await MainActor.run {
                    runtime.reloadConfigIfLocked()
                    return runtime.config.isConfigured ? runtime.engine : nil
                }
            },
            loadState: {
                // A locked keychain still has a sheet behind it: keep the
                // work scheduled so a later task retries.
                let configured = await MainActor.run {
                    runtime.reloadConfigIfLocked()
                    return runtime.config.isConfigured || runtime.isSecretLocked
                }
                return (try? await reader.state(isConfigured: configured))
                    ?? BackgroundOutboxState(isConfigured: configured, outstandingCount: 0)
            }
        )
    }
}
