//
//  FCTCAttendanceApp.swift
//  FCTCAttendance
//
//  App entry point. Owns the SwiftData `ModelContainer` for the on-device cache +
//  outbox. The sheet stays canonical (R1): everything stored here is a cache and is
//  reconstructible from `getState`.
//

import FCTCAttendanceKit
import SwiftData
import SwiftUI
import UserNotifications

@main
struct FCTCAttendanceApp: App {

    /// The app owns one container for the reconstructible cache and durable outbox.
    private let modelContainer: ModelContainer
    private let notificationDelegate: AttendanceNotificationDelegate
    private let backgroundDrain: BackgroundOutboxDrainCoordinator
    @State private var runtime: AppRuntime
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let routes = PendingRouteStore.shared
        let notificationDelegate = AttendanceNotificationDelegate(routes: routes)
        self.notificationDelegate = notificationDelegate
        UNUserNotificationCenter.current().delegate = notificationDelegate
        do {
            let isUITesting = UITestSupport.isEnabled
            if isUITesting { UITestSupport.prepareLaunch() }
            // UI tests get a throwaway ON-DISK store, not an in-memory one:
            // SwiftData only propagates the engine actor's saves into the views'
            // @Query contexts through the persistent store, and in-memory stores
            // skip that machinery. A unique URL keeps every launch clean.
            let configuration = isUITesting
                ? ModelConfiguration(
                    "FCTCAttendance-UITest",
                    schema: AttendanceSchema.schema,
                    url: FileManager.default.temporaryDirectory
                        .appending(path: "fctc-uitest-\(UUID().uuidString).store")
                )
                : ModelConfiguration(
                    "FCTCAttendance",
                    schema: AttendanceSchema.schema,
                    isStoredInMemoryOnly: false
                )
            let container = try ModelContainer(
                for: AttendanceSchema.schema,
                configurations: configuration
            )
            modelContainer = container
            let runtime = isUITesting
                ? UITestSupport.makeRuntime(modelContainer: container)
                : AppRuntime(modelContainer: container)
            _runtime = State(initialValue: runtime)
            backgroundDrain = BackgroundOutboxDrainFactory.make(
                modelContainer: container,
                persistence: runtime.configPersistence
            )
            _ = backgroundDrain.register()
        } catch {
            // Fail loudly until the app has a user-visible cache recovery path.
            fatalError("Unable to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            AppRootView(runtime: runtime, pendingRoutes: .shared)
        }
        .modelContainer(modelContainer)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                NotificationCenter.default.post(name: .fctcAppDidActivate, object: nil)
                Task { await runtime.engine.drain() }
            case .background:
                Task { await backgroundDrain.scheduleIfNeeded() }
            case .inactive:
                break
            @unknown default:
                break
            }
        }
    }
}

private struct AppRootView: View {
    let runtime: AppRuntime
    let pendingRoutes: PendingRouteStore

    var body: some View {
        Group {
            if runtime.config.isConfigured {
                HomeView(runtime: runtime, pendingRoutes: pendingRoutes)
            } else {
                NavigationStack {
                    SettingsView(runtime: runtime, configurationRequired: true)
                }
            }
        }
        .tint(runtime.accent.color)
    }
}

extension AccentChoice {
    /// The SwiftUI color for each palette entry. Lives in the app target so the
    /// kit stays UI-free.
    var color: Color {
        switch self {
        case .green: .green
        case .blue: .blue
        case .orange: .orange
        case .pink: .pink
        case .purple: .purple
        case .red: .red
        case .teal: .teal
        }
    }
}
