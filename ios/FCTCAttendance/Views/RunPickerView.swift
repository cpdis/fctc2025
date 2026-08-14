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
    @State private var viewModel: RunPickerViewModel
    @State private var showingAddRun = false

    init(runtime: AppRuntime, scope: RunPickerScope = .all) {
        self.runtime = runtime
        self.scope = scope
        _viewModel = State(initialValue: RunPickerViewModel(engine: runtime.engine))
    }

    var body: some View {
        let catchUpRuns = catchUpRuns

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

            ForEach(viewModel.sections) { section in
                Section(section.kind.rawValue) {
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

            if viewModel.sections.isEmpty {
                ContentUnavailableView(
                    scope == .past ? "No Past Runs" : "No Runs",
                    systemImage: "calendar.badge.plus",
                    description: Text("Add a scheduled run or refresh the sheet.")
                )
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(scope == .past ? "Past Runs" : "Choose Run")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddRun = true
                } label: {
                    Label("Add Run", systemImage: "plus")
                }
                .accessibilityIdentifier("add-run")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let selected = viewModel.selectedRun {
                NavigationLink(value: HomeRoute.checklist(selected, .standard)) {
                    Label("Review \(selected.date)", systemImage: "checklist")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
                .accessibilityIdentifier("review-default-run")
            }
        }
        .sheet(isPresented: $showingAddRun) {
            AddRunView(viewModel: viewModel)
        }
        .task { updateFromCache() }
        .onChange(of: cacheFingerprint) { _, _ in updateFromCache() }
        .onChange(of: runtime.generation) { _, _ in
            viewModel.replaceEngine(runtime.engine)
        }
    }

    private var cacheFingerprint: [RunSnapshot] {
        cachedRuns.map(RunSnapshot.init)
    }

    private var catchUpRuns: [RunSnapshot] {
        CatchUpPlanner.unrecordedPastRuns(among: cachedRuns.map(RunSnapshot.init))
    }

    private func updateFromCache() {
        let now = Date.now
        let calendar = Calendar.current
        let snapshots = cachedRuns.map(RunSnapshot.init).filter { run in
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
        viewModel.update(runs: snapshots, now: now, calendar: calendar)
    }
}

private struct RunRow: View {
    let run: RunSnapshot
    let isDefault: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(run.date)
                    .font(.headline)
                Spacer(minLength: 8)
                if run.hasRecordedAttendance {
                    Label("Recorded", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .labelStyle(.iconOnly)
                        .accessibilityLabel("Attendance recorded")
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
    @State private var date = Date.now
    @State private var meet = ""
    @State private var run = ""
    @State private var approxKm: Double?

    var body: some View {
        NavigationStack {
            Form {
                Section("Run details") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                        .accessibilityIdentifier("new-run-date")
                    TextField("Meet", text: $meet)
                        .textInputAutocapitalization(.words)
                        .accessibilityLabel("Meeting place")
                        .accessibilityIdentifier("new-run-meet")
                    TextField("Run", text: $run)
                        .textInputAutocapitalization(.words)
                        .accessibilityLabel("Run name")
                        .accessibilityIdentifier("new-run-name")
                    TextField("Approx kms", value: $approxKm, format: .number)
                        .keyboardType(.decimalPad)
                        .accessibilityLabel("Approximate kilometres")
                        .accessibilityIdentifier("new-run-km")
                }

                if let message = viewModel.errorMessage {
                    Section {
                        Text(message)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Add Run")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task {
                            do {
                                try await viewModel.addRun(request)
                                dismiss()
                            } catch {}
                        }
                    }
                    .disabled(!canAdd || viewModel.isAddingRun)
                    .accessibilityIdentifier("new-run-submit")
                }
            }
        }
    }

    private var canAdd: Bool {
        !meet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !run.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var request: AddRunRequest {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, d-MMM"
        return AddRunRequest(
            date: formatter.string(from: date),
            meet: meet.trimmingCharacters(in: .whitespacesAndNewlines),
            run: run.trimmingCharacters(in: .whitespacesAndNewlines),
            approxKm: approxKm
        )
    }
}
