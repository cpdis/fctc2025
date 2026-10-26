//
//  SharedScreenshotOffer.swift
//  FCTCAttendance
//
//  The offer for screenshots shared into the app, used by the tab shell and
//  the checklist. Each button has one meaning: Import opens them, Delete
//  Screenshots removes them, and Not Now keeps them for the next offer.
//

import SwiftUI

struct SharedScreenshotOffer: ViewModifier {
    let count: Int
    @Binding var isPresented: Bool
    let message: String
    let onImport: () -> Void
    /// Empties the shared inbox. A failure is shown, never swallowed.
    let delete: () throws -> Void

    @State private var deleteError: String?

    func body(content: Content) -> some View {
        content
            .alert(
                "Import \(count) shared screenshot\(count == 1 ? "" : "s")?",
                isPresented: $isPresented
            ) {
                Button("Import", action: onImport)
                Button("Delete Screenshots", role: .destructive) {
                    do { try delete() } catch {
                        deleteError = "The screenshots could not be deleted. Try again."
                    }
                }
                Button("Not Now", role: .cancel) {}
            } message: {
                Text(message)
            }
            .actionErrorAlert("Could not delete screenshots", message: $deleteError)
    }
}
