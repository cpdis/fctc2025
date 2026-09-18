import FCTCAttendanceKit
import SwiftUI
import SwiftData

struct GuestDetailView: View {
    let runtime: AppRuntime
    let guest: SharedGuest
    let checklist: ChecklistViewModel?
    @Query private var guestOperations: [PendingGuestOperation]
    @Query private var submissions: [PendingSubmission]
    @Query private var cachedGuests: [CachedGuest]
    @Query private var sharedCaches: [SharedSheetCache]
    @State private var history: GuestHistory?
    @State private var error: String?
    @State private var message: String?
    @State private var isWorking = false
    @State private var historicalRun: RunSnapshot?
    @State private var showingRename = false

    // A confirmed name mutation updates the cache before history is fetched again.
    private var currentGuest: SharedGuest {
        let loaded = history?.guest ?? guest
        let book = checklist?.run.runIdentity?.spreadsheetId ?? sharedCaches
            .filter { $0.endpointIdentity == runtime.config.endpoint?.absoluteString }
            .max(by: { $0.refreshedAt < $1.refreshedAt })?.state?.spreadsheetId
        let cached = cachedGuests.first { $0.spreadsheetId == book && $0.guestId == guest.guestId }?.guest
        return cached.map { $0.revision >= loaded.revision ? $0 : loaded } ?? loaded
    }

    var body: some View {
        let displayGuest = currentGuest
        let pendingNameChange = nameChange
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(displayGuest.confirmedRuns ?? 0)")
                        .font(.largeTitle.bold()).monospacedDigit()
                    Text(displayGuest.isActive ? "confirmed runs" : "guest runs credited to member").foregroundStyle(.secondary)
                    if displayGuest.canSuggestPromotion {
                        Label("Ready to add as a member", systemImage: "person.crop.circle.badge.checkmark")
                            .font(.subheadline).foregroundStyle(.tint)
                    }
                    if let last = displayGuest.lastAttendance {
                        Text("Last attended \(last.date), \(last.seasonYear)").font(.footnote).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 8).accessibilityIdentifier("guest-confirmed-count")
                if let pending = pendingPromotion {
                    NavigationLink { GuestOperationStatusView(runtime: runtime, id: pending.id) } label: {
                        Label("Check saved promotion", systemImage: "clock.arrow.circlepath")
                    }.accessibilityIdentifier("guest-pending-promotion")
                } else if hasPendingAttendance {
                    NavigationLink { OutboxView(runtime: runtime) } label: {
                        Label("Run pending — open Outbox", systemImage: "clock")
                    }.accessibilityIdentifier("guest-pending-attendance")
                    Text("Promotion waits for this person's pending attendance to be confirmed.").font(.footnote).foregroundStyle(.secondary)
                } else if displayGuest.isActive {
                    NavigationLink {
                        GuestPromotionView(runtime: runtime, guest: displayGuest, checklist: checklist)
                    } label: { Label("Add as member", systemImage: "person.crop.circle.badge.plus") }
                    .accessibilityIdentifier("guest-promote")
                } else {
                    LabeledContent("Member", value: displayGuest.memberName ?? displayGuest.displayName)
                }
                if displayGuest.isActive {
                    Button(pendingNameChange == nil ? "Correct name" : "Review name change", systemImage: "pencil") {
                        showingRename = true
                    }.accessibilityIdentifier("guest-correct-name")
                }
            } footer: {
                Text("All saved runs stay with this person when they become a member. Promotion is your choice.")
            }
            ForEach(years, id: \.self) { year in
                Section(String(year)) {
                    ForEach((history?.attendance ?? []).filter { $0.seasonYear == year && $0.state != "removed" }) { entry in
                        Button { Task { await open(entry) } } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.date).foregroundStyle(.primary)
                                Text(entry.run).font(.subheadline).foregroundStyle(.secondary)
                                if entry.classification == "transferred" { Text("Credited to member").font(.caption).foregroundStyle(.secondary) }
                            }
                        }.accessibilityIdentifier("guest-run-\(entry.seasonYear)-\(entry.runId)")
                    }
                }
            }
            if history?.attendance.isEmpty == true {
                ContentUnavailableView("No saved runs", systemImage: "calendar", description: Text("Select this guest on a run and confirm attendance."))
            }
            if isWorking { ProgressView("Loading saved history…") }
            if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
            if let error { Text(error).font(.footnote).foregroundStyle(.red) }
        }
        .navigationTitle(displayGuest.displayName).navigationBarTitleDisplayMode(.inline)
        .task { await load() }.refreshable { await load() }
        .navigationDestination(item: $historicalRun) { run in ChecklistView(runtime: runtime, run: run) }
        .sheet(isPresented: $showingRename) {
            NavigationStack {
                GuestNameEditorView(runtime: runtime, guest: displayGuest, operationId: pendingNameChange?.id) { saved in
                    history?.guest = saved
                    message = "Name saved for every organiser."
                    Task { await checklist?.loadSharedGuests() }
                }
            }
        }
    }

    private var nameChange: PendingGuestOperation? {
        let rows = guestOperations.filter {
            $0.endpointIdentity == runtime.config.endpoint?.absoluteString &&
            $0.operation?.action == "renameGuest" && $0.operation?.request["guestId"]?.string == guest.guestId &&
            $0.phase != .completed && $0.phase != .superseded
        }
        // Unknown outcomes must be checked before offering another correction.
        return rows.first { $0.phase == .queued || $0.phase == .checking }
            ?? rows.max { $0.createdAt < $1.createdAt }
    }

    private var pendingPromotion: PendingGuestOperation? {
        guestOperations.first { $0.endpointIdentity == runtime.config.endpoint?.absoluteString
            && $0.operation?.action == "commitPromotion" && $0.operation?.request["guestId"]?.string == guest.guestId
            && ($0.phase == .queued || $0.phase == .checking) }
    }
    private var hasPendingAttendance: Bool {
        submissions.contains { $0.endpointIdentity == runtime.config.endpoint?.absoluteString && $0.status != .done
            && $0.namedGuestIds?.contains(guest.guestId) == true }
    }
    private var years: [Int] { Array(Set(history?.attendance.map(\.seasonYear) ?? [])).sorted(by: >) }
    private func load() async {
        isWorking = true; defer { isWorking = false }
        do { history = try await runtime.engine.guestHistory(id: guest.guestId); error = nil }
        catch { self.error = UserFacingError.sync(error) }
    }
    private func open(_ entry: GuestAttendanceEntry) async {
        isWorking = true; defer { isWorking = false }
        do {
            let state = try await runtime.engine.refreshState(seasonSheetId: entry.seasonSheetId)
            guard state.spreadsheetId == entry.spreadsheetId,
                  let run = state.runs.first(where: { $0.identity == entry.identity }) else {
                throw SheetAPIError.badPayload(message: "The original run could not be found. Refresh the guest history.")
            }
            historicalRun = RunSnapshot(record: run, state: state, endpointIdentity: runtime.config.endpoint?.absoluteString)
        } catch { self.error = UserFacingError.sync(error) }
    }

}

struct GuestPromotionView: View {
    let runtime: AppRuntime
    let checklist: ChecklistViewModel?
    @State private var model: GuestPromotionViewModel
    @State private var showingSaveReview = false

    init(runtime: AppRuntime, guest: SharedGuest, checklist: ChecklistViewModel?) {
        self.runtime = runtime; self.checklist = checklist
        _model = State(initialValue: GuestPromotionViewModel(guest: guest, engine: runtime.engine))
    }
    var body: some View {
        List {
            Section {
                Picker("Member", selection: $model.targetMode) {
                    Text("Create new member").tag(PromotionTargetMode.create)
                    Text("Link existing member").tag(PromotionTargetMode.link)
                }.disabled(model.isWorking || model.preview != nil || model.operationId != nil)
                if model.targetMode == .create {
                    TextField("Member name", text: $model.memberName).textInputAutocapitalization(.words)
                        .disabled(model.isWorking || model.preview != nil || model.operationId != nil)
                } else {
                    Picker("Existing member", selection: $model.memberName) {
                        Text("Select a member").tag("")
                        ForEach(checklist?.roster ?? [], id: \.self) { Text($0).tag($0) }
                    }.disabled(model.isWorking || model.preview != nil || model.operationId != nil)
                }
            } footer: { Text("Choose the person explicitly. Matching names do not prove they are the same person.") }
            if let preview = model.preview {
                Section("Historical credit") {
                    LabeledContent("Confirmed runs", value: preview.confirmedRuns.formatted())
                        .accessibilityIdentifier("promotion-confirmed-count")
                    ForEach(preview.seasons, id: \.seasonSheetId) { season in
                        LabeledContent(String(season.seasonYear), value: "\(season.runs) runs")
                    }
                }
                Section("Run changes") {
                    ForEach(preview.changes, id: \.runId) { change in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(change.date) · \(change.run)").font(.subheadline)
                            Text("Guests \(change.plusOnesBefore) → \(change.plusOnesAfter) · People \(change.totalBefore) → \(change.totalAfter)")
                                .font(.caption).foregroundStyle(.secondary)
                            Text("Distance \(change.actualKmBefore?.formatted() ?? "blank") → \(change.actualKmAfter?.formatted() ?? "blank") km")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if let message = model.runMessage {
                Section("This run") {
                    Label(message, systemImage: model.waitingForRun ? "clock" : "checkmark.circle")
                    if model.waitingForRun { NavigationLink("Review Outbox") { OutboxView(runtime: runtime) } }
                }
            }
            if let message = model.promotionMessage { Section("Promotion") { Text(message).accessibilityIdentifier("promotion-status") } }
            if let error = model.errorMessage { Text(error).foregroundStyle(.red).font(.footnote) }
            if !model.completed {
                Section {
                    if model.preview == nil && model.operationId == nil {
                        Button(prepareLabel) {
                            if checklist?.draftDiffersFromSheet == true { showingSaveReview = true }
                            else { Task { await model.prepare(checklist: checklist) } }
                        }.accessibilityIdentifier("promotion-preview")
                    } else {
                        Button(model.operationId == nil ? "Confirm promotion" : "Check saved promotion") {
                            Task {
                                await model.commit()
                                if model.completed, let checklist {
                                    if let state = try? await runtime.engine.refreshState(seasonSheetId: checklist.run.runIdentity?.seasonSheetId) {
                                        checklist.acceptSavedState(state)
                                    }
                                }
                            }
                        }.accessibilityIdentifier("promotion-confirm")
                    }
                }.disabled(model.isWorking || model.memberName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if model.isWorking { ProgressView("Checking saved runs…") }
        }
        .navigationTitle("Add as member").navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Save this run first", isPresented: $showingSaveReview, titleVisibility: .visible) {
            Button("Save run and review promotion") { Task { await model.prepare(checklist: checklist) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(checklist?.diffSummary(for: .overwrite).summary ?? "") member checks. \(checklist?.guestDiff(for: .overwrite).summary ?? ""). This saves the reviewed checklist before preparing the promotion.")
        }
        .onChange(of: model.targetMode) { _, mode in model.memberName = mode == .create ? model.guest.displayName : "" }
    }
    private var prepareLabel: String {
        if model.waitingForRun { return "Check saved run and continue" }
        return checklist?.draftDiffersFromSheet == true ? "Save run and promote" : "Preview promotion"
    }
}
