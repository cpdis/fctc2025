//
//  ActionErrorAlert.swift
//  FCTCAttendance
//
//  A failed toolbar action (Confirm, Apply, Save, Add) must be seen. As the
//  last list row its message sat below the fold, so it is an alert instead,
//  with an error haptic.
//

import SwiftUI

extension View {
    /// Shows `message` as an alert while it is non-nil, and clears it on OK.
    func actionErrorAlert(_ title: String, message: Binding<String?>) -> some View {
        alert(
            title,
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { if !$0 { message.wrappedValue = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message.wrappedValue ?? "")
        }
        .sensoryFeedback(.error, trigger: message.wrappedValue) { _, new in new != nil }
    }
}
