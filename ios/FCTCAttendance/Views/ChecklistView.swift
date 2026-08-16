//
//  ChecklistView.swift
//  FCTCAttendance
//
//  Review & Confirm. Every capture modality lands in this Reminders-style list.
//

import FCTCAttendanceKit
import SwiftData
import SwiftUI
import UIKit

struct ChecklistView: View {
    let runtime: AppRuntime
    let presentation: ChecklistPresentation
    let onConfirmed: (@MainActor (RunSnapshot?) -> Void)?

    @Query(sort: \Member.name) private var cachedMembers: [Member]
    @Query(
        sort: \PendingSubmission.createdAt,
        order: .reverse
    ) private var cachedSubmissions: [PendingSubmission]
    @Query(sort: \ScheduledRun.rowIndex) private var cachedRuns: [ScheduledRun]
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: ChecklistViewModel
    @State private var searchText = ""
    @State private var showingRecordedChoice = false
    @State private var showingScreenshotImport = false
    @State private var showingVoiceEntry = false
    @State private var showingCatchUp = false
    @State private var nextCatchUpRun: RunSnapshot?
    @State private var showingSharedScreenshotOffer = false
    @State private var sharedScreenshotCount = 0
    @State private var sharedImportURLs: [URL] = []

    init(
        runtime: AppRuntime,
        run: RunSnapshot,
        draft: AttendanceDraft? = nil,
        presentation: ChecklistPresentation = .standard,
        onConfirmed: (@MainActor (RunSnapshot?) -> Void)? = nil
    ) {
        self.runtime = runtime
        self.presentation = presentation
        self.onConfirmed = onConfirmed
        _viewModel = State(
            initialValue: ChecklistViewModel(
                run: run,
                roster: [],
                draft: draft,
                engine: runtime.engine,
                deviceName: runtime.config.deviceName
            )
        )
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        let runSnapshots = cachedRuns.map(RunSnapshot.init)
        let statsByMember = MemberStats.calculateAll(
            members: viewModel.roster,
            runs: runSnapshots
        )

        List {
            // The smart modalities lead the screen (Colin's review, 2026-08-14):
            // hiding them in the collapsed toolbar buried the app's best features.
            Section {
                HStack(spacing: 12) {
                    Button {
                        showingScreenshotImport = true
                    } label: {
                        ModalityButtonLabel(
                            title: "Import Poll",
                            systemImage: "photo.badge.plus"
                        )
                    }
                    .disabled(viewModel.roster.isEmpty)
                    .accessibilityHint("Imports voter names as attendance suggestions.")
                    .accessibilityIdentifier("import-poll")

                    Button {
                        showingVoiceEntry = true
                    } label: {
                        ModalityButtonLabel(
                            title: "Dictate",
                            systemImage: "waveform"
                        )
                    }
                    .accessibilityHint("Dictate names, guests, and actual kilometres.")
                    .accessibilityIdentifier("dictate-attendance")
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section {
                HStack {
                    Label("Actual kms", systemImage: "figure.run")
                    Spacer(minLength: 16)
                    TextField("0", text: $viewModel.actualKmText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(minWidth: 64, idealWidth: 84, maxWidth: 110)
                        .accessibilityLabel("Actual kilometres")
                        .accessibilityIdentifier("actual-km")
                }

                NavigationLink {
                    GuestEditorView(viewModel: viewModel)
                } label: {
                    HStack {
                        Label("Guests", systemImage: "person.2")
                        Spacer(minLength: 16)
                        Text(viewModel.draft.plusOnes, format: .number)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .accessibilityLabel("Guests, \(viewModel.draft.plusOnes)")
                .accessibilityIdentifier("guest-editor")
            }

            Section("Attendance") {
                ForEach(filteredRoster, id: \.self) { name in
                    MemberCheckRow(
                        name: name,
                        provenance: viewModel.draft.checks[name],
                        isSuggested: viewModel.isSuggested(name),
                        stats: statsByMember[name]
                            ?? MemberStats(attendanceCount: 0, lastAttendedAt: nil, currentStreak: 0),
                        action: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            viewModel.toggleMember(name)
                        }
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if viewModel.draft.isChecked(name) {
                            Button("Uncheck", systemImage: "xmark.circle") {
                                viewModel.uncheckMember(name)
                            }
                            .tint(.orange)
                            .accessibilityLabel("Uncheck \(name)")
                        }
                    }
                }

                ForEach(viewModel.matchingGuests) { guest in
                    Button {
                        viewModel.quickAddName = guest.name
                        Task { try? await viewModel.commitQuickAdd() }
                    } label: {
                        HStack {
                            Label("Add \(guest.name) as member", systemImage: "person.crop.circle.badge.plus")
                                .foregroundStyle(.primary)
                            Spacer()
                            if viewModel.isFrequentGuest(guest.name) {
                                FrequentGuestBadge()
                            }
                        }
                    }
                    .disabled(viewModel.isAddingPerson)
                    .accessibilityIdentifier("promote-guest-\(guest.id)")
                }

                QuickAddPersonRow(viewModel: viewModel)
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
        .navigationTitle("Review & Confirm")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Find a person")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Confirm") {
                    if viewModel.requiresRecordedChoice {
                        showingRecordedChoice = true
                    } else {
                        submit(mode: .merge)
                    }
                }
                .fontWeight(.semibold)
                .disabled(!viewModel.canConfirm)
                .accessibilityHint(
                    viewModel.canConfirm
                        ? "Queues these attendance changes."
                        : "Change attendance before confirming."
                )
                .accessibilityIdentifier("confirm-attendance")
            }
        }
        .sheet(isPresented: $showingVoiceEntry) {
            NavigationStack {
                VoiceEntryView(checklistViewModel: viewModel)
            }
        }
        .confirmationDialog(
            "Attendance is already recorded",
            isPresented: $showingRecordedChoice,
            titleVisibility: .visible
        ) {
            Button("Merge — \(mergeSummary)") { submit(mode: .merge) }
                .accessibilityIdentifier("confirm-merge")
            Button("Overwrite — \(overwriteSummary)") { submit(mode: .overwrite) }
                .accessibilityIdentifier("confirm-overwrite")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Merge keeps sheet checks. Overwrite can remove them.")
        }
        .sheet(
            isPresented: $showingScreenshotImport,
            onDismiss: clearSharedImportState
        ) {
            ScreenshotImportView(
                roster: viewModel.roster,
                parser: UITestSupport.screenshotParser(),
                initialImages: UITestSupport.screenshotImages(),
                initialFileURLs: sharedImportURLs,
                skipCoach: UITestSupport.shouldSkipScreenshotCoach || !sharedImportURLs.isEmpty,
                onInitialFilesConsumed: clearSharedScreenshotInbox,
                onApply: { set, checks in
                    viewModel.applyProposals(checks: checks, from: set)
                    showingScreenshotImport = false
                },
                onAddPerson: addScreenshotPerson,
                onCancel: {
                    showingScreenshotImport = false
                }
            )
            .interactiveDismissDisabled(viewModel.isAddingPerson)
        }
        .task {
            updateCachedValues()
            switch presentation {
            case .dictation:
                showingVoiceEntry = true
            case .sharedScreenshots:
                loadSharedImagesAndPresent()
            case .standard:
                checkSharedScreenshotInbox()
            }
        }
        .onChange(of: cacheFingerprint) { _, _ in updateCachedValues() }
        .onReceive(NotificationCenter.default.publisher(for: .fctcAppDidActivate)) { _ in
            checkSharedScreenshotInbox()
        }
        .alert(
            "Import \(sharedScreenshotCount) shared screenshot\(sharedScreenshotCount == 1 ? "" : "s")?",
            isPresented: $showingSharedScreenshotOffer
        ) {
            Button("Import") { loadSharedImagesAndPresent() }
            Button("Dismiss", role: .cancel) {
                try? runtime.sharedScreenshotInbox.clear()
            }
        } message: {
            Text("Review these images through the existing poll import flow.")
        }
        .alert("Attendance recorded", isPresented: $showingCatchUp) {
            Button("Next unrecorded run") { finishConfirmation(with: nextCatchUpRun) }
                .accessibilityIdentifier("catchup-next")
            Button("Skip") { skipNextCatchUpRun() }
                .accessibilityIdentifier("catchup-skip")
            Button("Done", role: .cancel) { finishConfirmation(with: nil) }
                .accessibilityIdentifier("catchup-done")
        } message: {
            Text("An older run still needs attendance.")
        }
    }

    private var filteredRoster: [String] {
        guard !searchText.isEmpty else { return viewModel.roster }
        return viewModel.roster.filter {
            $0.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var cacheFingerprint: String {
        let roster = cachedMembers.map { "\($0.name):\($0.colIndex):\($0.isNew)" }
        let guests = cachedSubmissions.map { submission in
            "\(submission.id):\(submission.guestNames.joined(separator: ","))"
        }
        return (roster + guests).joined(separator: "|")
    }

    private var mergeSummary: String {
        let diff = viewModel.diffSummary(for: .merge)
        return "add \(diff.added), remove \(diff.removed)"
    }

    private var overwriteSummary: String {
        let diff = viewModel.diffSummary(for: .overwrite)
        return "add \(diff.added), remove \(diff.removed)"
    }

    private func updateCachedValues() {
        viewModel.updateRoster(cachedMembers.map(\.name))
        viewModel.updateGuestSubmissionHistory(cachedSubmissions.map(\.guestNames))
    }

    private func submit(mode: SubmissionMode) {
        Task {
            do {
                _ = try await viewModel.confirm(mode: mode)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                let snapshots = cachedRuns.map(RunSnapshot.init)
                if let next = CatchUpPlanner.nextOlderUnrecorded(
                    after: viewModel.run,
                    among: snapshots
                ) {
                    nextCatchUpRun = next
                    showingCatchUp = true
                } else {
                    finishConfirmation(with: nil)
                }
            } catch {}
        }
    }

    private func finishConfirmation(with nextRun: RunSnapshot?) {
        if let onConfirmed {
            onConfirmed(nextRun)
        } else {
            dismiss()
        }
    }

    private func skipNextCatchUpRun() {
        guard let skipped = nextCatchUpRun else {
            finishConfirmation(with: nil)
            return
        }
        let following = CatchUpPlanner.nextOlderUnrecorded(
            after: skipped,
            among: cachedRuns.map(RunSnapshot.init)
        )
        finishConfirmation(with: following)
    }

    private func checkSharedScreenshotInbox() {
        guard !showingScreenshotImport,
              !showingSharedScreenshotOffer,
              let count = try? runtime.sharedScreenshotInbox.list().count,
              count > 0
        else { return }
        sharedScreenshotCount = count
        showingSharedScreenshotOffer = true
    }

    private func loadSharedImagesAndPresent() {
        let urls = (try? runtime.sharedScreenshotInbox.list()) ?? []
        guard !urls.isEmpty else { return }
        sharedImportURLs = urls
        showingScreenshotImport = true
    }

    private func clearSharedScreenshotInbox() {
        try? runtime.sharedScreenshotInbox.clear()
    }

    private func clearSharedImportState() {
        clearSharedScreenshotInbox()
        sharedImportURLs = []
    }

    private func addScreenshotPerson(_ name: String) async throws {
        viewModel.quickAddName = name
        try await viewModel.commitQuickAdd()
        // Quick-add is normally a manual checklist action. This name came from an
        // explicit proposal choice, so the frozen apply seam supplies provenance.
        viewModel.uncheckMember(name)
    }
}

private struct MemberCheckRow: View {
    let name: String
    let provenance: CheckProvenance?
    let isSuggested: Bool
    let stats: MemberStats
    let action: () -> Void

    private var isChecked: Bool { provenance != nil }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                CircularCheck(isChecked: isChecked)

                MemberAvatarView(name: name)

                Text(name)
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                if let provenance, provenance != .manual {
                    ProvenanceBadge(kind: ProvenanceBadgeKind(provenance))
                } else if isSuggested {
                    ProvenanceBadge(kind: .suggested)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue(isChecked ? "Checked" : "Not checked")
        .accessibilityHint("Double-tap to \(isChecked ? "uncheck" : "check").")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("member-\(name)")
        .contextMenu {
            Button(action: {}) {
                Label("\(stats.attendanceCount) season attendances", systemImage: "calendar")
            }
            .disabled(true)
            Button(action: {}) {
                Label(lastAttendedLabel, systemImage: "clock")
            }
            .disabled(true)
            Button(action: {}) {
                Label("\(stats.currentStreak) run streak", systemImage: "flame")
            }
            .disabled(true)
        }
    }

    private var lastAttendedLabel: String {
        guard let date = stats.lastAttendedAt else { return "No recorded attendance" }
        return "Last attended \(date.formatted(date: .abbreviated, time: .omitted))"
    }
}

/// The prominent capture-modality tile pair above the detail rows.
private struct ModalityButtonLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.tint)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
        .contentShape(.rect)
    }
}

private struct CircularCheck: View {
    let isChecked: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isChecked ? Color.accentColor : .clear)
            Circle()
                .stroke(isChecked ? Color.accentColor : Color.secondary.opacity(0.45), lineWidth: 1.5)
            if isChecked {
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }
}

private struct QuickAddPersonRow: View {
    @Bindable var viewModel: ChecklistViewModel
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus.circle.fill")
                .font(.title3)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            TextField("Add person…", text: $viewModel.quickAddName)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .focused($isFocused)
                .onSubmit {
                    Task { try? await viewModel.commitQuickAdd() }
                }
                .accessibilityLabel("Add person")
                .accessibilityHint("Enter a name, then press Return.")
                .accessibilityIdentifier("add-person-field")

            if viewModel.isAddingPerson {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Adding person")
            }
        }
    }
}

private struct GuestEditorView: View {
    @Bindable var viewModel: ChecklistViewModel
    @State private var newGuestName = ""

    var body: some View {
        List {
            Section {
                ForEach(Array(viewModel.draft.guests.indices), id: \.self) { index in
                    HStack {
                        TextField(
                            "Guest name",
                            text: Binding(
                                get: { viewModel.draft.guests[index].name },
                                set: { viewModel.draft.guests[index].name = $0 }
                            )
                        )
                        .textInputAutocapitalization(.words)
                        .accessibilityLabel("Guest \(index + 1) name")
                        if viewModel.isFrequentGuest(viewModel.draft.guests[index].name) {
                            FrequentGuestBadge()
                            Button("Add as member") {
                                promote(viewModel.draft.guests[index].name)
                            }
                            .font(.caption)
                            .buttonStyle(.borderless)
                        }
                    }
                }
                .onDelete(perform: viewModel.removeGuests)

                HStack {
                    TextField("Add guest…", text: $newGuestName)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit(addGuest)
                        .accessibilityLabel("Add guest name")
                        .accessibilityIdentifier("add-guest-field")
                    Button("Add", action: addGuest)
                        .disabled(newGuestName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } header: {
                Text("Guest names")
            } footer: {
                Text("The sheet receives only the total guest count. Names stay on this device.")
            }

            Section("Sheet value") {
                LabeledContent("+1's", value: viewModel.draft.plusOnes.formatted())
            }
        }
        .navigationTitle("Guests")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func addGuest() {
        viewModel.addGuest(name: newGuestName)
        newGuestName = ""
    }

    private func promote(_ name: String) {
        viewModel.quickAddName = name
        Task { try? await viewModel.commitQuickAdd() }
    }
}
