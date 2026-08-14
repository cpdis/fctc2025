//
//  RunReminderService.swift
//  FCTCAttendanceKit
//
//  Local run reminders with a protocol-fronted UNUserNotificationCenter seam.
//

import Foundation
import UserNotifications

public struct RunReminderConstants: Hashable, Sendable {
    public var assumedStartHour: Int
    public var assumedStartMinute: Int
    public var postRunOffsetMinutes: Int

    public init(
        assumedStartHour: Int = 6,
        assumedStartMinute: Int = 0,
        postRunOffsetMinutes: Int = 90
    ) {
        self.assumedStartHour = assumedStartHour
        self.assumedStartMinute = assumedStartMinute
        self.postRunOffsetMinutes = postRunOffsetMinutes
    }
}

public struct RunReminderRequest: Hashable, Sendable {
    public var identifier: String
    public var title: String
    public var body: String
    public var fireDate: Date
    public var userInfo: [String: String]

    public init(
        identifier: String,
        title: String,
        body: String,
        fireDate: Date,
        userInfo: [String: String]
    ) {
        self.identifier = identifier
        self.title = title
        self.body = body
        self.fireDate = fireDate
        self.userInfo = userInfo
    }
}

public enum RunReminderNotificationPayload {
    public static let routeKey = "route"
    public static let rowIndexKey = "rowIndex"
    public static let dateKey = "date"
    public static let runKey = "run"
    public static let checklistRoute = "checklist"
}

public protocol RunNotificationCenterClient: Sendable {
    func requestAuthorization() async throws -> Bool
    func pendingRequestIdentifiers() async -> [String]
    func removePendingRequests(withIdentifiers identifiers: [String]) async
    func add(_ request: RunReminderRequest) async throws
}

public protocol RunReminderPreferenceStoring: Sendable {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool)
}

public protocol RunReminderScheduling: Sendable {
    @discardableResult
    func reconcile(state: SheetState, now: Date) async -> RunReminderReconcileResult
}

public struct NoopRunReminderScheduler: RunReminderScheduling {
    public init() {}
    public func reconcile(
        state: SheetState,
        now: Date
    ) async -> RunReminderReconcileResult { .disabled }
}

public protocol RunReminderManaging: RunReminderScheduling {
    var isEnabled: Bool { get }
    var lastReconcileResult: RunReminderReconcileResult? { get async }
    func setEnabled(_ enabled: Bool) async -> RunReminderPermissionResult
}

public enum RunReminderPermissionResult: Hashable, Sendable {
    case enabled
    case disabled
    case denied
    case failed
}

public enum RunReminderReconcileResult: Hashable, Sendable {
    case disabled
    case scheduled(Int)
    case failed
}

public actor RunReminderService: RunReminderManaging {
    public static let identifierPrefix = "fctc.run-reminder."

    private let center: any RunNotificationCenterClient
    private let preferences: any RunReminderPreferenceStoring
    private let constants: RunReminderConstants
    private var calendar: Calendar
    private var operationGeneration = 0
    public private(set) var lastReconcileResult: RunReminderReconcileResult?

    public nonisolated var isEnabled: Bool { preferences.isEnabled }

    public init(
        center: any RunNotificationCenterClient = UserNotificationCenterClient(),
        preferences: any RunReminderPreferenceStoring = UserDefaultsRunReminderPreferences(),
        constants: RunReminderConstants = RunReminderConstants(),
        calendar: Calendar = .current
    ) {
        self.center = center
        self.preferences = preferences
        self.constants = constants
        self.calendar = calendar
    }

    public func setEnabled(_ enabled: Bool) async -> RunReminderPermissionResult {
        operationGeneration &+= 1
        let generation = operationGeneration
        guard enabled else {
            preferences.setEnabled(false)
            await cancelOwnedRequests()
            lastReconcileResult = .disabled
            return .disabled
        }
        do {
            guard try await center.requestAuthorization() else {
                preferences.setEnabled(false)
                await cancelOwnedRequests()
                lastReconcileResult = .disabled
                return .denied
            }
            guard generation == operationGeneration else { return .disabled }
            preferences.setEnabled(true)
            lastReconcileResult = nil
            return .enabled
        } catch {
            preferences.setEnabled(false)
            await cancelOwnedRequests()
            lastReconcileResult = .failed
            return .failed
        }
    }

    public func reconcile(
        state: SheetState,
        now: Date = .now
    ) async -> RunReminderReconcileResult {
        let generation = operationGeneration
        guard preferences.isEnabled else {
            lastReconcileResult = .disabled
            return .disabled
        }
        await cancelOwnedRequests()
        guard isActive(generation) else {
            lastReconcileResult = .disabled
            return .disabled
        }

        var scheduledCount = 0
        for run in state.runs where !run.hasRecordedAttendance {
            guard let runDate = parseDate(run.date, seasonYear: state.seasonYear),
                  let fireDate = fireDate(on: runDate),
                  fireDate > now
            else { continue }

            let request = RunReminderRequest(
                identifier: Self.identifierPrefix + String(run.rowIndex),
                title: "FCTC Attendance",
                body: "Record attendance for \(run.meet) \(run.run)?",
                fireDate: fireDate,
                userInfo: [
                    RunReminderNotificationPayload.routeKey:
                        RunReminderNotificationPayload.checklistRoute,
                    RunReminderNotificationPayload.rowIndexKey: String(run.rowIndex),
                    RunReminderNotificationPayload.dateKey: run.date,
                    RunReminderNotificationPayload.runKey: run.run,
                ]
            )
            do {
                try await center.add(request)
            } catch {
                await cancelOwnedRequests()
                lastReconcileResult = .failed
                return .failed
            }
            guard isActive(generation) else {
                await cancelOwnedRequests()
                lastReconcileResult = .disabled
                return .disabled
            }
            scheduledCount += 1
        }
        let result = RunReminderReconcileResult.scheduled(scheduledCount)
        lastReconcileResult = result
        return result
    }

    private func isActive(_ generation: Int) -> Bool {
        generation == operationGeneration && preferences.isEnabled
    }

    private func cancelOwnedRequests() async {
        let identifiers = await center.pendingRequestIdentifiers()
            .filter { $0.hasPrefix(Self.identifierPrefix) }
        guard !identifiers.isEmpty else { return }
        await center.removePendingRequests(withIdentifiers: identifiers)
    }

    private func parseDate(_ value: String, seasonYear: Int) -> Date? {
        guard seasonYear > 0 else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEE, d-MMM-yyyy"
        return formatter.date(from: "\(value)-\(seasonYear)")
    }

    private func fireDate(on date: Date) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = constants.assumedStartHour
        components.minute = constants.assumedStartMinute
        guard let start = calendar.date(from: components) else { return nil }
        return calendar.date(byAdding: .minute, value: constants.postRunOffsetMinutes, to: start)
    }
}

private extension RunRecord {
    var hasRecordedAttendance: Bool { !attendees.isEmpty || plusOnes > 0 }
}

public final class UserDefaultsRunReminderPreferences: RunReminderPreferenceStoring, @unchecked Sendable {
    private static let key = "runReminders.enabled"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var isEnabled: Bool { defaults.bool(forKey: Self.key) }

    public func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.key)
    }
}

public struct UserNotificationCenterClient: RunNotificationCenterClient, @unchecked Sendable {
    private let center: UNUserNotificationCenter

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    public func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    public func pendingRequestIdentifiers() async -> [String] {
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                continuation.resume(returning: requests.map(\.identifier))
            }
        }
    }

    public func removePendingRequests(withIdentifiers identifiers: [String]) async {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    public func add(_ request: RunReminderRequest) async throws {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.sound = .default
        content.userInfo = request.userInfo
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: request.fireDate
            ),
            repeats: false
        )
        let notification = UNNotificationRequest(
            identifier: request.identifier,
            content: content,
            trigger: trigger
        )
        try await center.add(notification)
    }
}
