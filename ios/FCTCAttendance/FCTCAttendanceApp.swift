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

    @State private var pendingSetup: PendingSetupCode?
    @State private var setupError: String?

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
        .onOpenURL(perform: receiveSetupCode)
        .alert(
            "Connect this phone?",
            isPresented: binding(to: $pendingSetup),
            presenting: pendingSetup
        ) { pending in
            Button("Connect") { connect(pending.config) }
            Button("Cancel", role: .cancel) {}
        } message: { pending in
            Text("This setup code points at \(pending.host). Connect only if you recognise it.")
        }
        .alert(
            "Setup code not valid",
            isPresented: binding(to: $setupError),
            presenting: setupError
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }

    /// A scanned setup code is never applied on arrival. Any web page can open a
    /// custom scheme, so the person confirms the endpoint host first. The prompt
    /// doubles as the "it worked" feedback the Safari detour never gave.
    private func receiveSetupCode(_ url: URL) {
        guard SetupCodeParser.isSetupLink(url.absoluteString) else { return }
        do {
            let config = try SetupCodeParser().parse(url.absoluteString)
            pendingSetup = PendingSetupCode(config: config)
        } catch {
            setupError = error.localizedDescription
        }
    }

    private func connect(_ config: AppConfig) {
        do {
            try runtime.configPersistence.save(config)
            runtime.apply(config)
        } catch {
            setupError = "The shared secret could not be saved to Keychain. Try again."
        }
    }

    /// SwiftUI's `presenting:` alerts need a Bool binding alongside the value.
    private func binding<Value>(to state: Binding<Value?>) -> Binding<Bool> {
        Binding(get: { state.wrappedValue != nil }, set: { if !$0 { state.wrappedValue = nil } })
    }
}

/// A setup code that arrived by URL and is waiting for confirmation.
private struct PendingSetupCode {
    let config: AppConfig

    /// The endpoint host, which is what the person is being asked to vouch for.
    var host: String { config.endpoint?.host ?? "an unknown address" }
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
