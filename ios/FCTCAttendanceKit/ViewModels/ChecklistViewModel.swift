//
//  ChecklistViewModel.swift
//  FCTCAttendanceKit
//

import Foundation
import Observation

@MainActor
@Observable
public final class ChecklistViewModel {
    public let run: RunSnapshot
    public private(set) var roster: [String]
    public var draft: AttendanceDraft
    public var actualKmText: String {
        didSet { draft.actualKm = Self.parseDistance(actualKmText) }
    }
    public var quickAddName = ""
    public private(set) var isSubmitting = false
    public private(set) var isAddingPerson = false
    public private(set) var errorMessage: String?
    public private(set) var guestHistory: [Guest]

    @ObservationIgnored private var engine: any SyncEngineClient
    @ObservationIgnored private let deviceName: String?
    @ObservationIgnored private let eventMonitor = SyncEventMonitor()

    public init(
        run: RunSnapshot,
        roster: [String],
        guestHistory: [String] = [],
        draft suppliedDraft: AttendanceDraft? = nil,
        engine: any SyncEngineClient,
        deviceName: String? = nil
    ) {
        self.run = run
        self.roster = roster.sorted(by: Member.sheetOrder)
        self.guestHistory = Self.uniqueGuests(named: guestHistory)
        self.engine = engine
        self.deviceName = deviceName

        var draft = suppliedDraft ?? AttendanceDraft(
            rowIndex: run.rowIndex,
            expectedDate: run.date,
            expectedRun: run.run,
            checks: Dictionary(uniqueKeysWithValues: run.attendees.map { ($0, .manual) }),
            actualKm: run.actualKm ?? run.approxKm,
            plusOnesOverride: run.plusOnes,
            baseRevision: run.cachedRevision
        )
        if draft.actualKm == nil { draft.actualKm = run.actualKm ?? run.approxKm }
        self.draft = draft
        self.actualKmText = Self.formatDistance(draft.actualKm)
        observeEvents()
    }

    public var canConfirm: Bool {
        !isSubmitting && draftDiffersFromSheet
    }

    public var draftDiffersFromSheet: Bool {
        Set(draft.attendees) != Set(run.attendees)
            || draft.plusOnes != run.plusOnes
            || (draft.actualKm ?? run.actualKm) != run.actualKm
    }

    public var requiresRecordedChoice: Bool { run.hasRecordedAttendance }

    public var matchingGuests: [Guest] {
        let query = Self.canonical(quickAddName)
        guard !query.isEmpty else { return [] }
        let rosterKeys = Set(roster.map(Self.canonical))
        var seen: Set<String> = []
        return (draft.guests + guestHistory).filter { guest in
            let key = Self.canonical(guest.name)
            return key.contains(query)
                && !rosterKeys.contains(key)
                && seen.insert(key).inserted
        }
    }

    public func updateRoster(_ names: [String]) {
        roster = names.sorted(by: Member.sheetOrder)
    }

    public func updateGuestHistory(_ names: [String]) {
        guestHistory = Self.uniqueGuests(named: names)
    }

    public func toggleMember(_ name: String) {
        draft.toggle(name)
    }

    public func uncheckMember(_ name: String) {
        draft.uncheck(name)
    }

    public func isSuggested(_ name: String) -> Bool {
        draft.unmatched.contains { unmatched in
            unmatched.suggestions.contains { Self.canonical($0) == Self.canonical(name) }
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
        quickAddName = ""
        errorMessage = nil

        if let existing = roster.first(where: { Self.canonical($0) == Self.canonical(clean) }) {
            promoteGuest(named: clean)
            draft.check(existing)
            return
        }

        // Mirror SyncEngine's optimistic insert in value state. SwiftData catches up
        // through @Query while the network reconciliation is still suspended.
        roster.append(clean)
        roster.sort(by: Member.sheetOrder)
        let oldGuests = draft.guests
        let oldPlusOnesOverride = draft.plusOnesOverride
        promoteGuest(named: clean)
        draft.check(clean)
        isAddingPerson = true
        defer { isAddingPerson = false }
        do {
            _ = try await engine.addMember(name: clean)
        } catch {
            roster.removeAll { Self.canonical($0) == Self.canonical(clean) }
            draft.uncheck(clean)
            draft.guests = oldGuests
            draft.plusOnesOverride = oldPlusOnesOverride
            quickAddName = clean
            errorMessage = error.localizedDescription
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
            errorMessage = error.localizedDescription
            throw error
        }
    }

    private func promoteGuest(named name: String) {
        let key = Self.canonical(name)
        let oldCount = draft.guests.count
        draft.guests.removeAll { Self.canonical($0.name) == key }
        if draft.guests.count != oldCount { draft.plusOnesOverride = nil }
    }

    private func observeEvents() {
        eventMonitor.start(engine: engine) { [weak self] event in
            switch event {
            case .failed(_, let message), .parked(_, let message),
                 .conflict(_, _, let message, _):
                self?.errorMessage = message
            case .queued, .written, .rosterRefreshed:
                break
            }
        }
    }

    private static func canonical(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private static func uniqueGuests(named names: [String]) -> [Guest] {
        var seen: Set<String> = []
        return names.compactMap { name in
            let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = canonical(clean)
            guard !key.isEmpty, seen.insert(key).inserted else { return nil }
            return Guest(name: clean)
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

    public var errorDescription: String? {
        "Change the attendance before you confirm it."
    }
}
