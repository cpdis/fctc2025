//
//  BackgroundOutboxDrain.swift
//  FCTCAttendanceKit
//
//  Framework-free scheduling policy. The app target supplies BGTaskScheduler.
//

import Foundation
import SwiftData

public protocol OutboxDraining: Sendable {
    func drain() async
}

extension SyncEngine: OutboxDraining {}

public protocol BackgroundRefreshTaskHandle: Sendable {
    func setExpirationHandler(_ handler: @escaping @Sendable () -> Void)
    func complete(success: Bool)
}

public protocol BackgroundRefreshScheduling: Sendable {
    @discardableResult
    func register(
        identifier: String,
        handler: @escaping @Sendable (any BackgroundRefreshTaskHandle) -> Void
    ) -> Bool
    func submit(identifier: String, earliestBeginDate: Date?) throws
}

public struct BackgroundOutboxState: Hashable, Sendable {
    public var isConfigured: Bool
    public var outstandingCount: Int

    public init(isConfigured: Bool, outstandingCount: Int) {
        self.isConfigured = isConfigured
        self.outstandingCount = outstandingCount
    }

    public var needsDrain: Bool { isConfigured && outstandingCount > 0 }
}

/// Reads only submissions that SyncEngine can drain. Conflicts require a human
/// choice and must not keep rescheduling background refresh tasks forever.
public actor BackgroundOutboxStateReader: ModelActor {
    public nonisolated let modelExecutor: any ModelExecutor
    public nonisolated let modelContainer: ModelContainer

    public init(modelContainer: ModelContainer) {
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: context)
        self.modelContainer = modelContainer
    }

    public func state(isConfigured: Bool) throws -> BackgroundOutboxState {
        let queued = SubmissionStatus.queued.rawValue
        let inFlight = SubmissionStatus.inFlight.rawValue
        let descriptor = FetchDescriptor<PendingSubmission>(
            predicate: #Predicate {
                $0.stateRaw == queued || $0.stateRaw == inFlight
            }
        )
        return BackgroundOutboxState(
            isConfigured: isConfigured,
            outstandingCount: try modelContext.fetchCount(descriptor)
        )
    }
}

public final class BackgroundOutboxDrainCoordinator: @unchecked Sendable {
    public static let identifier = "com.cpdis.fctc-attendance.drain"

    private let scheduler: any BackgroundRefreshScheduling
    private let makeEngine: @Sendable () async -> (any OutboxDraining)?
    private let loadState: @Sendable () async -> BackgroundOutboxState
    private let earliestDelay: TimeInterval

    public init(
        scheduler: any BackgroundRefreshScheduling,
        earliestDelay: TimeInterval = 15 * 60,
        makeEngine: @escaping @Sendable () async -> (any OutboxDraining)?,
        loadState: @escaping @Sendable () async -> BackgroundOutboxState
    ) {
        self.scheduler = scheduler
        self.earliestDelay = earliestDelay
        self.makeEngine = makeEngine
        self.loadState = loadState
    }

    @discardableResult
    public func register() -> Bool {
        scheduler.register(identifier: Self.identifier) { [weak self] task in
            self?.handle(task)
        }
    }

    public func scheduleIfNeeded(now: Date = .now) async {
        guard await loadState().needsDrain else { return }
        try? scheduler.submit(
            identifier: Self.identifier,
            earliestBeginDate: now.addingTimeInterval(earliestDelay)
        )
    }

    private func handle(_ task: any BackgroundRefreshTaskHandle) {
        let operation = Task { [weak self] in
            guard let self else {
                task.complete(success: false)
                return
            }
            guard !Task.isCancelled else {
                task.complete(success: false)
                return
            }
            guard await loadState().needsDrain else {
                task.complete(success: true)
                return
            }
            guard let engine = await makeEngine() else {
                task.complete(success: !Task.isCancelled)
                return
            }
            await engine.drain()
            guard !Task.isCancelled else {
                task.complete(success: false)
                return
            }
            await scheduleIfNeeded()
            task.complete(success: true)
        }
        task.setExpirationHandler { operation.cancel() }
    }
}
