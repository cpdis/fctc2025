//
//  ChecklistViewModel.swift
//  FCTCAttendanceKit
//

import Foundation
import Observation

@MainActor
@Observable
public final class ChecklistViewModel {
    public private(set) var run: RunSnapshot
    public private(set) var roster: [String]
    public var draft: AttendanceDraft
    public var actualKmText: String {
        didSet { draft.actualKm = Self.parseDistance(actualKmText) }
    }
    public var quickAddName = ""
    public private(set) var isSubmitting = false
    public private(set) var isAddingPerson = false
    public private(set) var errorMessage: String?
    public private(set) var sharedGuests: [SharedGuest] = []
    public private(set) var unresolvedGuestNames: [String] = []

    @ObservationIgnored private var engine: any SyncEngineClient
    @ObservationIgnored private let deviceName: String?
    @ObservationIgnored private let eventMonitor = SyncEventMonitor()

    // Pristine-at-init values: a dictated/OCR'd number may only fill a field the
    // human has not touched this session (U7 rule: typed kms survives dictation).
    @ObservationIgnored private var initialKmText = ""
    @ObservationIgnored private var initialPlusOnesOverride: Int?
    @ObservationIgnored private var initialGuestCount = 0

    public init(
        run: RunSnapshot,
        roster: [String],
        draft suppliedDraft: AttendanceDraft? = nil,
        engine: any SyncEngineClient,
        deviceName: String? = nil
    ) {
        self.run = run
        self.roster = roster.sorted(by: Member.sheetOrder)
        self.engine = engine
        self.deviceName = deviceName

        var draft = suppliedDraft ?? AttendanceDraft(
            rowIndex: run.rowIndex,
            expectedDate: run.date,
            expectedRun: run.run,
            checks: Dictionary(uniqueKeysWithValues: run.attendees.map { ($0, .manual) }),
            actualKm: run.actualKm ?? run.approxKm,
            plusOnesOverride: run.plusOnes,
            baseRevision: run.cachedRevision,
            runIdentity: run.runIdentity, endpointIdentity: run.endpointIdentity,
            unnamedGuests: run.runIdentity == nil ? nil : run.unnamedGuests
        )
        if suppliedDraft == nil {
            draft.guests = run.namedGuestIds.compactMap { id in
                UUID(uuidString: id).map { Guest(id: $0, name: "Saved guest") }
            }
        }
        if draft.actualKm == nil { draft.actualKm = run.actualKm ?? run.approxKm }
        self.draft = draft
        self.actualKmText = Self.formatDistance(draft.actualKm)
        self.initialKmText = self.actualKmText
        self.initialPlusOnesOverride = draft.plusOnesOverride
        self.initialGuestCount = draft.guests.count
        observeEvents()
    }

    // MARK: Smart-modality proposals (the frozen U6/U7 seam)

    /// Apply a triage outcome to the draft. `checks` is the human-confirmed final
    /// list from the triage sheet: the auto-check tier minus any unticks, plus
    /// explicit picks and mappings. Names not on the roster are ignored — "add as
    /// new person" goes through `addPerson`, never through here. Proposal checks
    /// never downgrade a `.manual` check (enforced by `AttendanceDraft.check`),
    /// and extracted numbers only fill fields the human has not edited.
    public func applyProposals(checks: [String], from set: DraftProposalSet) {
        let rosterKeys = Set(roster)
        for name in checks where rosterKeys.contains(name) {
            draft.check(name, provenance: set.provenance)
        }

        if let distance = set.distanceKm, actualKmText == initialKmText {
            actualKmText = Self.formatDistance(distance)
        }

        let hadUntouchedGuests = draft.guests.count == initialGuestCount
            && draft.plusOnesOverride == initialPlusOnesOverride
        for name in set.guestNames {
            if supportsSharedGuests {
                if !unresolvedGuestNames.contains(name) { unresolvedGuestNames.append(name) }
                continue
            }
            let key = GuestNames.canonical(name)
            guard !key.isEmpty,
                  !draft.guests.contains(where: { GuestNames.canonical($0.name) == key })
            else { continue }
            draft.guests.append(Guest(name: name))
            draft.plusOnesOverride = nil
        }
        // A bare count ("plus two") without names sets the override, but only when
        // the human had not already curated guests or the count themselves.
        if let plusOnes = set.plusOnes, set.guestNames.isEmpty, hadUntouchedGuests {
            if supportsSharedGuests { draft.unnamedGuests = plusOnes }
            else { draft.plusOnesOverride = plusOnes }
        }
    }

    public var canConfirm: Bool {
        !isSubmitting && unresolvedGuestNames.isEmpty && draftDiffersFromSheet
    }

    public var draftDiffersFromSheet: Bool {
        Set(draft.attendees) != Set(run.attendees)
            || Set(draft.namedGuestIds) != Set(run.namedGuestIds)
            || draft.plusOnes != run.plusOnes
            || (draft.actualKm ?? run.actualKm) != run.actualKm
    }

    public var requiresRecordedChoice: Bool { run.hasRecordedAttendance || requiresGuestOverwrite }

    /// Merge cannot remove a saved named guest or consume a saved unnamed slot.
    /// Derive this from the final allocation so undoing an edit clears the guard.
    public var requiresGuestOverwrite: Bool {
        supportsSharedGuests && (!Set(run.namedGuestIds).isSubset(of: Set(draft.namedGuestIds))
            || (draft.unnamedGuests ?? 0) < run.unnamedGuests)
    }

    public var supportsSharedGuests: Bool { run.runIdentity != nil }

    public func updateRoster(_ names: [String]) { roster = names.sorted(by: Member.sheetOrder) }

    public func loadSharedGuests() async {
        do { updateSharedGuests(try await engine.sharedGuests()) }
        catch { errorMessage = UserFacingError.sync(error) }
    }

    public func updateSharedGuests(_ guests: [SharedGuest]) {
        sharedGuests = guests.sorted { Member.sheetOrder($0.displayName, $1.displayName) }
        for index in draft.guests.indices {
            if let shared = guests.first(where: { $0.guestId == draft.guests[index].id.uuidString.lowercased() }) {
                draft.guests[index].name = shared.displayName
            }
        }
    }

    public func selectGuest(_ guest: SharedGuest, namingUnnamed: Bool = false, replacing: UUID? = nil) {
        guard guest.isActive, let selected = guest.draftGuest else { return }
        selectGuest(selected, namingUnnamed: namingUnnamed, replacing: replacing)
    }

    private func selectGuest(_ guest: Guest, namingUnnamed: Bool, replacing: UUID?) {
        guard !draft.guests.contains(where: { $0.id == guest.id }) else { return }
        if let replacing {
            guard let index = draft.guests.firstIndex(where: { $0.id == replacing }) else { return }
            draft.guests[index] = guest
        } else {
            if namingUnnamed {
                guard let count = draft.unnamedGuests, count > 0 else { return }
                draft.unnamedGuests = count - 1
            }
            draft.guests.append(guest)
        }
    }

    public func createSharedGuest(name: String, confirmDistinct: Bool = false, namingUnnamed: Bool = false, replacing: UUID? = nil) async throws {
        let guest = try await engine.createGuest(name: name, confirmDistinct: confirmDistinct)
        selectGuest(guest, namingUnnamed: namingUnnamed, replacing: replacing)
    }

    public func replaceProvisional(id: String, sharedId: String) {
        guard let guest = sharedGuests.first(where: { $0.guestId == sharedId })?.draftGuest else { return }
        draft.guests = draft.guests.map { $0.id.uuidString.lowercased() == id ? guest : $0 }
        var seen = Set<UUID>()
        draft.guests = draft.guests.filter { seen.insert($0.id).inserted }
    }

    public func removeGuest(id: UUID) { draft.guests.removeAll { $0.id == id } }

    public func requireGuestReview(_ names: [String]) {
        for name in names where !unresolvedGuestNames.contains(name) { unresolvedGuestNames.append(name) }
    }

    public func resolveProposedName(_ name: String) {
        unresolvedGuestNames.removeAll { GuestNames.canonical($0) == GuestNames.canonical(name) }
    }

    public func dismissProposedName(_ name: String) { resolveProposedName(name) }

    public func guestDiff(for mode: SubmissionMode) -> GuestAttendanceDiff {
        let before = Set(run.namedGuestIds), after = Set(draft.namedGuestIds)
        func name(_ id: String) -> String {
            sharedGuests.first(where: { $0.guestId == id })?.displayName
                ?? draft.guests.first(where: { $0.id.uuidString.lowercased() == id })?.name ?? "Saved guest"
        }
        return GuestAttendanceDiff(added: after.subtracting(before).sorted().map(name),
            removed: mode == .overwrite ? before.subtracting(after).sorted().map(name) : [],
            unnamedBefore: run.unnamedGuests,
            unnamedAfter: mode == .merge ? max(run.unnamedGuests, draft.unnamedGuests ?? 0) : draft.unnamedGuests ?? 0)
    }

    /// Adopt only the exact run after its receipt confirms a save or promotion.
    public func acceptSavedState(_ state: SheetState) {
        guard let identity = run.runIdentity, let record = state.runs.first(where: { $0.identity == identity }) else { return }
        run = RunSnapshot(record: record, state: state, endpointIdentity: run.endpointIdentity)
        roster = state.roster.map(\.name)
        sharedGuests = state.guests ?? sharedGuests
        draft = AttendanceDraft(rowIndex: record.rowIndex, expectedDate: record.date, expectedRun: record.run,
            checks: Dictionary(uniqueKeysWithValues: record.attendees.map { ($0, .manual) }),
            guests: (record.namedGuestIds ?? []).compactMap { id in sharedGuests.first { $0.guestId == id }?.draftGuest },
            actualKm: record.actualKm, baseRevision: state.sheetRevision, runIdentity: identity,
            endpointIdentity: run.endpointIdentity, unnamedGuests: record.unnamedGuests ?? 0)
        actualKmText = Self.formatDistance(record.actualKm)
    }

    public func toggleMember(_ name: String) {
        draft.toggle(name)
    }

    public func uncheckMember(_ name: String) {
        draft.uncheck(name)
    }

    public func isSuggested(_ name: String) -> Bool {
        draft.unmatched.contains { unmatched in
            unmatched.suggestions.contains { GuestNames.canonical($0) == GuestNames.canonical(name) }
        }
    }

    public func addGuest(name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        draft.guests.append(Guest(name: clean))
        draft.plusOnesOverride = nil
    }

    public func removeGuests(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            guard draft.guests.indices.contains(index) else { continue }
            draft.guests.remove(at: index)
        }
        draft.plusOnesOverride = nil
    }

    public func commitQuickAdd() async throws {
        let clean = quickAddName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        if supportsSharedGuests && sharedGuests.contains(where: { GuestNames.canonical($0.displayName) == GuestNames.canonical(clean) }) {
            let message = "Open this guest's history to review promotion and retain all previous runs."
            errorMessage = message
            throw SheetAPIError.badPayload(message: message)
        }
        quickAddName = ""
        errorMessage = nil

        if let existing = roster.first(where: { GuestNames.canonical($0) == GuestNames.canonical(clean) }) {
            draft.check(existing)
            return
        }

        // Mirror SyncEngine's optimistic insert in value state. SwiftData catches up
        // through @Query while the network reconciliation is still suspended.
        roster.append(clean)
        roster.sort(by: Member.sheetOrder)
        let oldGuests = draft.guests
        let oldPlusOnesOverride = draft.plusOnesOverride
        draft.check(clean)
        isAddingPerson = true
        defer { isAddingPerson = false }
        do {
            if let identity = run.runIdentity { _ = try await engine.refreshState(seasonSheetId: identity.seasonSheetId) }
            let result = try await engine.addMember(name: clean)
            // Adding a roster column changes the canonical sheet revision. Keep
            // this open draft on that revision so its later Confirm does not queue
            // a stale write.
            draft.baseRevision = result.sheetRevision
        } catch {
            roster.removeAll { GuestNames.canonical($0) == GuestNames.canonical(clean) }
            draft.uncheck(clean)
            draft.guests = oldGuests
            draft.plusOnesOverride = oldPlusOnesOverride
            quickAddName = clean
            errorMessage = UserFacingError.sync(error)
            throw error
        }
    }

    public func diffSummary(
        for mode: SubmissionMode,
        against serverRun: RunRecord? = nil
    ) -> AttendanceDiff {
        let server = Set(serverRun?.attendees ?? run.attendees)
        let local = Set(draft.attendees)
        return AttendanceDiff(
            added: local.subtracting(server).count,
            removed: mode == .overwrite ? server.subtracting(local).count : 0
        )
    }

    @discardableResult
    public func confirm(mode: SubmissionMode) async throws -> UUID {
        guard canConfirm else { throw ChecklistError.unchangedDraft }
        guard mode != .merge || !requiresGuestOverwrite else { throw ChecklistError.guestOverwriteRequired }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            let id = try await engine.enqueue(
                draft: draft,
                mode: mode,
                deviceName: deviceName
            )
            return id
        } catch {
            errorMessage = UserFacingError.sync(error)
            throw error
        }
    }

    private func observeEvents() {
        eventMonitor.start(engine: engine) { [weak self] event in
            switch event {
            case .failed(_, let message), .serviceFailed(let message):
                self?.errorMessage = message
            case .parked(_, let message):
                self?.errorMessage = message
            case .conflict:
                self?.errorMessage = UserFacingError.conflict
            case .authenticationRequired:
                self?.errorMessage = UserFacingError.authentication
            case .queued, .written, .rosterRefreshed, .syncActivity:
                break
            }
        }
    }

    private static func parseDistance(_ value: String) -> Double? {
        Double(value.trimmingCharacters(in: .whitespacesAndNewlines).replacing(",", with: "."))
    }

    private static func formatDistance(_ value: Double?) -> String {
        guard let value else { return "" }
        return value.formatted(.number.precision(.fractionLength(0...2)))
    }
}

public enum ChecklistError: LocalizedError, Sendable, Equatable {
    case unchangedDraft
    case guestOverwriteRequired

    public var errorDescription: String? {
        switch self {
        case .unchangedDraft: "Change the attendance before you confirm it."
        case .guestOverwriteRequired: "Review an overwrite to name, replace or remove a saved guest. Merge keeps the old guest allocation."
        }
    }
}
