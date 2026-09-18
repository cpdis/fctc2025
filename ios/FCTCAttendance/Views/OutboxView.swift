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
    @Query(sort: \PendingGuestOperation.createdAt) private var guestOperations: [PendingGuestOperation]
    @State private var viewModel: OutboxViewModel
    @State private var selectedConflict: PendingSubmissionSnapshot?
    @State private var showingSettings = false

    init(runtime: AppRuntime) {
        self.runtime = runtime
        _viewModel = State(initialValue: OutboxViewModel(engine: runtime.engine))
    }

    var body: some View {
        let outstanding = viewModel.outstanding(
            from: cachedSubmissions.map(PendingSubmissionSnapshot.init)
        )

        List {
            if let banner = viewModel.syncBanner {
                Section {
                    Label(
                        banner.message,
                        systemImage: banner.kind == .offline
                            ? "wifi.slash"
                            : banner.kind == .parked
                                ? "hourglass"
                                : "exclamationmark.triangle.fill"
                    )
                        .font(.footnote)
                        .foregroundStyle(banner.kind == .authentication ? .red : .orange)
                        .accessibilityIdentifier("outbox-sync-banner")

                    if banner.kind == .offline || banner.kind == .parked {
                        Button("Retry Now", systemImage: "arrow.clockwise") {
                            Task { await viewModel.retry() }
                        }
                        .accessibilityIdentifier("outbox-banner-retry")
                    } else if banner.kind == .authentication {
                        Button("Open Settings", systemImage: "gearshape") {
                            showingSettings = true
                        }
                        .accessibilityIdentifier("outbox-open-settings")
                    }
                }
            }

            if !pendingGuestOperations.isEmpty {
                Section("Guest changes") {
                    ForEach(pendingGuestOperations) { operation in
                        if operation.operation?.action == "renameGuest" {
                            NavigationLink {
                                GuestNameEditorView(runtime: runtime, operationId: operation.id)
                            } label: { guestOperationLabel(operation) }
                            .accessibilityIdentifier("outbox-rename-\(operation.id)")
                        } else if operation.conflict?.reason == "identity_ambiguous",
                           let provisionalId = operation.operation?.request["guestId"]?.string {
                            NavigationLink {
                                GuestIdentityReviewView(runtime: runtime, provisionalId: provisionalId,
                                    displayName: operation.operation?.request["displayName"]?.string ?? "Guest",
                                    candidateIds: operation.conflict?.guestIds ?? [])
                            } label: { guestOperationLabel(operation) }
                        } else {
                            NavigationLink { GuestOperationStatusView(runtime: runtime, id: operation.id) } label: { guestOperationLabel(operation) }
                        }
                    }
                    Button("Check saved guest changes") { Task { await runtime.engine.drain() } }
                        .accessibilityIdentifier("check-guest-operations")
                }
            }
            if outstanding.isEmpty && pendingGuestOperations.isEmpty {
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

            if let message = viewModel.errorMessage, viewModel.syncBanner == nil {
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
            if submission.conflictReason == "guest_promoted" {
                GuestConflictReviewView(runtime: runtime, submission: submission)
            } else {
                ConflictResolutionView(runtime: runtime, submission: submission, viewModel: viewModel)
            }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack { SettingsView(runtime: runtime) }
        }
        .onChange(of: runtime.generation) { _, _ in
            viewModel.replaceEngine(runtime.engine)
        }
    }

    private var pendingGuestOperations: [PendingGuestOperation] {
        guestOperations.filter { $0.endpointIdentity == runtime.config.endpoint?.absoluteString && $0.phase != .completed && $0.phase != .superseded }
    }
    private func guestOperationTitle(_ operation: PendingGuestOperation) -> String {
        switch operation.operation?.action {
        case "renameGuest": "Name change"
        case "commitPromotion": "Member promotion"
        case "importGuestHistory": "Guest history import"
        default: "Guest identity"
        }
    }
    private func guestOperationLabel(_ operation: PendingGuestOperation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(guestOperationTitle(operation))
                .font(.headline)
            if operation.operation?.action == "renameGuest" {
                Text(operation.operation?.request["displayName"]?.string ?? "Guest")
                Text(operation.phase == .conflict || operation.phase == .rejected ? "Review name" : "Name change pending")
                    .font(.footnote).foregroundStyle(.secondary)
                if let reason = operation.lastError {
                    Text(reason).font(.footnote).foregroundStyle(.secondary)
                        .accessibilityIdentifier("outbox-rename-reason-\(operation.id)")
                }
            } else {
                Text(operation.lastError ?? "Waiting to sync").font(.footnote).foregroundStyle(.secondary)
            }
            if operation.operation?.action != "renameGuest" && (operation.phase == .rejected || (operation.phase == .conflict && operation.conflict?.reason != "identity_ambiguous")) {
                Text("Open the guest history to review this change again.").font(.footnote).foregroundStyle(.secondary)
            }
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
        case .queued: submission.verificationPending ? "Checking saved changes" : submission.lastError ?? "Waiting to sync"
        case .inFlight: "Sending"
        case .conflict: submission.conflictMessage ?? "Sheet changes need review"
        case .done: "Synced"
        }
    }
}

private struct ConflictResolutionView: View {
    let runtime: AppRuntime
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

                Section("Guest names") {
                    LabeledContent("Local", value: submission.guestNames.isEmpty ? "None" : submission.guestNames.joined(separator: ", "))
                    LabeledContent("Sheet", value: serverGuestNames.isEmpty ? "None" : serverGuestNames.joined(separator: ", "))
                    LabeledContent("Local unnamed", value: submission.unnamedGuests?.formatted() ?? "Not recorded")
                    LabeledContent("Sheet unnamed", value: serverRun?.unnamedGuests?.formatted() ?? "Not recorded")
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
                    if submission.runIdentity != nil || submission.conflictReason != "identity_review_required" {
                    if !requiresGuestOverwrite {
                        Button("Merge with Sheet") { resolve(.merge) }
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity)
                            .accessibilityIdentifier("conflict-merge")
                    }

                    Button("Overwrite Sheet") { resolve(.overwrite) }
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("conflict-overwrite")

                    } else {
                        if !submission.guestNames.isEmpty {
                            NavigationLink("Recover local guest history") { GuestRecoveryView(runtime: runtime) }
                        }
                        Text("This older submission has no verified workbook or season. It remains saved here. Open the original run and compare these details before recording it again.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Button("Discard Local Submission", role: .destructive) { resolve(.discard) }
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("conflict-discard")
                } footer: {
                    Text(requiresGuestOverwrite
                         ? "This guest correction needs an overwrite. Review the local and sheet allocations above. Overwrite uses the local checklist exactly."
                         : "Merge keeps all sheet checks and guest allocations. Overwrite uses the local checklist exactly.")
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

    private var serverRun: RunRecord? {
        guard let state = submission.conflictState else { return nil }
        if let identity = submission.runIdentity { return state.runs.first { $0.identity == identity } }
        return state.runs.first { $0.date == submission.expectedDate && $0.run == submission.expectedRun }
    }
    private var serverAttendees: [String] { serverRun?.attendees ?? [] }
    private var requiresGuestOverwrite: Bool {
        guard submission.mode == .overwrite, submission.runIdentity != nil, let run = serverRun,
              let named = submission.namedGuestIds, let unnamed = submission.unnamedGuests else { return false }
        return !Set(run.namedGuestIds ?? []).isSubset(of: Set(named))
            || unnamed < (run.unnamedGuests ?? max(0, run.plusOnes - (run.namedGuestIds?.count ?? 0)))
    }
    private var serverGuestNames: [String] {
        (serverRun?.namedGuestIds ?? []).map { id in submission.conflictState?.guests?.first { $0.guestId == id }?.displayName ?? "Saved guest" }
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
