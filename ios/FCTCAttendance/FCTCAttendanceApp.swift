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

@main
struct FCTCAttendanceApp: App {

    /// The app owns one container for the reconstructible cache and durable outbox.
    private let modelContainer: ModelContainer
    @State private var runtime: AppRuntime
    @Environment(\.scenePhase) private var scenePhase

    init() {
        do {
            let isUITesting = UITestSupport.isEnabled
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
        } catch {
            // Fail loudly until the app has a user-visible cache recovery path.
            fatalError("Unable to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            AppRootView(runtime: runtime)
        }
        .modelContainer(modelContainer)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await runtime.engine.drain() }
        }
    }
}

private struct AppRootView: View {
    let runtime: AppRuntime

    var body: some View {
        if runtime.config.isConfigured {
            HomeView(runtime: runtime)
        } else {
            NavigationStack {
                SettingsView(runtime: runtime, configurationRequired: true)
            }
        }
    }
}
