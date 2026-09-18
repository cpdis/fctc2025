import FCTCAttendanceKit
import SwiftData
import SwiftUI

struct GuestNameEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var operations: [PendingGuestOperation]
    @State private var model: GuestNameViewModel
    @FocusState private var nameIsFocused: Bool
    private let onSaved: (SharedGuest) -> Void

    init(runtime: AppRuntime, guest: SharedGuest? = nil, operationId: UUID? = nil,
         onSaved: @escaping (SharedGuest) -> Void = { _ in }) {
        _model = State(initialValue: GuestNameViewModel(guest: guest, operationId: operationId, engine: runtime.engine))
        self.onSaved = onSaved
    }

    var body: some View {
        List {
            if model.isPending {
                Section {
                    Label("Name change pending", systemImage: "clock")
                    Text("Your name change is saved on this phone. You can leave this screen while it syncs.")
                        .foregroundStyle(.secondary)
                    if let reason = operationMessage ?? model.operation?.message {
                        Text(reason).font(.footnote).foregroundStyle(.secondary)
                            .accessibilityIdentifier("guest-name-pending-reason")
                    }
                    LabeledContent("New name", value: model.name)
                    Button("Check again") { Task { await model.check() } }
                        .disabled(model.isWorking).accessibilityIdentifier("guest-name-check")
                }
            } else {
                if model.needsReview {
                    Section("Review name change") {
                        Text("This change did not save. Review the saved name, then choose which name to keep.")
                        LabeledContent("Saved name", value: model.guest?.displayName ?? "Loading…")
                            .accessibilityIdentifier("guest-name-saved")
                        if let reason = model.operation?.message {
                            Text(reason).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    TextField("Name", text: $model.name)
                        .textInputAutocapitalization(.words).focused($nameIsFocused)
                        .submitLabel(.done).onSubmit { nameIsFocused = false }
                        .disabled(model.isWorking || !model.reviewReady)
                        .accessibilityIdentifier("guest-name-field")
                } header: {
                    Text(model.needsReview ? "Your correction" : "Guest name")
                } footer: {
                    Text("This saves the name for every organiser. All previous runs stay with this person.")
                }
                Section {
                    Button("Save name") {
                        nameIsFocused = false
                        Task { await model.save() }
                    }.disabled(!model.canSave).accessibilityIdentifier("guest-name-save")
                    if model.needsReview {
                        Button("Keep saved name") { Task { await model.keepSavedName() } }
                            .disabled(model.isWorking).accessibilityIdentifier("guest-name-keep")
                    }
                }
            }
            if model.isWorking { ProgressView("Checking saved name…") }
            if let error = model.errorMessage {
                Section {
                    Text(error).foregroundStyle(.red).font(.footnote)
                    Button("Refresh saved name") { Task { await model.load() } }
                        .disabled(model.isWorking)
                }
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle(model.needsReview ? "Review name" : "Correct name")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(model.isPending ? "Done" : "Cancel") { dismiss() }
                    .accessibilityIdentifier("guest-name-close")
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { nameIsFocused = false }.accessibilityIdentifier("guest-name-keyboard-done")
            }
        }
        .task { await model.load() }
        .onChange(of: operationPhase) { _, _ in Task { await model.observeSavedChange() } }
        .onChange(of: model.finished) { _, finished in
            guard finished else { return }
            if let guest = model.savedGuest { onSaved(guest) }
            dismiss()
        }
    }

    private var operationPhase: GuestOperationPhase? {
        operations.first { $0.id == model.operationId }?.phase
    }

    // Retry failures can update the message without changing the pending phase.
    private var operationMessage: String? {
        operations.first { $0.id == model.operationId }?.lastError
    }
}
