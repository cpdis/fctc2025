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
                        .appending(path: "fctc-uitest-\(UITestSupport.storeName).store")
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
                RootTabView(runtime: runtime, pendingRoutes: pendingRoutes)
            } else {
                NavigationStack {
                    SettingsView(runtime: runtime, configurationRequired: true)
                }
            }
        }
        .tint(runtime.accent.color)
        .onOpenURL(perform: receiveSetupCode)
        .alert(
            pendingSetup?.review.title ?? "",
            isPresented: binding(to: $pendingSetup),
            presenting: pendingSetup
        ) { pending in
            Button(
                pending.review.confirmTitle,
                role: pending.review.isDestructive ? .destructive : nil
            ) { connect(pending.config) }
            Button("Cancel", role: .cancel) {}
        } message: { pending in
            Text(pending.review.message)
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

    /// A scanned setup code is never applied on arrival. Any web page or chat link
    /// can open a custom scheme, and every Apps Script endpoint has the same host,
    /// so the person confirms the deployment and device name first. The prompt also
    /// says when the code replaces a working sheet and how many submissions that
    /// strands. It doubles as the "it worked" feedback the Safari detour never gave.
    private func receiveSetupCode(_ url: URL) {
        guard SetupCodeParser.isSetupLink(url.absoluteString) else { return }
        do {
            let config = try SetupCodeParser().parse(url.absoluteString)
            let current = runtime.config
            // Fails closed: an unreadable outbox shows an error, never a blind prompt.
            let waiting = try PendingSubmission.outstandingCount(
                endpointIdentity: current.endpoint?.absoluteString,
                in: runtime.modelContainer.mainContext
            )
            // The parser guarantees an HTTPS endpoint with a host, so this holds.
            guard let review = SetupCodeReview(
                incoming: config,
                current: current,
                waitingSubmissions: waiting
            ) else { throw SetupCodeError.invalidEndpoint }
            pendingSetup = PendingSetupCode(config: config, review: review)
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

/// A setup code that arrived by URL and is waiting for confirmation, with the
/// review captured on arrival so the prompt text cannot shift under the person.
private struct PendingSetupCode {
    let config: AppConfig
    let review: SetupCodeReview
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
