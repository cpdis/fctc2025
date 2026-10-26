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

/// A route plus the moment it was stored. `consume()` drops stale routes.
private struct StoredRoute: Codable {
    let route: PendingAppRoute
    let createdAt: Date
}

final class PendingRouteStore: @unchecked Sendable {
    static let shared = PendingRouteStore()
    static let changed = Notification.Name("FCTCAttendance.pendingRouteChanged")

    private static let key = "pendingAppRoute"
    private let defaults: UserDefaults
    /// A route older than this was a tap the person has forgotten about.
    private static let maximumAge: TimeInterval = 10 * 60
    private let lock = NSLock()
    private let now: @Sendable () -> Date

    init(
        defaults: UserDefaults? = UserDefaults(suiteName: AppGroupConstants.identifier),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.defaults = defaults ?? .standard
        self.now = now
    }

    func set(_ route: PendingAppRoute) {
        guard let data = try? JSONCoding.encoder.encode(StoredRoute(route: route, createdAt: now()))
        else { return }
        lock.withLock { defaults.set(data, forKey: Self.key) }
        Task { @MainActor in
            NotificationCenter.default.post(name: Self.changed, object: nil)
        }
    }

    func consume() -> PendingAppRoute? {
        lock.withLock {
            guard let data = defaults.data(forKey: Self.key) else { return nil }
            defaults.removeObject(forKey: Self.key)
            let decoder = JSONCoding.decoder
            if let stored = try? decoder.decode(StoredRoute.self, from: data) {
                return now().timeIntervalSince(stored.createdAt) <= Self.maximumAge
                    ? stored.route : nil
            }
            // Older builds stored the bare route with no date. Treat it as fresh once.
            return try? decoder.decode(PendingAppRoute.self, from: data)
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
    static let supportedModes: IntentModes = .foreground(.immediate)

    func perform() async throws -> some IntentResult {
        PendingRouteStore.shared.set(.todayChecklist)
        return .result()
    }
}

struct DictateAttendanceIntent: AppIntent {
    static let title: LocalizedStringResource = "Dictate Attendance"
    static let description = IntentDescription("Open today's checklist and start dictation.")
    static let supportedModes: IntentModes = .foreground(.immediate)

    func perform() async throws -> some IntentResult {
        PendingRouteStore.shared.set(.todayDictation)
        return .result()
    }
}

struct AttendanceShortcuts: AppShortcutsProvider {
    static let shortcutTileColor: ShortcutTileColor = .lime

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RecordAttendanceIntent(),
            phrases: [
                "Record attendance in \(.applicationName)",
                "Take attendance in \(.applicationName)",
                "Start \(.applicationName) attendance",
            ],
            shortTitle: "Record Attendance",
            systemImageName: "checklist"
        )
        AppShortcut(
            intent: DictateAttendanceIntent(),
            phrases: [
                "Dictate attendance in \(.applicationName)",
                "Say who ran in \(.applicationName)",
            ],
            shortTitle: "Dictate Attendance",
            systemImageName: "waveform"
        )
    }
}
