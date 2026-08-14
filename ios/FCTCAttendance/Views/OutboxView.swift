//
//  OutboxView.swift
//  FCTCAttendance
//

import FCTCAttendanceKit
import SwiftData
import SwiftUI

struct OutboxView: View {
    let runtime: AppRuntime

    @Query(
        filter: #Predicate<PendingSubmission> { $0.stateRaw != "done" },
        sort: \PendingSubmission.createdAt
    ) private var cachedSubmissions: [PendingSubmission]
    @State private var viewModel: OutboxViewModel
    @State private var selectedConflict: PendingSubmissionSnapshot?

    init(runtime: AppRuntime) {
        self.runtime = runtime
        _viewModel = State(initialValue: OutboxViewModel(engine: runtime.engine))
    }

    var body: some View {
        let outstanding = viewModel.outstanding(
            from: cachedSubmissions.map(PendingSubmissionSnapshot.init)
        )

        List {
            if outstanding.isEmpty {
                ContentUnavailableView(
                    "Outbox Clear",
                    systemImage: "checkmark.circle",
                    description: Text("Confirmed attendance will wait here when the sheet is offline.")
                )
                .listRowBackground(Color.clear)
                .accessibilityIdentifier("outbox-empty")
            } else {
                Section("Waiting") {
                    ForEach(outstanding) { submission in
                        if submission.status == .conflict {
                            Button {
                                selectedConflict = submission
                            } label: {
                                OutboxRow(submission: submission)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Opens conflict resolution.")
                            .accessibilityIdentifier("outbox-conflict-\(submission.id)")
                        } else {
                            OutboxRow(submission: submission)
                                .accessibilityIdentifier("outbox-row-\(submission.id)")
                        }
                    }
                }
            }

            if let message = viewModel.errorMessage {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Outbox")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await viewModel.retry() }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .disabled(!viewModel.canRetry(outstanding))
                .accessibilityIdentifier("outbox-retry")
            }
        }
        .sheet(item: $selectedConflict) { submission in
            ConflictResolutionView(submission: submission, viewModel: viewModel)
        }
        .onChange(of: runtime.generation) { _, _ in
            viewModel.replaceEngine(runtime.engine)
        }
    }

}

private struct OutboxRow: View {
    let submission: PendingSubmissionSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 26)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(submission.expectedRun)
                    .font(.headline)
                Text(submission.expectedDate)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(submission.status == .conflict ? .red : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if submission.status == .conflict {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 3)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(submission.expectedRun), \(submission.expectedDate), \(detail)")
    }

    private var icon: String {
        switch submission.status {
        case .queued: "clock.badge.exclamationmark"
        case .inFlight: "arrow.trianglehead.2.clockwise"
        case .conflict: "exclamationmark.triangle.fill"
        case .done: "checkmark.circle.fill"
        }
    }

    private var tint: Color {
        switch submission.status {
        case .queued, .inFlight: .orange
        case .conflict: .red
        case .done: .green
        }
    }

    private var detail: String {
        switch submission.status {
        case .queued: submission.lastError ?? "Waiting to sync"
        case .inFlight: "Sending"
        case .conflict: submission.conflictMessage ?? "Sheet changes need review"
        case .done: "Synced"
        }
    }
}

private struct ConflictResolutionView: View {
    let submission: PendingSubmissionSnapshot
    let viewModel: OutboxViewModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Local checks", value: submission.attendees.count.formatted())
                    LabeledContent("Sheet checks", value: serverAttendees.count.formatted())
                    LabeledContent("Local additions", value: diff.attendance.added.formatted())
                    LabeledContent("Sheet-only checks", value: diff.attendance.removed.formatted())
                } header: {
                    Text("Attendance difference")
                } footer: {
                    Text(submission.conflictMessage ?? "The sheet changed after this attendance was prepared.")
                }

                Section("Guest count") {
                    LabeledContent("Local +1's", value: localGuestValue)
                    LabeledContent("Sheet +1's", value: diff.serverPlusOnes.formatted())
                    LabeledContent("Result", value: diff.plusOnesChanged ? "Changed" : "Same")
                }

                Section("Actual distance") {
                    LabeledContent("Local kms", value: localDistanceValue)
                    LabeledContent("Sheet kms", value: serverDistanceValue)
                    LabeledContent("Result", value: diff.actualKmChanged ? "Changed" : "Same")
                }

                Section("Local attendance") {
                    if submission.attendees.isEmpty {
                        Text("No checked members")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(submission.attendees, id: \.self) { Text($0) }
                    }
                }

                Section("Sheet attendance") {
                    if serverAttendees.isEmpty {
                        Text("No checked members")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(serverAttendees, id: \.self) { Text($0) }
                    }
                }

                if let message = viewModel.errorMessage {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("conflict-error")
                    }
                }

                Section {
                    Button("Merge with Sheet") { resolve(.merge) }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("conflict-merge")

                    Button("Overwrite Sheet") { resolve(.overwrite) }
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("conflict-overwrite")

                    Button("Discard Local Submission", role: .destructive) { resolve(.discard) }
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("conflict-discard")
                } footer: {
                    Text("Merge keeps all sheet checks. Overwrite uses the local checklist exactly.")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Resolve Conflict")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .disabled(viewModel.isResolving)
        }
    }

    private var serverAttendees: [String] {
        guard let state = submission.conflictState else { return [] }
        let run = state.runs.first {
            $0.date == submission.expectedDate && $0.run == submission.expectedRun
        } ?? state.runs.first { $0.rowIndex == submission.rowIndex }
        return run?.attendees ?? []
    }

    private var diff: ConflictDiff {
        viewModel.conflictDiff(for: submission)
    }

    private var localGuestValue: String {
        diff.localPlusOnes?.formatted() ?? "No change"
    }

    private var localDistanceValue: String {
        diff.localActualKm.map(formatDistance) ?? "No change"
    }

    private var serverDistanceValue: String {
        diff.serverActualKm.map(formatDistance) ?? "Blank"
    }

    private func formatDistance(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    private func resolve(_ action: ConflictResolutionAction) {
        Task {
            do {
                _ = try await viewModel.resolve(id: submission.id, action: action)
                dismiss()
            } catch {
                // The view model retains the message so this sheet can show a retry.
            }
        }
    }
}
