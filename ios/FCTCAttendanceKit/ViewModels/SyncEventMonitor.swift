//
//  SyncEventMonitor.swift
//  FCTCAttendanceKit
//
//  MainActor bridge for the SyncEngine AsyncStream. Each view model owns one bridge
//  and receives only Sendable SyncEvent values from the actor.
//

import Foundation

@MainActor
final class SyncEventMonitor {
    private var task: Task<Void, Never>?

    func start(
        engine: any SyncEngineClient,
        receive: @escaping @MainActor @Sendable (SyncEvent) -> Void
    ) {
        task?.cancel()
        let events = engine.events
        task = Task { @MainActor in
            for await event in events {
                guard !Task.isCancelled else { return }
                receive(event)
            }
        }
    }

    deinit {
        task?.cancel()
    }
}
