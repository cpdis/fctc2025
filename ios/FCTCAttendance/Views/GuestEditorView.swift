import FCTCAttendanceKit
import SwiftData
import SwiftUI

/// Selecting a saved identity adds attendance. Naming an unnamed slot is a
/// separate action, so a correction cannot accidentally increase headcount.
struct GuestEditorView: View {
    let runtime: AppRuntime
    @Bindable var viewModel: ChecklistViewModel
    @Query private var cachedGuests: [CachedGuest]
    @Query private var provisionalGuests: [ProvisionalGuest]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var nameIsFocused: Bool
    @State private var name = ""
    @State private var proposedName: String?
    @State private var guestPicker: GuestPickerPurpose?
    @State private var showingDistinctChoice = false
    @State private var isCreating = false
    @State private var error: String?
    @State private var historyGuest: SharedGuest?

    var body: some View {
        List {
            if !viewModel.supportsSharedGuests {
                Section {
                    Label("Shared guests need a sheet update", systemImage: "arrow.triangle.2.circlepath")
                    Text("Refresh after shared guests are enabled. Existing local names remain available in Settings → Recover guest history.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            if !viewModel.unresolvedGuestNames.isEmpty {
                Section("Review suggested guests") {
                    ForEach(viewModel.unresolvedGuestNames, id: \.self) { suggestion in
                        HStack {
                            Button(suggestion) { name = suggestion; proposedName = suggestion }
                            Spacer()
                            Button("Ignore") { viewModel.dismissProposedName(suggestion) }.buttonStyle(.borderless)
                        }
                    }
                    Text("Select a shared guest or create a new person below.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            if !viewModel.draft.guests.isEmpty {
                Section("On this run") {
                    ForEach(viewModel.draft.guests) { guest in
                        selectedGuestLayout {
                            HStack {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                                Text(guest.name).accessibilityIdentifier("selected-guest-\(guest.name)")
                            }
                            if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                            if let shared = viewModel.sharedGuests.first(where: { $0.guestId == guest.id.uuidString.lowercased() }) {
                                NavigationLink { GuestDetailView(runtime: runtime, guest: shared, checklist: viewModel) } label: {
                                    Text("\(shared.confirmedRuns ?? 0) runs").foregroundStyle(.secondary)
                                }.accessibilityIdentifier("guest-history-\(shared.displayName)")
                            } else {
                                Text("Pending").font(.caption).foregroundStyle(.orange)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Remove", role: .destructive) { viewModel.removeGuest(id: guest.id) }
                            Button("Replace") { showPicker(.replace(guest)) }.tint(.blue)
                        }
                    }
                }
            }
            Section {
                Stepper("Unnamed guests: \(viewModel.draft.unnamedGuests ?? 0)", value: Binding(
                    get: { viewModel.draft.unnamedGuests ?? 0 },
                    set: { viewModel.draft.unnamedGuests = $0 }
                ), in: 0...999)
                .accessibilityIdentifier("unnamed-guests")
                if (viewModel.draft.unnamedGuests ?? 0) > 0 {
                    Button("Name a guest", systemImage: "person.crop.circle.badge.questionmark") {
                        showPicker(.nameUnnamed)
                    }.accessibilityIdentifier("name-unnamed-guest")
                }
            } footer: {
                Text("Name an unnamed guest without changing the total.")
            }
            Section {
                TextField("Find or add a guest", text: $name)
                    .textInputAutocapitalization(.words)
                    .focused($nameIsFocused)
                    .submitLabel(.done)
                    .onSubmit { nameIsFocused = false }
                    .accessibilityIdentifier("add-guest-field")
                ForEach(availableGuests) { guest in
                    HStack {
                        Button { select(guest) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "circle").foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(guest.displayName).foregroundStyle(.primary)
                                    Text(guestSummary(guest)).font(.caption).foregroundStyle(.secondary)
                                    if guest.canSuggestPromotion {
                                        Text("Ready to add as a member").font(.caption).foregroundStyle(.tint)
                                    }
                                }
                                Spacer(minLength: 0)
                            }.contentShape(.rect)
                        }.buttonStyle(.plain).accessibilityIdentifier("select-guest-\(guest.displayName)")
                        Button { historyGuest = guest } label: {
                            Image(systemName: "info.circle").frame(minWidth: 44, minHeight: 44)
                                .accessibilityLabel("\(guest.displayName) history")
                        }.buttonStyle(.borderless).accessibilityIdentifier("guest-history-\(guest.displayName)")
                    }
                }
                if !cleanName.isEmpty {
                    Button("Create new guest ‘\(cleanName)’", systemImage: "person.badge.plus") {
                        if viewModel.sharedGuests.contains(where: { GuestNames.canonical($0.displayName) == GuestNames.canonical(cleanName) }) {
                            showingDistinctChoice = true
                        } else { create(confirmDistinct: false) }
                    }.disabled(isCreating).accessibilityIdentifier("create-shared-guest")
                }
            } header: { Text("Returning guests") } footer: {
                Text("Saved names and confirmed run counts are shared with every organiser. Selecting a guest adds them to this run.")
            }
            Section("Run total") {
                LabeledContent("Guests", value: viewModel.draft.plusOnes.formatted())
                Text(viewModel.guestDiff(for: .overwrite).summary).font(.footnote).foregroundStyle(.secondary)
            }
            if let error = error ?? viewModel.errorMessage {
                Section { Text(error).foregroundStyle(.red).font(.footnote) }
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle("Guests").navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $historyGuest) { GuestDetailView(runtime: runtime, guest: $0, checklist: viewModel) }
        .sheet(item: $guestPicker) { purpose in
            GuestPickerView(viewModel: viewModel, purpose: purpose)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if nameIsFocused {
                    Spacer()
                    Button("Done") { nameIsFocused = false }
                        .accessibilityIdentifier("guest-keyboard-done")
                }
            }
        }
        .disabled(!viewModel.supportsSharedGuests)
        .confirmationDialog("Is this a different person?", isPresented: $showingDistinctChoice, titleVisibility: .visible) {
            Button("Create a different person with this name") { create(confirmDistinct: true) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("A shared guest already has this name. Select that person to retain their history.") }
        .task { await viewModel.loadSharedGuests(); resolveProvisionalSelections() }
        .onChange(of: cachedGuests.compactMap(\.guest)) { _, _ in reloadCachedGuests() }
        .onChange(of: provisionalGuests.map { "\($0.guestId):\($0.resolvedGuestId ?? "")" }) { _, _ in
            resolveProvisionalSelections()
        }
    }

    private var cleanName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var selectedGuestLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout())
    }
    private var availableGuests: [SharedGuest] {
        let selected = Set(viewModel.draft.namedGuestIds)
        let query = GuestNames.canonical(cleanName)
        return viewModel.sharedGuests.filter { guest in
            guest.isActive && !selected.contains(guest.guestId)
                && (query.isEmpty || GuestNames.canonical(guest.displayName).contains(query))
        }
    }
    private func reloadCachedGuests() {
        viewModel.updateSharedGuests(cachedGuests.filter { $0.spreadsheetId == viewModel.run.runIdentity?.spreadsheetId }.compactMap(\.guest))
        resolveProvisionalSelections()
    }
    private func resolveProvisionalSelections() {
        for guest in provisionalGuests where guest.endpointIdentity == runtime.config.endpoint?.absoluteString {
            if let resolved = guest.resolvedGuestId { viewModel.replaceProvisional(id: guest.guestId, sharedId: resolved) }
        }
    }
    private func guestSummary(_ guest: SharedGuest) -> String {
        let last = guest.lastAttendance.map { " · Last \($0.date), \($0.seasonYear)" } ?? ""
        return "\(guest.confirmedRuns ?? 0) confirmed runs\(last)"
    }
    private func select(_ guest: SharedGuest) {
        nameIsFocused = false
        viewModel.selectGuest(guest)
        viewModel.resolveProposedName(proposedName ?? name)
        name = ""; proposedName = nil
    }
    private func showPicker(_ purpose: GuestPickerPurpose) {
        nameIsFocused = false
        guestPicker = purpose
    }
    private func create(confirmDistinct: Bool) {
        let requestedName = cleanName
        nameIsFocused = false
        isCreating = true
        Task {
            defer { isCreating = false }
            do {
                try await viewModel.createSharedGuest(name: requestedName, confirmDistinct: confirmDistinct)
                viewModel.resolveProposedName(proposedName ?? requestedName)
                name = ""; proposedName = nil
            } catch { self.error = UserFacingError.sync(error) }
        }
    }
}
