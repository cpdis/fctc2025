//
//  BackgroundOutboxDrainTests.swift
//  FCTCAttendanceKitTests
//
//  The background refresh policy, the outstanding-work reader and the
//  locked-keychain path, with fake schedulers and tasks.
//

import Foundation
import Security
import SwiftData
import Synchronization
import Testing

@testable import FCTCAttendanceKit

@Suite("Background outbox drain", .timeLimit(.minutes(1)))
struct BackgroundOutboxDrainTests {
    @Test("Scheduler registers and submits only for configured outstanding work")
    func schedulerPolicy() async {
        let scheduler = FakeBackgroundScheduler()
        let engine = FakeOutboxDrainer()
        let state = LockedBackgroundState(
            BackgroundOutboxState(isConfigured: false, outstandingCount: 1)
        )
        let coordinator = BackgroundOutboxDrainCoordinator(
            scheduler: scheduler,
            earliestDelay: 60,
            makeEngine: { engine },
            loadState: { state.value }
        )

        #expect(coordinator.register())
        await coordinator.scheduleIfNeeded(now: Date(timeIntervalSince1970: 100))
        #expect(scheduler.submissions.isEmpty)

        state.value = BackgroundOutboxState(isConfigured: true, outstandingCount: 1)
        await coordinator.scheduleIfNeeded(now: Date(timeIntervalSince1970: 100))
        #expect(scheduler.submissions == [
            FakeBackgroundScheduler.Submission(
                identifier: BackgroundOutboxDrainCoordinator.identifier,
                earliest: Date(timeIntervalSince1970: 160)
            ),
        ])
    }

    @Test("Registered handler drains the lent client and completes")
    func handlerDrains() async {
        let scheduler = FakeBackgroundScheduler()
        let engine = FakeOutboxDrainer()
        let coordinator = BackgroundOutboxDrainCoordinator(
            scheduler: scheduler,
            makeEngine: { engine },
            loadState: { BackgroundOutboxState(isConfigured: true, outstandingCount: 1) }
        )
        _ = coordinator.register()
        let task = FakeBackgroundTask()

        scheduler.launch(task)
        while task.completions.isEmpty { await Task.yield() }

        #expect(await engine.drainCount == 1)
        #expect(task.completions == [true])
    }

    /// PLAT-1: the next request is submitted before the work, so an expiry
    /// mid-drain still leaves one. Before the fix the request was submitted
    /// only after a drain that was not cancelled, so this saw none.
    @Test("An expired task cancels the drain, completes once, and leaves a request")
    func expirationCancels() async {
        let scheduler = FakeBackgroundScheduler()
        let engine = CancellableOutboxDrainer()
        let coordinator = BackgroundOutboxDrainCoordinator(
            scheduler: scheduler,
            makeEngine: { engine },
            loadState: { BackgroundOutboxState(isConfigured: true, outstandingCount: 1) }
        )
        _ = coordinator.register()
        let task = FakeBackgroundTask()

        scheduler.launch(task)
        while !(await engine.started) { await Task.yield() }
        task.expire()
        while !(await engine.finished) { await Task.yield() }

        #expect(await engine.wasCancelled)
        // The work ends after the expiry; its result must not reach the
        // system a second time.
        #expect(task.completions == [false])
        #expect(scheduler.submissions.count == 1)
    }

    @Test("Handler completes without a client when no work remains")
    func handlerSkipsEmptyOutbox() async {
        let scheduler = FakeBackgroundScheduler()
        let engine = FakeOutboxDrainer()
        let coordinator = BackgroundOutboxDrainCoordinator(
            scheduler: scheduler,
            makeEngine: { engine },
            loadState: { BackgroundOutboxState(isConfigured: true, outstandingCount: 0) }
        )
        _ = coordinator.register()
        let task = FakeBackgroundTask()

        scheduler.launch(task)
        while task.completions.isEmpty { await Task.yield() }

        #expect(await engine.drainCount == 0)
        #expect(task.completions == [true])
        #expect(scheduler.submissions.isEmpty)
    }

    /// PLAT-6: work is waiting but no client can drain it (a locked keychain).
    /// The task reports failure and leaves a request, so a later task retries.
    /// Before the fix it completed true with nothing scheduled.
    @Test("No client for outstanding work completes false and retries later")
    func handlerRetriesWithoutClient() async {
        let scheduler = FakeBackgroundScheduler()
        let coordinator = BackgroundOutboxDrainCoordinator(
            scheduler: scheduler,
            makeEngine: { nil },
            loadState: { BackgroundOutboxState(isConfigured: true, outstandingCount: 1) }
        )
        _ = coordinator.register()
        let task = FakeBackgroundTask()

        scheduler.launch(task)
        while task.completions.isEmpty { await Task.yield() }

        #expect(task.completions == [false])
        #expect(scheduler.submissions.count == 1)
    }

    @Test("State reader excludes conflicts from drainable work")
    func stateReaderExcludesConflicts() async throws {
        let container = try makeBackgroundContainer()
        let context = ModelContext(container)
        context.insert(PendingSubmission(
            rowIndex: 1, expectedDate: "Fri, 1-May", expectedRun: "Tempo", attendees: ["Col"], status: .queued
        ))
        context.insert(PendingSubmission(
            rowIndex: 2, expectedDate: "Fri, 8-May", expectedRun: "Hills", attendees: ["Col"], status: .conflict
        ))
        try context.save()
        let reader = BackgroundOutboxStateReader(modelContainer: container)

        let state = try await reader.state(isConfigured: true)

        #expect(state.outstandingCount == 1)
        #expect(state.needsDrain)
    }

    /// CA-14: guest operations are outbox work too. Before the fix only
    /// submissions were counted, so this read zero and nothing was scheduled.
    @Test("State reader counts queued and checking guest operations only")
    func stateReaderCountsGuestOperations() async throws {
        let container = try makeBackgroundContainer()
        let context = ModelContext(container)
        for phase in [GuestOperationPhase.queued, .checking, .completed, .conflict, .rejected] {
            let operation = try SharedGuestOperation(action: "createGuest", fields: [
                "guestId": .string("guest-\(phase.rawValue)"), "displayName": .string("Toby"),
            ])
            let row = try PendingGuestOperation(
                operation: operation, endpointIdentity: "endpoint", spreadsheetId: "book"
            )
            row.phase = phase
            context.insert(row)
        }
        try context.save()
        let reader = BackgroundOutboxStateReader(modelContainer: container)

        let state = try await reader.state(isConfigured: true)

        #expect(state.outstandingCount == 2)
        #expect(state.needsDrain)
    }
}

@Suite("Locked keychain")
struct LockedKeychainTests {
    @Test("errSecInteractionNotAllowed maps to a retry-later error")
    func lockedStatus() {
        #expect(KeychainStoreError(status: errSecInteractionNotAllowed) == .interactionNotAllowed)
        #expect(KeychainStoreError(status: errSecAuthFailed) == .operationFailed(errSecAuthFailed))
    }

    /// PLAT-NEW-1: before the fix `load()` threw a bare keychain error and
    /// callers fell back to an empty config, dropping the endpoint.
    @Test("A locked secret keeps the endpoint and says retry later", arguments: [true, false])
    func lockedLoadKeepsEndpoint(locked: Bool) throws {
        let suite = "LockedKeychainTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let error: KeychainStoreError = locked ? .interactionNotAllowed : .invalidData
        try UserDefaultsAppConfigPersistence(defaults: defaults, secretStore: FakeSecretStore())
            .save(configuredAPI)
        let persistence = UserDefaultsAppConfigPersistence(
            defaults: defaults, secretStore: FakeSecretStore(readError: error)
        )

        do {
            _ = try persistence.load()
            Issue.record("A failed secret read must throw.")
        } catch let failure as AppConfigLoadError {
            #expect(failure.endpointOnly.endpoint == configuredAPI.endpoint)
            #expect(failure.endpointOnly.deviceName == configuredAPI.deviceName)
            #expect(!failure.endpointOnly.isConfigured)
            #expect(failure.isRetryLater == locked)
        }
    }
}

private func makeBackgroundContainer() throws -> ModelContainer {
    try ModelContainer(
        for: AttendanceSchema.schema,
        configurations: ModelConfiguration(
            "BackgroundOutboxStateTests",
            schema: AttendanceSchema.schema,
            isStoredInMemoryOnly: true
        )
    )
}

/// Reads fail with `readError` when it is set; writes always succeed.
private struct FakeSecretStore: SecretStoring {
    var readError: KeychainStoreError?

    func readSecret() throws -> String? {
        if let readError { throw readError }
        return configuredAPI.secret
    }

    func writeSecret(_ value: String) throws {}
}

private final class FakeBackgroundScheduler: BackgroundRefreshScheduling {
    struct Submission: Equatable {
        let identifier: String
        let earliest: Date?
    }

    private let handler = Mutex<(@Sendable (any BackgroundRefreshTaskHandle) -> Void)?>(nil)
    private let recorded = Mutex<[Submission]>([])

    var submissions: [Submission] { recorded.withLock { $0 } }

    func register(
        identifier: String,
        handler: @escaping @Sendable (any BackgroundRefreshTaskHandle) -> Void
    ) -> Bool {
        self.handler.withLock { $0 = handler }
        return true
    }

    func submit(identifier: String, earliestBeginDate: Date?) throws {
        recorded.withLock { $0.append(Submission(identifier: identifier, earliest: earliestBeginDate)) }
    }

    func launch(_ task: any BackgroundRefreshTaskHandle) {
        handler.withLock { $0 }?(task)
    }
}

/// Records every completion, so a test can prove the system hears one.
private final class FakeBackgroundTask: BackgroundRefreshTaskHandle {
    private let expiration = Mutex<(@Sendable () -> Void)?>(nil)
    private let results = Mutex<[Bool]>([])

    var completions: [Bool] { results.withLock { $0 } }

    func setExpirationHandler(_ handler: @escaping @Sendable () -> Void) {
        expiration.withLock { $0 = handler }
    }

    func complete(success: Bool) {
        results.withLock { $0.append(success) }
    }

    func expire() {
        expiration.withLock { $0 }?()
    }
}

private actor FakeOutboxDrainer: OutboxDraining {
    private(set) var drainCount = 0
    func drain() async { drainCount += 1 }
}

private actor CancellableOutboxDrainer: OutboxDraining {
    private(set) var started = false
    private(set) var finished = false
    private(set) var wasCancelled = false

    func drain() async {
        started = true
        do {
            try await Task.sleep(nanoseconds: 60_000_000_000)
        } catch {
            wasCancelled = Task.isCancelled
        }
        finished = true
    }
}

private final class LockedBackgroundState: Sendable {
    private let stored: Mutex<BackgroundOutboxState>

    init(_ value: BackgroundOutboxState) {
        stored = Mutex(value)
    }

    var value: BackgroundOutboxState {
        get { stored.withLock { $0 } }
        set { stored.withLock { $0 = newValue } }
    }
}
