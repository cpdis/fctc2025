import FCTCAttendanceKit
import SwiftUI

/// The sheet owns one explicit allocation choice. Its purpose cannot leak into
/// the Returning guests list, where a selection always adds another attendee.
enum GuestPickerPurpose: Identifiable {
    case nameUnnamed
    case replace(Guest)

    var id: String {
        switch self {
        case .nameUnnamed: "unnamed"
        case .replace(let guest): guest.id.uuidString
        }
    }

    var replacementID: UUID? {
        if case .replace(let guest) = self { guest.id } else { nil }
    }

    var namesUnnamedGuest: Bool {
        if case .nameUnnamed = self { true } else { false }
    }
}

struct GuestPickerView: View {
    @Bindable var viewModel: ChecklistViewModel
    let purpose: GuestPickerPurpose
    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameIsFocused: Bool
    @State private var name = ""
    @State private var isCreating = false
    @State private var showingDistinctChoice = false
    @State private var error: String?

    var body: some View {
        let availableGuests = availableGuests
        NavigationStack {
            List {
                Section {
                    TextField("Find or enter a name", text: $name)
                        .textInputAutocapitalization(.words)
                        .focused($nameIsFocused)
                        .submitLabel(.done)
                        .onSubmit { nameIsFocused = false }
                        .accessibilityIdentifier("guest-picker-name")
                    if !cleanName.isEmpty {
                        Button("Use new name ‘\(cleanName)’", systemImage: "person.badge.plus") {
                            if viewModel.sharedGuests.contains(where: {
                                GuestNames.canonical($0.displayName) == GuestNames.canonical(cleanName)
                            }) {
                                showingDistinctChoice = true
                            } else { create(confirmDistinct: false) }
                        }
                        .accessibilityIdentifier("guest-picker-create")
                    }
                    if isCreating { ProgressView("Saving name…") }
                } footer: {
                    Text(instructions)
                }

                Section("Saved guests") {
                    ForEach(availableGuests) { guest in
                        Button { select(guest) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(guest.displayName).foregroundStyle(.primary)
                                Text("\(guest.confirmedRuns ?? 0) confirmed runs")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("guest-picker-select-\(guest.displayName)")
                    }
                    if availableGuests.isEmpty {
                        Text(cleanName.isEmpty ? "Enter a name above to name this guest." : "No saved guests match this name.")
                            .foregroundStyle(.secondary)
                    }
                }

                if let error {
                    Section { Text(error).font(.footnote).foregroundStyle(.red) }
                }
            }
            .disabled(isCreating)
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle(purpose.namesUnnamedGuest ? "Name a guest" : "Replace guest")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isCreating)
                        .accessibilityIdentifier("guest-picker-cancel")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    if nameIsFocused {
                        Spacer()
                        Button("Done") { nameIsFocused = false }
                            .accessibilityIdentifier("guest-picker-keyboard-done")
                    }
                }
            }
            .confirmationDialog("Is this a different person?", isPresented: $showingDistinctChoice, titleVisibility: .visible) {
                Button("Create a different person with this name") { create(confirmDistinct: true) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("A saved guest already has this name. Select that person to keep their run history.")
            }
        }
        .interactiveDismissDisabled(isCreating)
    }

    private var cleanName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var availableGuests: [SharedGuest] {
        let selected = Set(viewModel.draft.namedGuestIds)
        let query = GuestNames.canonical(cleanName)
        return viewModel.sharedGuests.filter { guest in
            guest.isActive && !selected.contains(guest.guestId)
                && (query.isEmpty || GuestNames.canonical(guest.displayName).contains(query))
        }
    }

    private var instructions: String {
        let action: String
        switch purpose {
        case .nameUnnamed: action = "Choose a saved guest or enter a new name for one unnamed guest."
        case .replace(let guest): action = "Choose who attended in place of \(guest.name)."
        }
        return "\(action) The total stays at \(viewModel.draft.plusOnes) guests."
    }

    private func select(_ guest: SharedGuest) {
        nameIsFocused = false
        viewModel.selectGuest(guest, namingUnnamed: purpose.namesUnnamedGuest, replacing: purpose.replacementID)
        viewModel.resolveProposedName(guest.displayName)
        dismiss()
    }

    private func create(confirmDistinct: Bool) {
        let requestedName = cleanName
        nameIsFocused = false
        error = nil
        isCreating = true
        Task {
            defer { isCreating = false }
            do {
                try await viewModel.createSharedGuest(name: requestedName, confirmDistinct: confirmDistinct,
                    namingUnnamed: purpose.namesUnnamedGuest, replacing: purpose.replacementID)
                viewModel.resolveProposedName(requestedName)
                dismiss()
            } catch { self.error = UserFacingError.sync(error) }
        }
    }
}
