//
//  AppRouting.swift
//  FCTCAttendance
//
//  Durable route handoff for notification taps and App Intents.
//

import AppIntents
import FCTCAttendanceKit
import Foundation
import UserNotifications

enum PendingAppRoute: Codable, Hashable, Sendable {
    case todayChecklist
    case todayDictation
    case checklist(rowIndex: Int, date: String, run: String)
}

final class PendingRouteStore: @unchecked Sendable {
    static let shared = PendingRouteStore()
    static let changed = Notification.Name("FCTCAttendance.pendingRouteChanged")

    private static let key = "pendingAppRoute"
    private let defaults: UserDefaults
    private let lock = NSLock()

    init(defaults: UserDefaults? = UserDefaults(suiteName: AppGroupConstants.identifier)) {
        self.defaults = defaults ?? .standard
    }

    func set(_ route: PendingAppRoute) {
        guard let data = try? JSONEncoder().encode(route) else { return }
        lock.withLock { defaults.set(data, forKey: Self.key) }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.changed, object: nil)
        }
    }

    func consume() -> PendingAppRoute? {
        lock.withLock {
            guard let data = defaults.data(forKey: Self.key),
                  let route = try? JSONDecoder().decode(PendingAppRoute.self, from: data)
            else { return nil }
            defaults.removeObject(forKey: Self.key)
            return route
        }
    }
}

extension Notification.Name {
    static let fctcAppDidActivate = Notification.Name("FCTCAttendance.appDidActivate")
}

final class AttendanceNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    private let routes: PendingRouteStore

    init(routes: PendingRouteStore) {
        self.routes = routes
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        guard info[RunReminderNotificationPayload.routeKey] as? String
                == RunReminderNotificationPayload.checklistRoute,
              let rowValue = info[RunReminderNotificationPayload.rowIndexKey] as? String,
              let rowIndex = Int(rowValue),
              let date = info[RunReminderNotificationPayload.dateKey] as? String,
              let run = info[RunReminderNotificationPayload.runKey] as? String
        else { return }
        routes.set(.checklist(rowIndex: rowIndex, date: date, run: run))
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

struct RecordAttendanceIntent: AppIntent {
    static let title: LocalizedStringResource = "Record Attendance"
    static let description = IntentDescription("Open today's attendance checklist.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        PendingRouteStore.shared.set(.todayChecklist)
        return .result()
    }
}

struct DictateAttendanceIntent: AppIntent {
    static let title: LocalizedStringResource = "Dictate Attendance"
    static let description = IntentDescription("Open today's checklist and start dictation.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        PendingRouteStore.shared.set(.todayDictation)
        return .result()
    }
}

struct AttendanceShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RecordAttendanceIntent(),
            phrases: ["Record attendance in \(.applicationName)"],
            shortTitle: "Record Attendance",
            systemImageName: "checklist"
        )
        AppShortcut(
            intent: DictateAttendanceIntent(),
            phrases: ["Dictate attendance in \(.applicationName)"],
            shortTitle: "Dictate Attendance",
            systemImageName: "waveform"
        )
    }
}
