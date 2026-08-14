//
//  SyncTypes.swift
//  FCTCAttendanceKit
//
//  Public timing, event, and dependency seams for the durable attendance outbox.
//

import Foundation

public struct RetryPolicy: Hashable, Sendable {
    public var initialDelay: TimeInterval
    public var multiplier: Double
    public var maxDelay: TimeInterval
    /// One immediate attempt plus four delayed attempts by default.
    public var maxAttempts: Int

    public init(
        initialDelay: TimeInterval = 2,
        multiplier: Double = 2,
        maxDelay: TimeInterval = 16,
        maxAttempts: Int = 5
    ) {
        self.initialDelay = initialDelay
        self.multiplier = multiplier
        self.maxDelay = maxDelay
        self.maxAttempts = maxAttempts
    }

    public static let `default` = RetryPolicy()

    /// Delay before a 1-based attempt. Attempt one is immediate.
    public func delay(forAttempt attempt: Int) -> TimeInterval {
        guard attempt > 1 else { return 0 }
        let raw = initialDelay * pow(multiplier, Double(attempt - 2))
        return min(raw, maxDelay)
    }
}

public protocol SyncClock: Sendable {
    func now() async -> Date
    func sleep(for seconds: TimeInterval) async throws
}

public struct SystemSyncClock: SyncClock {
    public init() {}

    public func now() async -> Date { Date() }

    public func sleep(for seconds: TimeInterval) async throws {
        let nanoseconds = UInt64(max(0, seconds) * 1_000_000_000)
        try await Task.sleep(nanoseconds: nanoseconds)
    }
}

public enum SyncEvent: Hashable, Sendable {
    case queued(id: UUID)
    case written(id: UUID)
    case conflict(id: UUID, reason: String, message: String, state: SheetState)
    case parked(id: UUID, message: String)
    case failed(id: UUID, message: String)
    case rosterRefreshed(SheetState)
}

/// AsyncStream is a work-sharing sequence when several iterators consume the same
/// instance. Screens need broadcast semantics, so each access to `events` receives
/// its own stream and continuation.
final class SyncEventBroadcaster: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<SyncEvent>.Continuation] = [:]

    func stream() -> AsyncStream<SyncEvent> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(100)) { continuation in
            lock.withLock { continuations[id] = continuation }
            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock { self?.continuations[id] = nil }
            }
        }
    }

    func yield(_ event: SyncEvent) {
        let listeners = lock.withLock { Array(continuations.values) }
        for listener in listeners { listener.yield(event) }
    }

    func finish() {
        let listeners = lock.withLock {
            let values = Array(continuations.values)
            continuations.removeAll()
            return values
        }
        for listener in listeners { listener.finish() }
    }
}

/// User choices for a durable conflict row. Merge and overwrite create a fresh
/// queued row against the server revision. Discard closes the old row as history.
public enum ConflictResolutionAction: String, Hashable, Sendable, CaseIterable {
    case merge
    case overwrite
    case discard
}

public protocol SyncEngineClient: Sendable {
    func refreshState() async throws -> SheetState
    func enqueue(_ submission: AttendanceSubmission) async throws -> UUID
    func enqueue(
        draft: AttendanceDraft,
        mode: SubmissionMode,
        deviceName: String?
    ) async throws -> UUID
    func drain() async
    func addMember(name: String) async throws -> AddMemberResult
    func addRun(_ request: AddRunRequest) async throws -> AddRunResult
    func resolveConflict(id: UUID, action: ConflictResolutionAction) async throws -> UUID?
    /// Every access returns a broadcast subscription for that consumer.
    var events: AsyncStream<SyncEvent> { get }
}

public struct UnimplementedSyncEngine: SyncEngineClient {
    public init() {}
    public func refreshState() async throws -> SheetState { throw SheetAPIError.notImplemented }
    public func refresh() async throws -> SheetState { throw SheetAPIError.notImplemented }
    public func enqueue(_ submission: AttendanceSubmission) async throws -> UUID {
        throw SheetAPIError.notImplemented
    }
    public func enqueue(
        draft: AttendanceDraft,
        mode: SubmissionMode,
        deviceName: String?
    ) async throws -> UUID { throw SheetAPIError.notImplemented }
    public func drain() async {}
    public func addMember(name: String) async throws -> AddMemberResult {
        throw SheetAPIError.notImplemented
    }
    public func addRun(_ request: AddRunRequest) async throws -> AddRunResult {
        throw SheetAPIError.notImplemented
    }
    public func resolveConflict(
        id: UUID,
        action: ConflictResolutionAction
    ) async throws -> UUID? { throw SheetAPIError.notImplemented }
    public var events: AsyncStream<SyncEvent> {
        AsyncStream { $0.finish() }
    }
}
