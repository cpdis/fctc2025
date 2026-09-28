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
    @Query private var cachedGuests: [CachedGuest]
    @Query private var sheetCaches: [SharedSheetCache]
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
        let runSnapshots = scopedRuns
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
                .buttonStyle(.pressable)
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
                    GuestEditorView(runtime: runtime, viewModel: viewModel)
                } label: {
                    HStack {
                        Label("Guests", systemImage: "person.2")
                        Spacer(minLength: 16)
                        Text(viewModel.draft.plusOnes, format: .number)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(viewModel.draft.plusOnes)))
                            .animation(Motion.snappy, value: viewModel.draft.plusOnes)
                    }
                }
                .accessibilityLabel("Guests, \(viewModel.draft.plusOnes)")
                .accessibilityIdentifier("guest-editor")
            }

            Section {
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

                QuickAddPersonRow(viewModel: viewModel)
            } header: {
                AttendanceCountHeader(draft: viewModel.draft)
            }

            if !viewModel.unresolvedGuestNames.isEmpty {
                Section {
                    NavigationLink("Review suggested guest names") { GuestEditorView(runtime: runtime, viewModel: viewModel) }
                    Text("Select each suggested guest before confirming attendance.").font(.footnote).foregroundStyle(.secondary)
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
            // Inside the tab shell, automatic placement moves search into a
            // navigation-bar drawer that stays hidden until a pull-down. Pin it
            // to the bottom bar, where it sat before the tabs (U11).
            DefaultToolbarItem(kind: .search, placement: .bottomBar)
        }
        // The bottom search and the tab bar cannot share the bottom edge, so the
        // checklist hides the tab bar like the run picker does.
        .toolbarVisibility(.hidden, for: .tabBar)
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
            if !viewModel.requiresGuestOverwrite {
                Button("Merge — \(mergeSummary)") { submit(mode: .merge) }
                    .accessibilityIdentifier("confirm-merge")
            }
            Button(viewModel.requiresGuestOverwrite ? "Overwrite — save guest correction" : "Overwrite — \(overwriteSummary)") { submit(mode: .overwrite) }
                .accessibilityIdentifier("confirm-overwrite")
            Button("Cancel", role: .cancel) {}
        } message: {
            if viewModel.requiresGuestOverwrite {
                Text("This guest correction needs an overwrite. \(viewModel.guestDiff(for: .overwrite).summary). Overwrite uses this checklist exactly.")
            } else {
                Text("Merge keeps sheet attendance. Merge: \(viewModel.guestDiff(for: .merge).summary). Overwrite: \(viewModel.guestDiff(for: .overwrite).summary).")
            }
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
                onGuestNames: guestReview,
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

    private var guestReview: (([String]) -> Void)? {
        guard viewModel.supportsSharedGuests else { return nil }
        return { names in viewModel.requireGuestReview(names) }
    }

    private var exactState: SheetState? {
        guard let identity = viewModel.run.runIdentity else { return nil }
        return sheetCaches.first { $0.endpointIdentity == runtime.config.endpoint?.absoluteString
            && $0.spreadsheetId == identity.spreadsheetId && $0.seasonSheetId == identity.seasonSheetId }?.state
    }
    private var scopedRuns: [RunSnapshot] {
        RunCacheScope.runs(cachedRuns.map(RunSnapshot.init), endpoint: runtime.config.endpoint?.absoluteString, state: exactState)
    }

    private var filteredRoster: [String] {
        guard !searchText.isEmpty else { return viewModel.roster }
        return viewModel.roster.filter {
            $0.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var cacheFingerprint: String {
        let roster = cachedMembers.map { "\($0.name):\($0.colIndex):\($0.isNew)" }
        let guests = cachedGuests.compactMap(\.guest).map { "\($0.guestId):\($0.displayName):\($0.revision)" }
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
        viewModel.updateRoster(exactState?.roster.map(\.name) ?? cachedMembers.map(\.name))
        viewModel.updateSharedGuests(cachedGuests.filter { $0.spreadsheetId == viewModel.run.runIdentity?.spreadsheetId }.compactMap(\.guest))
    }

    private func submit(mode: SubmissionMode) {
        Task {
            do {
                _ = try await viewModel.confirm(mode: mode)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                let snapshots = scopedRuns
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
            among: scopedRuns
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
