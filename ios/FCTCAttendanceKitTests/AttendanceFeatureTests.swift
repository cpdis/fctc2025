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

@Suite("Run reminders", .timeLimit(.minutes(1)))
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

    /// A loose date cell ("Sat 15-Aug", no comma) is a run on the Dashboard, so
    /// it gets its reminder like any other unrecorded run.
    @Test("A loose sheet date still gets its reminder")
    func reminderLooseDate() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 14, hour: 12)))
        let center = FakeRunNotificationCenter()
        let reminders = RunReminderService(
            center: center,
            preferences: FakeReminderPreferences(enabled: true),
            constants: RunReminderConstants(),
            calendar: calendar
        )
        let state = SheetState(
            runs: [RunRecord(rowIndex: 8, date: "Sat 15-Aug", meet: "Lake Monger", run: "Tempo", attendees: [])],
            seasonYear: 2026,
            sheetRevision: "rev-2"
        )

        await reminders.reconcile(state: state, now: now)

        let request = try #require(await center.addedRequests.first)
        #expect(calendar.dateComponents([.month, .day, .hour, .minute], from: request.fireDate)
            == DateComponents(month: 8, day: 15, hour: 7, minute: 30))
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
        defer { try? FileManager.default.removeItem(at: root) }
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
