//
//  AttendanceFeatureTests.swift
//  FCTCAttendanceKitTests
//
//  Review-round-two rules that stay independent from SwiftUI.
//

import Foundation
import SwiftData
import Testing

@testable import FCTCAttendanceKit

@Suite("Round two attendance helpers")
struct RoundTwoHelperTests {
    private let now = Date(timeIntervalSince1970: 1_786_665_600) // 2026-08-14 UTC

    @Test("Catch-up selects the nearest older unrecorded run")
    func catchUpSelection() throws {
        let current = run(row: 4, dayOffset: -1)
        let runs = [
            run(row: 1, dayOffset: -4),
            run(row: 2, dayOffset: -3, attendees: ["Col"]),
            run(row: 3, dayOffset: -2),
            current,
            run(row: 5, dayOffset: 1),
        ]

        let next = CatchUpPlanner.nextOlderUnrecorded(
            after: current,
            among: runs,
            now: now,
            calendar: utcCalendar
        )

        #expect(next?.rowIndex == 3)
        #expect(
            CatchUpPlanner.nextOlderUnrecorded(
                after: run(row: 6, dayOffset: 0),
                among: runs,
                now: now,
                calendar: utcCalendar
            ) == nil
        )
        #expect(
            CatchUpPlanner.unrecordedPastRuns(
                among: runs,
                now: now,
                calendar: utcCalendar
            ).map(\.rowIndex) == [4, 3, 1]
        )
    }

    @Test("Member stats count attendance, last date, and the current streak")
    func memberStats() {
        let runs = [
            run(row: 1, dayOffset: -4, attendees: ["Col"]),
            run(row: 2, dayOffset: -3, attendees: ["Aaron"]),
            run(row: 3, dayOffset: -2, attendees: ["Col"]),
            run(row: 4, dayOffset: -1, attendees: ["Col", "Aaron"]),
            run(row: 5, dayOffset: 1),
        ]

        let stats = MemberStats.calculate(
            member: "Col",
            runs: runs,
            now: now
        )

        #expect(stats.attendanceCount == 3)
        #expect(stats.lastAttendedAt == runs[3].scheduledAt)
        #expect(stats.currentStreak == 2)
        #expect(
            MemberStats.calculateAll(
                members: ["Col", "Aaron"],
                runs: runs,
                now: now
            )["Col"] == stats
        )
    }

    @Test("Guest frequency counts at most once per submission")
    func frequentGuests() {
        let counts = GuestPromotionCounter.counts(
            in: [
                ["Priya", "PRIYA"],
                [" Priya "],
                ["Toby", "Priya"],
                ["Toby"],
            ]
        )

        #expect(counts[GuestPromotionCounter.canonical("Priya")] == 3)
        #expect(GuestPromotionCounter.isFrequent("priya", counts: counts))
        #expect(!GuestPromotionCounter.isFrequent("Toby", counts: counts))
    }

    @Test("Avatar initials and palette indexes are stable")
    func avatarIdentity() {
        #expect(MemberAvatar.initials(for: " Alex Kravchenko ") == "AK")
        #expect(MemberAvatar.initials(for: "Col") == "C")
        #expect(MemberAvatar.paletteIndex(for: "Álex Kr") == MemberAvatar.paletteIndex(for: "alex kr"))
        #expect(MemberAvatar.paletteIndex(for: "Alex Kr") == 0)
        #expect((0..<8).contains(MemberAvatar.paletteIndex(for: "Someone Else")))
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func run(
        row: Int,
        dayOffset: Int,
        attendees: [String] = [],
        plusOnes: Int = 0
    ) -> RunSnapshot {
        RunSnapshot(
            rowIndex: row,
            date: "Run \(row)",
            scheduledAt: utcCalendar.date(byAdding: .day, value: dayOffset, to: now),
            meet: "Meet \(row)",
            run: "Run \(row)",
            approxKm: 8,
            attendees: attendees,
            plusOnes: plusOnes,
            cachedRevision: "rev-1"
        )
    }
}

@Suite("Run reminders")
struct RunReminderTests {
    @Test("Reconcile cancels old reminders and schedules only future blank runs")
    func reminderReconcile() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 14,
            hour: 12
        )))
        let center = FakeRunNotificationCenter(
            pending: ["fctc.run-reminder.7", "some-other-notification"]
        )
        let preferences = FakeReminderPreferences(enabled: true)
        let reminders = RunReminderService(
            center: center,
            preferences: preferences,
            constants: RunReminderConstants(),
            calendar: calendar
        )
        let state = SheetState(
            runs: [
                RunRecord(
                    rowIndex: 8,
                    date: "Sat, 15-Aug",
                    meet: "Lake Monger",
                    run: "Tempo",
                    attendees: []
                ),
                RunRecord(
                    rowIndex: 9,
                    date: "Sun, 16-Aug",
                    meet: "City Beach",
                    run: "Long Run",
                    attendees: ["Col"]
                ),
                RunRecord(
                    rowIndex: 6,
                    date: "Thu, 13-Aug",
                    meet: "Old Meet",
                    run: "Old Run"
                ),
            ],
            seasonYear: 2026,
            sheetRevision: "rev-2"
        )

        await reminders.reconcile(state: state, now: now)

        #expect(await center.removedIdentifiers == ["fctc.run-reminder.7"])
        let request = try #require(await center.addedRequests.first)
        #expect(await center.addedRequests.count == 1)
        #expect(request.identifier == "fctc.run-reminder.8")
        #expect(request.body == "Record attendance for Lake Monger Tempo?")
        #expect(request.userInfo["rowIndex"] == "8")
        #expect(calendar.component(.hour, from: request.fireDate) == 7)
        #expect(calendar.component(.minute, from: request.fireDate) == 30)
    }

    @Test("A denied first enable leaves reminders off")
    func reminderDenial() async {
        let center = FakeRunNotificationCenter(authorizationGranted: false)
        let preferences = FakeReminderPreferences(enabled: false)
        let reminders = RunReminderService(center: center, preferences: preferences)

        let result = await reminders.setEnabled(true)

        #expect(result == .denied)
        #expect(!preferences.isEnabled)
        #expect(await center.authorizationRequests == 1)
    }

    @Test("A same-day run schedules when its reminder time is still future")
    func sameDayReminder() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 14,
            hour: 7
        )))
        let center = FakeRunNotificationCenter()
        let reminders = RunReminderService(
            center: center,
            preferences: FakeReminderPreferences(enabled: true),
            calendar: calendar
        )

        let result = await reminders.reconcile(
            state: SheetState(
                runs: [RunRecord(
                    rowIndex: 8,
                    date: "Fri, 14-Aug",
                    meet: "Lake Monger",
                    run: "Tempo"
                )],
                seasonYear: 2026,
                sheetRevision: "rev-2"
            ),
            now: now
        )

        #expect(result == .scheduled(1))
        #expect(await center.addedRequests.count == 1)
    }

    @Test("Disabling reminders cancels only owned requests")
    func reminderDisable() async {
        let center = FakeRunNotificationCenter(
            pending: ["fctc.run-reminder.4", "another-feature"]
        )
        let preferences = FakeReminderPreferences(enabled: true)
        let reminders = RunReminderService(center: center, preferences: preferences)

        let result = await reminders.setEnabled(false)

        #expect(result == .disabled)
        #expect(!preferences.isEnabled)
        #expect(await center.authorizationRequests == 0)
        #expect(await center.removedIdentifiers == ["fctc.run-reminder.4"])
    }

    @Test("An authorization error leaves reminders off and clears owned requests")
    func reminderAuthorizationFailure() async {
        let center = FakeRunNotificationCenter(
            pending: ["fctc.run-reminder.9", "another-feature"],
            authorizationFails: true
        )
        let preferences = FakeReminderPreferences(enabled: false)
        let reminders = RunReminderService(center: center, preferences: preferences)

        let result = await reminders.setEnabled(true)

        #expect(result == .failed)
        #expect(!preferences.isEnabled)
        #expect(await center.authorizationRequests == 1)
        #expect(await center.removedIdentifiers == ["fctc.run-reminder.9"])
    }

    @Test("A scheduling failure is retained for the caller")
    func reminderSchedulingFailure() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 14,
            hour: 7
        )))
        let center = FakeRunNotificationCenter(addFails: true)
        let reminders = RunReminderService(
            center: center,
            preferences: FakeReminderPreferences(enabled: true),
            calendar: calendar
        )
        let state = SheetState(
            runs: [RunRecord(
                rowIndex: 8,
                date: "Sat, 15-Aug",
                meet: "Lake Monger",
                run: "Tempo"
            )],
            seasonYear: 2026,
            sheetRevision: "rev-2"
        )

        let result = await reminders.reconcile(state: state, now: now)

        #expect(result == .failed)
        #expect(await reminders.lastReconcileResult == .failed)
    }

    @Test("Disabling during reconcile removes an in-flight reminder")
    func disableDuringReconcile() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 14,
            hour: 7
        )))
        let center = SuspendingRunNotificationCenter()
        let preferences = FakeReminderPreferences(enabled: true)
        let reminders = RunReminderService(
            center: center,
            preferences: preferences,
            calendar: calendar
        )
        let state = SheetState(
            runs: [RunRecord(
                rowIndex: 8,
                date: "Sat, 15-Aug",
                meet: "Lake Monger",
                run: "Tempo"
            )],
            seasonYear: 2026,
            sheetRevision: "rev-2"
        )

        let reconcile = Task { await reminders.reconcile(state: state, now: now) }
        await center.waitUntilAddStarts()
        #expect(await reminders.setEnabled(false) == .disabled)
        await center.resumeAdd()

        #expect(await reconcile.value == .disabled)
        #expect(!preferences.isEnabled)
        #expect(await center.pendingRequestIdentifiers().isEmpty)
    }
}

@Suite("Shared screenshot inbox")
struct SharedScreenshotInboxTests {
    @Test("Inbox lists PNGs in order and clears every received file")
    func listingAndClearing() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "fctc-share-inbox-\(UUID().uuidString)")
        let inbox = SharedScreenshotInbox(containerURL: root)
        let folder = try inbox.inboxURL()
        try Data([2]).write(to: folder.appending(path: "b.png"))
        try Data([1]).write(to: folder.appending(path: "a.PNG"))
        try Data([3]).write(to: folder.appending(path: "ignored.txt"))

        #expect(try inbox.list().map(\.lastPathComponent) == ["a.PNG", "b.png"])

        try inbox.remove([folder.appending(path: "a.PNG")])
        #expect(try inbox.list().map(\.lastPathComponent) == ["b.png"])
        #expect(try inbox.storedByteCount() == 2)

        try inbox.clear()
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }
}

@Suite("Background outbox drain")
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

    @Test("Registered handler drains with a fresh client and completes")
    func handlerDrains() async {
        let scheduler = FakeBackgroundScheduler()
        let engine = FakeOutboxDrainer()
        let state = LockedBackgroundState(
            BackgroundOutboxState(isConfigured: true, outstandingCount: 1)
        )
        let coordinator = BackgroundOutboxDrainCoordinator(
            scheduler: scheduler,
            makeEngine: { engine },
            loadState: { state.value }
        )
        _ = coordinator.register()
        let task = FakeBackgroundTask()

        scheduler.launch(task)
        while await engine.drainCount == 0 { await Task.yield() }
        while task.completed == nil { await Task.yield() }

        #expect(await engine.drainCount == 1)
        #expect(task.completed == true)
    }

    @Test("Expiration cancels the drain and completes unsuccessfully")
    func expirationCancels() async {
        let scheduler = FakeBackgroundScheduler()
        let engine = CancellableOutboxDrainer()
        let coordinator = BackgroundOutboxDrainCoordinator(
            scheduler: scheduler,
            makeEngine: { engine },
            loadState: {
                BackgroundOutboxState(isConfigured: true, outstandingCount: 1)
            }
        )
        _ = coordinator.register()
        let task = FakeBackgroundTask()

        scheduler.launch(task)
        while !(await engine.started) { await Task.yield() }
        task.expire()
        while task.completed == nil { await Task.yield() }

        #expect(await engine.wasCancelled)
        #expect(task.completed == false)
    }

    @Test("Handler completes without a client when no work remains")
    func handlerSkipsEmptyOutbox() async {
        let scheduler = FakeBackgroundScheduler()
        let engine = FakeOutboxDrainer()
        let coordinator = BackgroundOutboxDrainCoordinator(
            scheduler: scheduler,
            makeEngine: { engine },
            loadState: {
                BackgroundOutboxState(isConfigured: true, outstandingCount: 0)
            }
        )
        _ = coordinator.register()
        let task = FakeBackgroundTask()

        scheduler.launch(task)
        while task.completed == nil { await Task.yield() }

        #expect(await engine.drainCount == 0)
        #expect(task.completed == true)
    }

    @Test("Handler completes safely when configuration cannot make a client")
    func handlerHandlesMissingClient() async {
        let scheduler = FakeBackgroundScheduler()
        let coordinator = BackgroundOutboxDrainCoordinator(
            scheduler: scheduler,
            makeEngine: { nil },
            loadState: {
                BackgroundOutboxState(isConfigured: true, outstandingCount: 1)
            }
        )
        _ = coordinator.register()
        let task = FakeBackgroundTask()

        scheduler.launch(task)
        while task.completed == nil { await Task.yield() }

        #expect(task.completed == true)
        #expect(scheduler.submissions.isEmpty)
    }

    @Test("State reader excludes conflicts from drainable work")
    func stateReaderExcludesConflicts() async throws {
        let container = try ModelContainer(
            for: AttendanceSchema.schema,
            configurations: ModelConfiguration(
                "BackgroundOutboxStateTests",
                schema: AttendanceSchema.schema,
                isStoredInMemoryOnly: true
            )
        )
        let context = ModelContext(container)
        context.insert(PendingSubmission(
            rowIndex: 1,
            expectedDate: "Fri, 1-May",
            expectedRun: "Tempo",
            attendees: ["Col"],
            status: .queued
        ))
        context.insert(PendingSubmission(
            rowIndex: 2,
            expectedDate: "Fri, 8-May",
            expectedRun: "Hills",
            attendees: ["Col"],
            status: .conflict
        ))
        try context.save()
        let reader = BackgroundOutboxStateReader(modelContainer: container)

        let state = try await reader.state(isConfigured: true)

        #expect(state.outstandingCount == 1)
        #expect(state.needsDrain)
    }
}

private actor FakeRunNotificationCenter: RunNotificationCenterClient {
    private let authorizationGranted: Bool
    private let pending: [String]
    private let authorizationFails: Bool
    private let addFails: Bool
    private(set) var authorizationRequests = 0
    private(set) var removedIdentifiers: [String] = []
    private(set) var addedRequests: [RunReminderRequest] = []

    init(
        authorizationGranted: Bool = true,
        pending: [String] = [],
        authorizationFails: Bool = false,
        addFails: Bool = false
    ) {
        self.authorizationGranted = authorizationGranted
        self.pending = pending
        self.authorizationFails = authorizationFails
        self.addFails = addFails
    }

    func requestAuthorization() async throws -> Bool {
        authorizationRequests += 1
        if authorizationFails { throw FakeNotificationError.authorization }
        return authorizationGranted
    }

    func pendingRequestIdentifiers() async -> [String] { pending }

    func removePendingRequests(withIdentifiers identifiers: [String]) async {
        removedIdentifiers.append(contentsOf: identifiers)
    }

    func add(_ request: RunReminderRequest) async throws {
        if addFails { throw FakeNotificationError.add }
        addedRequests.append(request)
    }
}

private enum FakeNotificationError: Error {
    case authorization
    case add
}

private actor SuspendingRunNotificationCenter: RunNotificationCenterClient {
    private var pending: Set<String> = []
    private var didStartAdd = false
    private var addContinuation: CheckedContinuation<Void, Never>?

    func requestAuthorization() async throws -> Bool { true }

    func pendingRequestIdentifiers() async -> [String] { Array(pending) }

    func removePendingRequests(withIdentifiers identifiers: [String]) async {
        pending.subtract(identifiers)
    }

    func add(_ request: RunReminderRequest) async throws {
        didStartAdd = true
        await withCheckedContinuation { continuation in
            addContinuation = continuation
        }
        pending.insert(request.identifier)
    }

    func waitUntilAddStarts() async {
        while !didStartAdd { await Task.yield() }
    }

    func resumeAdd() {
        addContinuation?.resume()
        addContinuation = nil
    }
}

private final class FakeReminderPreferences: RunReminderPreferenceStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var enabled: Bool

    init(enabled: Bool) {
        self.enabled = enabled
    }

    var isEnabled: Bool { lock.withLock { enabled } }

    func setEnabled(_ enabled: Bool) {
        lock.withLock { self.enabled = enabled }
    }
}

private final class FakeBackgroundScheduler: BackgroundRefreshScheduling, @unchecked Sendable {
    struct Submission: Equatable {
        let identifier: String
        let earliest: Date?
    }

    private let lock = NSLock()
    private var handler: (@Sendable (any BackgroundRefreshTaskHandle) -> Void)?
    private var recordedSubmissions: [Submission] = []

    var submissions: [Submission] { lock.withLock { recordedSubmissions } }

    func register(
        identifier: String,
        handler: @escaping @Sendable (any BackgroundRefreshTaskHandle) -> Void
    ) -> Bool {
        lock.withLock { self.handler = handler }
        return true
    }

    func submit(identifier: String, earliestBeginDate: Date?) throws {
        lock.withLock {
            recordedSubmissions.append(Submission(identifier: identifier, earliest: earliestBeginDate))
        }
    }

    func launch(_ task: any BackgroundRefreshTaskHandle) {
        lock.withLock { handler }?(task)
    }
}

private final class FakeBackgroundTask: BackgroundRefreshTaskHandle, @unchecked Sendable {
    private let lock = NSLock()
    private var expiration: (@Sendable () -> Void)?
    private var result: Bool?

    var completed: Bool? { lock.withLock { result } }

    func setExpirationHandler(_ handler: @escaping @Sendable () -> Void) {
        lock.withLock { expiration = handler }
    }

    func complete(success: Bool) {
        lock.withLock { result = success }
    }

    func expire() {
        lock.withLock { expiration }?()
    }
}

private actor FakeOutboxDrainer: OutboxDraining {
    private(set) var drainCount = 0
    func drain() async { drainCount += 1 }
}

private actor CancellableOutboxDrainer: OutboxDraining {
    private(set) var started = false
    private(set) var wasCancelled = false

    func drain() async {
        started = true
        do {
            try await Task.sleep(nanoseconds: 60_000_000_000)
        } catch {
            wasCancelled = Task.isCancelled
        }
    }
}

private final class LockedBackgroundState: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: BackgroundOutboxState

    init(_ value: BackgroundOutboxState) {
        stored = value
    }

    var value: BackgroundOutboxState {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
