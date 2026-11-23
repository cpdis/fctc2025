//
//  RunCancellationViews.swift
//  FCTCAttendance
//
//  Review & Confirm's run cancelled pieces (docs/plans/2026-11-23-1050-feat-run-cancelled-plan.md, U4).
//  ChecklistView decides when they show; these views only draw them.
//

import FCTCAttendanceKit
import SwiftUI

/// Run cancelled, a destructive row below the roster (Colin's pick of three, 23 Nov 2026).
/// The confirmation is attached to the row: iOS 26 shows it as a popover there.
struct CancelRunFooter: View {
    let run: RunSnapshot
    @Binding var isConfirming: Bool
    let isWorking: Bool
    let confirm: () -> Void

    var body: some View {
        Section {
            Button(role: .destructive) {
                isConfirming = true
            } label: {
                HStack {
                    Label("Mark Run Cancelled", systemImage: "xmark.circle")
                    Spacer()
                    if isWorking { ProgressView() }
                }
            }
            .disabled(isWorking)
            .accessibilityIdentifier("cancel-run")
            .confirmationDialog("Cancel this run?", isPresented: $isConfirming, titleVisibility: .visible) {
                Button("Mark Cancelled", role: .destructive, action: confirm)
                    .accessibilityIdentifier("confirm-cancel-run")
                Button("Keep Run", role: .cancel) {}
                    .accessibilityIdentifier("keep-run")
            } message: {
                Text("\(run.date) \(run.runName) shows as cancelled for every organiser and on the dashboard. Restore Run undoes it.")
            }
        } footer: {
            Text("Nobody ran? Mark it cancelled so no one is asked to record it.")
        }
    }
}

/// A cancelled run's whole screen: what happened, and the way back.
struct CancelledRunSections: View {
    let run: RunSnapshot
    let isWorking: Bool
    let restore: () -> Void

    var body: some View {
        Section {
            VStack(spacing: 8) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Run Cancelled")
                    .font(.title2.bold())
                Text("\(run.date) · \(run.detailLabel)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text("Nobody is asked to record it, and it does not count as a club day.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("cancelled-run-status")
        }

        Section {
            Button(action: restore) {
                HStack {
                    Spacer()
                    if isWorking { ProgressView() } else { Text("Restore Run").fontWeight(.semibold) }
                    Spacer()
                }
            }
            .disabled(isWorking)
            .accessibilityLabel("Restore Run")
            .accessibilityIdentifier("restore-run")
        } footer: {
            Text("Restore it if the run went ahead after all. Then record attendance as usual.")
        }
    }
}
