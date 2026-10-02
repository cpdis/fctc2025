//
//  RunPickerView.swift
//  FCTCAttendance
//

import FCTCAttendanceKit
import SwiftData
import SwiftUI

enum RunPickerScope: Hashable, Sendable {
    case all
    case thisWeek
    case past
}

struct RunPickerView: View {
    let runtime: AppRuntime
    let scope: RunPickerScope

    @Query(sort: \ScheduledRun.rowIndex) private var cachedRuns: [ScheduledRun]
    @Query private var sheetCaches: [SharedSheetCache]
    @State private var viewModel: RunPickerViewModel
    /// Past runs still missing attendance, newest first. Stored by
    /// `updateFromCache()` with the sections, so a render never resolves the
    /// season cache.
    @State private var catchUpRuns: [RunSnapshot] = []
    @State private var showingAddRun = false
    @State private var searchText = ""

    private var title: String {
        switch scope {
        case .all: "Season"
        case .thisWeek: "This Week"
        case .past: "Past Runs"
        }
    }

    /// Locale-aware, case- and diacritic-insensitive match on meet, run name, and the sheet-style date text.
    private var filteredSections: [RunSection] {
        guard !searchText.isEmpty else { return viewModel.sections }
        return viewModel.sections.compactMap { section in
            let runs = section.runs.filter { run in
                run.meet.localizedStandardContains(searchText)
                    || run.run.localizedStandardContains(searchText)
                    || run.date.localizedStandardContains(searchText)
            }
            guard !runs.isEmpty else { return nil }
            var filtered = section
            filtered.runs = runs
            return filtered
        }
    }

    init(runtime: AppRuntime, scope: RunPickerScope = .all) {
        self.runtime = runtime
        self.scope = scope
        _viewModel = State(initialValue: RunPickerViewModel(engine: runtime.engine))
    }

    var body: some View {
        List {
            if scope == .past, catchUpRuns.count >= 2, let start = catchUpRuns.first {
                Section {
                    NavigationLink(value: HomeRoute.checklist(start, .standard)) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Catch Up")
                                    .font(.headline)
                                Text("\(catchUpRuns.count) past runs need attendance")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                                .foregroundStyle(.tint)
                        }
                    }
                    .accessibilityIdentifier("past-runs-catch-up")
                }
            }

            ForEach(filteredSections) { section in
                Section(section.title) {
                    ForEach(section.runs) { run in
                        NavigationLink(value: HomeRoute.checklist(run, .standard)) {
                            RunRow(
                                run: run,
                                isDefault: viewModel.selectedRun?.rowIndex == run.rowIndex
                            )
                        }
                        .accessibilityIdentifier("run-row-\(run.rowIndex)")
                    }
                }
            }

            if filteredSections.isEmpty {
                if searchText.isEmpty {
                    ContentUnavailableView(
                        scope == .past ? "No Past Runs" : "No Runs",
                        systemImage: "calendar.badge.plus",
                        description: Text("Add a scheduled run or refresh the sheet.")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ContentUnavailableView.search(text: searchText)
                        .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(title)
        .searchable(text: $searchText, prompt: "Location, run, or date")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddRun = true
                } label: {
                    Label("Add Run", systemImage: "plus")
                }
                .accessibilityIdentifier("add-run")
            }
            // Search and the one primary action share the bottom glass toolbar,
            // per the HIG: search at the bottom, a single prominent action on the
            // trailing side. The Default badge marks which run Review opens.
            DefaultToolbarItem(kind: .search, placement: .bottomBar)
            if let selected = viewModel.selectedRun {
                ToolbarSpacer(.fixed, placement: .bottomBar)
                ToolbarItem(placement: .bottomBar) {
                    NavigationLink(value: HomeRoute.checklist(selected, .standard)) {
                        Text("Review")
                    }
                    .buttonStyle(.glassProminent)
                    .accessibilityLabel("Review \(selected.date)")
                    .accessibilityIdentifier("review-default-run")
                }
            }
        }
        // The bottom toolbar above and the tab bar both claim the bottom edge,
        // and iOS 26 draws the tab bar over the toolbar rather than stacking
        // them. The picker is a focused task, so it hides the tab bar; the tab
        // bar returns when the picker pops (U11, checked on iOS 26.5).
        .toolbarVisibility(.hidden, for: .tabBar)
        .sheet(isPresented: $showingAddRun) {
            AddRunView(viewModel: viewModel)
        }
        .task { updateFromCache() }
        .onChange(of: cacheFingerprint) { _, _ in updateFromCache() }
        .onChange(of: runtime.generation) { _, _ in
            viewModel.replaceEngine(runtime.engine)
        }
    }

    /// Changes whenever the season's runs can. It decodes no JSON, so it is
    /// cheap to build per render.
    private var cacheFingerprint: String {
        runtime.activeRunsFingerprint(runs: cachedRuns, caches: sheetCaches)
    }

    /// The one place the picker resolves the season cache.
    private func updateFromCache() {
        let now = Date.now
        let calendar = Calendar.current
        let runs = runtime.activeRuns(in: cachedRuns).map(RunSnapshot.init)
        catchUpRuns = CatchUpPlanner.unrecordedPastRuns(among: runs, now: now, calendar: calendar)
        let snapshots = runs.filter { run in
            guard let date = run.scheduledAt else { return scope == .all }
            switch scope {
            case .all:
                return true
            case .thisWeek:
                return calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear)
            case .past:
                return date < calendar.startOfDay(for: now)
            }
        }
        viewModel.update(
            runs: snapshots,
            now: now,
            calendar: calendar,
            groupPastByMonth: scope == .past
        )
    }
}

private struct RunRow: View {
    let run: RunSnapshot
    let isDefault: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Status follows the date it describes. At the trailing edge it sat on
            // the first line while the chevron centres on the row, so the two never
            // lined up; centred there, it squeezed the detail line onto two lines.
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(run.date)
                    .font(.headline)
                if run.hasRecordedAttendance {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                } else if isDefault {
                    Text("Default")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.tint)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.tint.opacity(0.12), in: .capsule)
                }
            }
            Text(run.detailLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        [run.date, run.detailLabel, run.hasRecordedAttendance ? "Recorded" : nil]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}

private struct AddRunView: View {
    let viewModel: RunPickerViewModel

    @Environment(\.dismiss) private var dismiss
    /// The form's fields and rules live in the kit so they are unit-tested.
    @State private var draft = AddRunDraft()
    /// An Add that failed, shown as an alert rather than a row below the fold.
    @State private var addError: String?
    /// Same decimal-pad trap as the checklist: no Return key, so the keyboard
    /// needs a Done button and scroll-to-dismiss.
    @FocusState private var kilometresFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $draft.date, displayedComponents: .date)
                        .accessibilityIdentifier("new-run-date")
                    TextField("Meet", text: $draft.meet)
                        .textInputAutocapitalization(.words)
                        .accessibilityLabel("Meeting place")
                        .accessibilityInputLabels(["Meet", "Meeting place"])
                        .accessibilityIdentifier("new-run-meet")
                    TextField("Run", text: $draft.run)
                        .textInputAutocapitalization(.words)
                        .accessibilityLabel("Run name")
                        .accessibilityInputLabels(["Run", "Run name"])
                        .accessibilityIdentifier("new-run-name")
                    TextField("Approx km", text: $draft.approxKmText)
                        .keyboardType(.decimalPad)
                        .focused($kilometresFocused)
                        .accessibilityLabel("Approximate kilometres")
                        .accessibilityInputLabels(["Approx km", "Approx kms", "Approximate kilometres"])
                        // The error also rides in the hint, next to the field.
                        .accessibilityHint(draft.distanceIsMalformed ? DistanceText.malformedMessage : "")
                        .accessibilityIdentifier("new-run-km")
                } header: {
                    Text("Run details")
                } footer: {
                    if draft.distanceIsMalformed {
                        Text(DistanceText.malformedMessage)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("new-run-km-error")
                    }
                }

                if let message = viewModel.errorMessage {
                    Section {
                        Text(message)
                            .foregroundStyle(.red)
                    }
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .actionErrorAlert("Could not add run", message: $addError)
            // The footer and the alert are visual; say each error out loud.
            .onChange(of: draft.distanceIsMalformed) { _, malformed in
                if malformed { AccessibilityNotification.Announcement(DistanceText.malformedMessage).post() }
            }
            .onChange(of: viewModel.errorMessage) { _, message in
                if let message { AccessibilityNotification.Announcement(message).post() }
            }
            .onChange(of: addError) { _, message in
                if let message { AccessibilityNotification.Announcement(message).post() }
            }
            .navigationTitle("Add Run")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    if kilometresFocused {
                        Spacer()
                        Button("Done") { kilometresFocused = false }
                            .accessibilityIdentifier("new-run-km-keyboard-done")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task {
                            do {
                                try await viewModel.addRun(draft.request)
                                dismiss()
                            } catch is CancellationError {
                                // A second tap while the first add ran.
                            } catch {
                                addError = viewModel.errorMessage ?? UserFacingError.sync(error)
                            }
                        }
                    }
                    .disabled(!draft.canAdd || viewModel.isAddingRun)
                    .accessibilityIdentifier("new-run-submit")
                }
            }
        }
    }
}
