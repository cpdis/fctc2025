import FCTCAttendanceKit
import SwiftUI

struct GuestRecoveryView: View {
    let runtime: AppRuntime
    @State private var model: GuestRecoveryViewModel
    init(runtime: AppRuntime) {
        self.runtime = runtime
        _model = State(initialValue: GuestRecoveryViewModel(engine: runtime.engine))
    }
    var body: some View {
        List {
            Section {
                Text("Local names are evidence to review. Choose the shared person and the original season and run.")
                Text("An import names an existing unnamed guest. It never adds a person to the headcount.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach([GuestRecoveryStatus.pending, .dismissed, .imported], id: \.self) { status in
                let items = model.candidates.filter { $0.status == status }
                if !items.isEmpty {
                    Section(status == .pending ? "Needs review" : status == .dismissed ? "Dismissed" : "Imported") {
                        ForEach(items) { candidate in
                            NavigationLink {
                                GuestRecoveryCandidateView(runtime: runtime, candidate: candidate)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(candidate.displayName)
                                    Text("\(candidate.expectedDate) · \(candidate.expectedRun)").font(.caption).foregroundStyle(.secondary)
                                    Text(evidenceLabel(candidate.evidenceStatus)).font(.caption).foregroundStyle(.secondary)
                                }
                            }.accessibilityIdentifier("recovery-candidate-\(candidate.displayName)-\(status.rawValue)")
                        }
                    }
                }
            }
            if model.candidates.isEmpty {
                ContentUnavailableView("No local names to recover", systemImage: "checkmark.circle", description: Text("Shared guests already use saved history."))
            }
            if let error = model.errorMessage { Text(error).foregroundStyle(.red).font(.footnote) }
        }
        .navigationTitle("Recover guest history").navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }.refreshable { await model.load() }
    }
}

private struct GuestRecoveryCandidateView: View {
    let runtime: AppRuntime
    let candidate: GuestRecoverySnapshot
    @State private var model: GuestRecoveryViewModel
    @State private var guestId = ""
    @State private var seasonId = -1
    @State private var runId = ""
    @State private var verified = false
    @State private var isCreating = false
    @State private var creationPending = false
    @State private var creationError: String?

    init(runtime: AppRuntime, candidate: GuestRecoverySnapshot) {
        self.runtime = runtime; self.candidate = candidate
        _model = State(initialValue: GuestRecoveryViewModel(engine: runtime.engine))
    }
    private var current: GuestRecoverySnapshot { model.candidates.first { $0.id == candidate.id } ?? candidate }
    var body: some View {
        List {
            Section("Local evidence") {
                LabeledContent("Name", value: candidate.displayName)
                Text("\(candidate.expectedDate) · \(candidate.expectedRun)")
                Text(evidenceLabel(candidate.evidenceStatus)).font(.footnote).foregroundStyle(.secondary)
                Text("The saved date has no verified year. Choose its season below.").font(.footnote).foregroundStyle(.secondary)
            }
            if current.status == .imported {
                Section { Label("Imported and confirmed", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            } else {
                Section("Assign saved attendance") {
                    Picker("Shared guest", selection: $guestId) {
                        Text("Choose a person").tag("")
                        ForEach(model.guests.filter(\.isActive)) { guest in
                            Text("\(guest.displayName) · \(guest.confirmedRuns ?? 0) runs").tag(guest.guestId)
                        }
                    }.accessibilityIdentifier("recovery-person")
                    Button("Create shared guest ‘\(candidate.displayName)’") {
                        isCreating = true; creationError = nil
                        Task {
                            defer { isCreating = false }
                            do {
                                let guest = try await runtime.engine.createGuest(name: candidate.displayName, confirmDistinct: false)
                                creationPending = true
                                await runtime.engine.drain()
                                await model.load()
                                if model.guests.contains(where: { $0.guestId == guest.id.uuidString.lowercased() && $0.isActive }) {
                                    guestId = guest.id.uuidString.lowercased()
                                }
                            } catch { creationError = UserFacingError.sync(error) }
                        }
                    }.disabled(isCreating || creationPending)
                    if creationPending && guestId.isEmpty {
                        Text("Guest creation is pending. Review its saved status in Outbox.").font(.footnote).foregroundStyle(.secondary)
                    }
                    NavigationLink("Review pending guest identities") { OutboxView(runtime: runtime) }
                    Picker("Season", selection: $seasonId) {
                        Text("Choose a season").tag(-1)
                        ForEach(model.seasons, id: \.seasonSheetId) { Text(String($0.seasonYear)).tag($0.seasonSheetId) }
                    }.accessibilityIdentifier("recovery-season")
                    if let state = model.selectedSeasonState {
                        Picker("Run", selection: $runId) {
                            Text("Choose the original run").tag("")
                            ForEach(state.runs, id: \.rowIndex) { run in
                                Text("\(run.date) · \(run.run) · \(run.unnamedGuests ?? 0) unnamed").tag(run.runId ?? "")
                            }
                        }.accessibilityIdentifier("recovery-run")
                    }
                    Toggle("I verified this person attended this run", isOn: $verified)
                        .accessibilityIdentifier("recovery-verified")
                }.disabled(isCreating || model.isWorking || model.preview != nil || model.operationId != nil)
                if let preview = model.preview {
                    Section("Import review") {
                        ForEach(preview.changes, id: \.runId) { change in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(change.expectedDate) · \(change.expectedRun)")
                                Text(change.alreadyAssigned ? "Already recorded. No extra credit." : "Unnamed guests: \(change.unnamedBefore) → \(change.unnamedAfter)")
                                    .font(.footnote).foregroundStyle(.secondary)
                                Text("Headcount stays the same").font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        Button(model.operationId == nil ? "Confirm import" : "Check saved import") {
                            Task { await model.importReviewed(candidateId: candidate.id) }
                        }.accessibilityIdentifier("recovery-confirm-import")
                    }
                } else {
                    Section {
                        Button("Preview import") { Task { await model.review(candidate: current, guestId: guestId, runId: runId, attendanceVerified: verified) } }
                            .disabled(guestId.isEmpty || runId.isEmpty || !verified || model.isWorking)
                            .accessibilityIdentifier("recovery-preview")
                    }
                }
                Section {
                    Button(current.status == .dismissed ? "Reopen for review" : "Dismiss reminder") {
                        Task { await model.setStatus(current.status == .dismissed ? .pending : .dismissed, for: current) }
                    }.disabled(model.operationId != nil).accessibilityIdentifier("recovery-dismiss")
                } footer: { Text("Dismissal keeps this evidence. You can return after correcting the spreadsheet.") }
            }
            if let message = model.statusMessage { Text(message).foregroundStyle(.secondary) }
            if let error = model.errorMessage { Text(error).foregroundStyle(.red).font(.footnote) }
            if let creationError { Text(creationError).foregroundStyle(.red).font(.footnote) }
            if model.isWorking { ProgressView() }
        }
        .navigationTitle(candidate.displayName).navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .onChange(of: seasonId) { _, id in runId = ""; verified = false; Task { await model.selectSeason(id) } }
        .onChange(of: guestId) { _, _ in verified = false }
        .onChange(of: runId) { _, _ in verified = false }
    }
}

private func evidenceLabel(_ status: String) -> String {
    switch status {
    case "committed": "Local submission was saved; verify its original run."
    case "discarded": "Local submission was discarded; attendance is unconfirmed."
    case "superseded": "Local submission was replaced; attendance is unconfirmed."
    case "legacy_ambiguous": "Older history does not prove this run was saved."
    default: "Local attendance is unconfirmed."
    }
}
