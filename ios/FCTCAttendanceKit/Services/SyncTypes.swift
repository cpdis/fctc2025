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
    case authenticationRequired(id: UUID)
    case serviceFailed(message: String)
    case rosterRefreshed(SheetState)
    /// A drain pass started (`true`) or finished (`false`). Row status cannot
    /// carry this: a shared row keeps `.inFlight` after an unknown outcome, long
    /// after any request has stopped. Screens show a working state only from here.
    case syncActivity(isActive: Bool)
}

/// AsyncStream is a work-sharing sequence when several iterators consume the same
/// instance. Screens need broadcast semantics, so each access to `events` receives
/// its own stream and continuation.
final class SyncEventBroadcaster: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<SyncEvent>.Continuation] = [:]
    /// Whether a drain is running now. Unlike other events it is state, so a
    /// screen that subscribes mid-drain is told at once.
    private var isActive = false

    func stream() -> AsyncStream<SyncEvent> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(100)) { continuation in
            // Register and replay under one lock, so a concurrent change of
            // activity cannot slip between them and leave the replay stale.
            lock.withLock {
                continuations[id] = continuation
                if isActive { continuation.yield(.syncActivity(isActive: true)) }
            }
            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock { self?.continuations[id] = nil }
            }
        }
    }

    /// Records drain activity and tells every subscriber when it changes.
    /// Yielding inside the lock keeps activity events in order with the replay.
    func setActivity(_ active: Bool) {
        lock.withLock {
            guard isActive != active else { return }
            isActive = active
            for listener in continuations.values {
                listener.yield(.syncActivity(isActive: active))
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
    func refreshState(seasonSheetId: Int?) async throws -> SheetState
    /// Last season as a read-only snapshot; nil when the endpoint has none.
    func previousSeasonSnapshot() async throws -> SheetState?
    func sharedGuests() async throws -> [SharedGuest]
    func guestHistory(id: String) async throws -> GuestHistory
    func createGuest(name: String, confirmDistinct: Bool) async throws -> Guest
    func resolveGuestIdentity(provisionalId: String, existingGuestId: String?, confirmDistinct: Bool) async throws
    func renameGuest(_ guest: SharedGuest, name: String) async throws -> UUID
    func replaceGuestRename(id: UUID, guest: SharedGuest, name: String) async throws -> UUID
    func discardGuestRename(id: UUID) async throws
    func previewPromotion(guestId: String, memberName: String, targetMode: PromotionTargetMode) async throws -> PromotionPreview
    func commitPromotion(_ preview: PromotionPreview) async throws -> UUID
    func recoveryCandidates(includeDismissed: Bool) async throws -> [GuestRecoverySnapshot]
    func updateRecoveryCandidate(id: String, guestId: String?, run: GuestImportEntry?, status: GuestRecoveryStatus) async throws
    func previewGuestImport(guestId: String, entries: [GuestImportEntry]) async throws -> GuestImportPreview
    func importGuestHistory(_ preview: GuestImportPreview, candidateIds: [String]) async throws -> UUID
    func guestOperation(id: UUID) async throws -> GuestOperationSnapshot?
    func pendingSubmission(id: UUID) async throws -> PendingSubmissionSnapshot?
    func replacePromotedGuestSubmission(id: UUID, reviewedDraft: AttendanceDraft) async throws -> UUID

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
