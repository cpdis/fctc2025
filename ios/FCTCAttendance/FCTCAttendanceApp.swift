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

    /// Every persistent model in `FCTCAttendanceKit`. Kept in one place so U3 can add
    /// to `AttendanceSchema.models` without touching the app target.
    private let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try ModelContainer(
                for: AttendanceSchema.schema,
                configurations: ModelConfiguration(
                    "FCTCAttendance",
                    schema: AttendanceSchema.schema,
                    isStoredInMemoryOnly: false
                )
            )
        } catch {
            // A cache we cannot open is not worth crashing over long-term, but during
            // development a loud failure is the right signal (U8 replaces this with a
            // recover-by-wiping-the-cache path).
            fatalError("Unable to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
        }
        .modelContainer(modelContainer)
    }
}
