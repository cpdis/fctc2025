//
//  StoreRecoveryNotice.swift
//  FCTCAttendance
//
//  The one-time screen after `StoreRecovery` set the local store aside. It
//  says what happened, where the old data is, and that the sheet is safe.
//  Continue clears the flag, so it never shows again for that recovery.
//

import SwiftUI

extension View {
    /// Covers the app once after a store recovery.
    func storeRecoveryNotice() -> some View {
        modifier(StoreRecoveryNoticeModifier())
    }
}

private struct StoreRecoveryNoticeModifier: ViewModifier {
    /// The set-aside folder name; `nil` once the person has seen the notice.
    @AppStorage(StoreRecovery.noticeKey) private var folder: String?

    func body(content: Content) -> some View {
        content.fullScreenCover(isPresented: Binding(
            get: { folder != nil },
            set: { if !$0 { folder = nil } }
        )) {
            StoreRecoveryNotice(folder: folder ?? "") { folder = nil }
        }
    }
}

private struct StoreRecoveryNotice: View {
    let folder: String
    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "archivebox")
                    .font(.largeTitle)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text("Your local data was set aside")
                    .font(.title.bold())
                    .accessibilityAddTraits(.isHeader)
                Text("The app could not open the data saved on this phone. It moved that data to a folder named “\(folder)” and started fresh.")
                Text("Your Google Sheet is not affected. The app downloads it again when it syncs.")
                Text("Submissions that had not been sent are kept in that folder. Check the sheet and add any that are missing.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: onContinue) {
                Text("Continue").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(24)
            .accessibilityIdentifier("store-recovery-continue")
        }
    }
}
