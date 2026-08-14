//
//  SyncEngine.swift
//  FCTCAttendanceKit
//
//  STUB (U1) — the real outbox drain, backoff and conflict plumbing land in U3.
//
//  Shape of the thing: confirming a draft NEVER blocks the UI on the network
//  (Apps Script cold starts run 1–3 s). The draft becomes a `PendingSubmission`, the
//  engine drains the queue with exponential backoff, and conflicts surface as events
//  the UI can present as a diff instead of clobbering the sheet (R8, R9).
//

import Foundation

/// Backoff schedule for outbox retries. Values are the delay before attempt N.
public struct RetryPolicy: Hashable, Sendable {
    public var initialDelay: TimeInterval
    public var multiplier: Double
    public var maxDelay: TimeInterval
    public var maxAttempts: Int

    public init(
        initialDelay: TimeInterval = 2,
        multiplier: Double = 2,
        maxDelay: TimeInterval = 300,
        maxAttempts: Int = 8
    ) {
        self.initialDelay = initialDelay
        self.multiplier = multiplier
        self.maxDelay = maxDelay
        self.maxAttempts = maxAttempts
    }

    public static let `default` = RetryPolicy()

    /// Delay before `attempt` (1-based). Deterministic and pure so U3 can test it
    /// without waiting on a clock.
    public func delay(forAttempt attempt: Int) -> TimeInterval {
        guard attempt > 1 else { return 0 }
        let raw = initialDelay * pow(multiplier, Double(attempt - 2))
        return min(raw, maxDelay)
    }
}

/// Everything the UI needs to hear from the engine.
public enum SyncEvent: Hashable, Sendable {
    case queued(id: UUID)
    case written(id: UUID)
    case conflict(id: UUID, reason: String, state: SheetState)
    case failed(id: UUID, message: String)
    case rosterRefreshed(SheetState)
}

/// Drains the outbox and keeps the local cache honest. Implemented in U3.
public protocol SyncEngine: Sendable {

    /// Refresh roster + runs from the sheet (one round-trip bootstrap).
    func refresh() async throws -> SheetState

    /// Confirm a draft: persist it to the outbox and kick a drain. Returns the
    /// outbox row's id so the UI can follow it.
    func enqueue(_ submission: AttendanceSubmission) async throws -> UUID

    /// Attempt to send everything outstanding. Safe to call repeatedly — submissions
    /// carry absolute values and are idempotent.
    func drain() async

    /// Engine → UI events.
    var events: AsyncStream<SyncEvent> { get }
}

/// Placeholder so views can be built before U3. Refuses everything, emits nothing.
public struct UnimplementedSyncEngine: SyncEngine {

    public init() {}

    public func refresh() async throws -> SheetState {
        throw SheetAPIError.notImplemented
    }

    public func enqueue(_ submission: AttendanceSubmission) async throws -> UUID {
        throw SheetAPIError.notImplemented
    }

    public func drain() async {}

    public var events: AsyncStream<SyncEvent> {
        AsyncStream { (continuation: AsyncStream<SyncEvent>.Continuation) in
            continuation.finish()
        }
    }
}
