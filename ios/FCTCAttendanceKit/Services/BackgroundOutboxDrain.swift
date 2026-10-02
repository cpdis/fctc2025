//
//  BackgroundOutboxDrain.swift
//  FCTCAttendanceKit
//
//  Framework-free scheduling policy. The app target supplies BGTaskScheduler.
//

import Foundation
import os
import SwiftData
import Synchronization

/// Anything that can drain the outbox. `SyncEngineClient` inherits it, so the
/// background task borrows the app's one engine instead of building a second
/// engine over the same store.
public protocol OutboxDraining: Sendable {
    func drain() async
}

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
    /// The app has a sheet to drain to. A keychain that is locked for now
    /// still counts: the secret is there, and the task retries later.
    public var isConfigured: Bool
    public var outstandingCount: Int

    public init(isConfigured: Bool, outstandingCount: Int) {
        self.isConfigured = isConfigured
        self.outstandingCount = outstandingCount
    }

    public var needsDrain: Bool { isConfigured && outstandingCount > 0 }
}

/// Counts the work SyncEngine can drain: queued or in-flight submissions and
/// queued or checking guest operations. Conflicts need a human choice and must
/// not keep rescheduling background refresh tasks forever.
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
        let submissions = FetchDescriptor<PendingSubmission>(
            predicate: #Predicate {
                $0.stateRaw == queued || $0.stateRaw == inFlight
            }
        )
        // A guest operation the drain still owes the sheet: unsent, or sent
        // with its receipt not yet checked (CA-14).
        let opQueued = GuestOperationPhase.queued.rawValue
        let opChecking = GuestOperationPhase.checking.rawValue
        let operations = FetchDescriptor<PendingGuestOperation>(
            predicate: #Predicate {
                $0.phaseRaw == opQueued || $0.phaseRaw == opChecking
            }
        )
        let submissionCount = try modelContext.fetchCount(submissions)
        let operationCount = try modelContext.fetchCount(operations)
        return BackgroundOutboxState(
            isConfigured: isConfigured,
            outstandingCount: submissionCount + operationCount
        )
    }
}

public final class BackgroundOutboxDrainCoordinator: Sendable {
    public static let identifier = "com.cpdis.fctc-attendance.drain"
    private static let logger = Logger(subsystem: "com.cpdis.fctc-attendance", category: "background")

    private let scheduler: any BackgroundRefreshScheduling
    private let makeEngine: @Sendable () async -> (any OutboxDraining)?
    private let loadState: @Sendable () async -> BackgroundOutboxState
    private let earliestDelay: TimeInterval

    /// `makeEngine` returns the process's one drain owner, or nil when it
    /// cannot drain now (not set up, or the keychain is locked).
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
        _ = await submitIfNeeded(now: now)
    }

    /// Submits the next request when work is outstanding, and says whether
    /// there was work. A failed submit is logged, never thrown: the next
    /// trip to the background tries again.
    private func submitIfNeeded(now: Date) async -> Bool {
        guard await loadState().needsDrain else { return false }
        do {
            try scheduler.submit(
                identifier: Self.identifier,
                earliestBeginDate: now.addingTimeInterval(earliestDelay)
            )
        } catch {
            Self.logger.error("Could not schedule the outbox drain: \(error.localizedDescription, privacy: .public)")
        }
        return true
    }

    /// One background task (PLAT-1):
    ///
    ///   set expiration handler ──> submit next request ──> drain ──> complete
    ///          │ (any time)                                              ▲
    ///          └──────────── cancel the work, complete(false) ──────────┘ once
    ///
    /// The next request goes in before any work, so an expiry or a crash
    /// mid-drain still leaves the outbox scheduled.
    private func handle(_ task: any BackgroundRefreshTaskHandle) {
        let run = BackgroundRun(task: task)
        task.setExpirationHandler { run.expire() }
        run.start { [self] in
            guard await submitIfNeeded(now: .now) else { return true }
            guard let engine = await makeEngine() else {
                // Locked keychain, or no setup yet: the request submitted
                // above is the retry.
                Self.logger.notice("Outbox drain deferred: the app cannot drain now.")
                return false
            }
            await engine.drain()
            return !Task.isCancelled
        }
    }
}

/// One background task's lifetime: its work, its expiry, and a completion
/// that reaches the system exactly once, whichever of the two ends first.
private final class BackgroundRun: Sendable {
    private struct State {
        var isCompleted = false
        var work: Task<Void, Never>?
    }

    private let task: any BackgroundRefreshTaskHandle
    private let state = Mutex(State())

    init(task: any BackgroundRefreshTaskHandle) {
        self.task = task
    }

    /// Runs `operation` and completes with its result. When the expiry came
    /// first, the work is cancelled at once (it still submits its request).
    func start(_ operation: @escaping @Sendable () async -> Bool) {
        let work = Task { complete(success: await operation()) }
        let expired = state.withLock { state in
            state.work = work
            return state.isCompleted
        }
        if expired { work.cancel() }
    }

    func expire() {
        state.withLock { $0.work }?.cancel()
        complete(success: false)
    }

    private func complete(success: Bool) {
        let isFirst = state.withLock { state in
            defer { state.isCompleted = true }
            return !state.isCompleted
        }
        if isFirst { task.complete(success: success) }
    }
}
