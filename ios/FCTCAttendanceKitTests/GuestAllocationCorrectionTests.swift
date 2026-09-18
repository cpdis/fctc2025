import Foundation
import SwiftData
import Testing
@testable import FCTCAttendanceKit

@Suite("Guest allocation correction review", .serialized)
@MainActor
struct GuestAllocationCorrectionTests {
    private let rene = "11111111-1111-4111-8111-111111111111"
    private let wes = "22222222-2222-4222-8222-222222222222"
    private let ann = "33333333-3333-4333-8333-333333333333"
    private let identity = RunIdentity(spreadsheetId: "review-book", seasonSheetId: 26,
        runId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")

    @Test("A promoted offline merge keeps concurrent members, guests and unnamed slots")
    func concurrentMerge() throws {
        let state = promotedState()
        let review = try PromotedGuestReview(submission: snapshot(mode: .merge), state: state, endpointIdentity: configuredAPI.endpoint?.absoluteString)
        #expect(Set(review.draft.attendees) == ["Col", "Rene Member", "Toby"])
        #expect(Set(review.draft.namedGuestIds) == [wes, ann])
        #expect(review.draft.unnamedGuests == 2)
        #expect(review.draft.attendees.count + review.draft.plusOnes == 7)
        #expect(review.guestNamesBefore == ["Wes"])
        #expect(Set(review.membersBefore) == ["Rene Member", "Toby"])
        #expect(review.removedMembers.isEmpty)
        #expect(review.removedGuests.isEmpty)
        #expect(review.actualKmBefore == 8)
        #expect(review.draft.actualKm == 7.2)
    }

    @Test("An original overwrite reviews the actual refreshed guests before removing them")
    func overwriteBefore() throws {
        let review = try PromotedGuestReview(submission: snapshot(mode: .overwrite), state: promotedState(), endpointIdentity: configuredAPI.endpoint?.absoluteString)
        #expect(review.guestNamesBefore == ["Wes"])
        #expect(review.guestNamesAfter == ["Ann"])
        #expect(Set(review.draft.attendees) == ["Col", "Rene Member"])
        #expect(review.draft.unnamedGuests == 1)
        #expect(review.peopleBefore == 5)
        #expect(review.unnamedBefore == 2)
        #expect(review.removedMembers == ["Toby"])
        #expect(review.removedGuests == ["Wes"])
    }

    @Test("The conversion service rejects a merge review that drops concurrent attendance")
    func serviceRejectsLoss() async throws {
        let container = try guestContainer(), state = promotedState()
        let engine = guestEngine(container, StubTransport([.response(try stateData(state))]))
        _ = try await engine.refreshState()
        let context = ModelContext(container)
        let old = PendingSubmission.from(draft: queuedDraft(), mode: .merge, deviceName: nil, createdAt: .now)
        old.status = .conflict; old.conflictReason = "guest_promoted"
        context.insert(old); try context.save()
        let saved = try #require(try await engine.pendingSubmission(id: old.id))
        var review = try PromotedGuestReview(submission: saved, state: state, endpointIdentity: configuredAPI.endpoint?.absoluteString).draft
        review.checks.removeValue(forKey: "Toby")
        review.guests.removeAll { $0.id.uuidString.lowercased() == wes }
        review.unnamedGuests = 1
        await #expect(throws: SheetAPIError.self) { try await engine.replacePromotedGuestSubmission(id: old.id, reviewedDraft: review) }
        #expect(try await engine.pendingSubmission(id: old.id)?.status == .conflict)
        #expect(try ModelContext(container).fetch(FetchDescriptor<PendingSubmission>()).count == 1)
    }

    @Test("Saving the reviewed merge retains all concurrent attendance")
    func reviewedMergeSave() async throws {
        let container = try guestContainer(), state = promotedState()
        let engine = guestEngine(container, StubTransport([.response(try stateData(state))]))
        _ = try await engine.refreshState()
        let context = ModelContext(container)
        let old = PendingSubmission.from(draft: queuedDraft(), mode: .merge, deviceName: nil, createdAt: .now)
        old.status = .conflict; old.conflictReason = "guest_promoted"
        context.insert(old); try context.save()
        let saved = try #require(try await engine.pendingSubmission(id: old.id))
        let review = try PromotedGuestReview(submission: saved, state: state, endpointIdentity: configuredAPI.endpoint?.absoluteString)
        let id = try await engine.replacePromotedGuestSubmission(id: old.id, reviewedDraft: review.draft)
        let replacement = try #require(try await engine.pendingSubmission(id: id))
        #expect(Set(replacement.attendees) == ["Col", "Rene Member", "Toby"])
        #expect(Set(replacement.namedGuestIds ?? []) == [wes, ann])
        #expect(replacement.unnamedGuests == 2)
        #expect(replacement.mode == .overwrite)
        #expect(try await engine.pendingSubmission(id: old.id)?.outcome == .superseded)
    }

    @Test("Naming a saved unnamed slot saves an overwrite with unchanged headcount")
    func unnamedAssignmentSave() async throws {
        let container = try guestContainer()
        var before = promotedState()
        before.guests = [SharedGuest(guestId: rene, displayName: "Rene")]
        before.runs[0].attendees = ["Col"]
        before.runs[0].namedGuestIds = []; before.runs[0].unnamedGuests = 1; before.runs[0].plusOnes = 1
        var after = before
        after.runs[0].namedGuestIds = [rene]; after.runs[0].unnamedGuests = 0
        after.sheetRevision = "saved"
        let transport = StubTransport([.response(try stateData(before)), .response(json("{\"ok\":true,\"written\":1}")), .response(try stateData(after))])
        let engine = guestEngine(container, transport)
        _ = try await engine.refreshState()
        let model = ChecklistViewModel(run: RunSnapshot(record: before.runs[0], state: before, endpointIdentity: configuredAPI.endpoint?.absoluteString), roster: before.roster.map(\.name), engine: engine)
        model.updateSharedGuests(before.guests!)
        model.selectGuest(before.guests![0], namingUnnamed: true)
        #expect(model.requiresGuestOverwrite)
        await #expect(throws: ChecklistError.self) { try await model.confirm(mode: .merge) }
        #expect(try ModelContext(container).fetch(FetchDescriptor<PendingSubmission>()).isEmpty)
        let id = try await model.confirm(mode: .overwrite)
        await engine.drain()
        let saved = try #require(try await engine.pendingSubmission(id: id))
        #expect(saved.outcome == .committed)
        #expect(saved.mode == .overwrite)
        #expect(saved.namedGuestIds == [rene])
        #expect(saved.unnamedGuests == 0)
        #expect(saved.attendees.count + (saved.plusOnes ?? 0) == 2)
        let requests = try await transport.requests.map { try JSONDecoder().decode(GuestJSON.self, from: $0) }
        let write = try #require(requests.first { $0["action"]?.string == "submitAttendance" })
        #expect(write["mode"]?.string == "overwrite")
        #expect(write["unnamedGuests"]?.int == 0)
    }

    @Test("Replacing or removing saved guests cannot use additive merge")
    func correctionRejectsMerge() async throws {
        let state = promotedState()
        for replacement in [true, false] {
            let model = ChecklistViewModel(run: RunSnapshot(record: state.runs[0], state: state, endpointIdentity: configuredAPI.endpoint?.absoluteString), roster: state.roster.map(\.name), engine: UnimplementedSyncEngine())
            model.updateSharedGuests(state.guests!)
            if replacement { model.selectGuest(state.guests![2], replacing: UUID(uuidString: wes)!) }
            else { model.removeGuest(id: UUID(uuidString: wes)!) }
            #expect(model.requiresGuestOverwrite)
            await #expect(throws: ChecklistError.self) { try await model.confirm(mode: .merge) }
        }
    }

    @Test("Guest review describes the actual additive merge allocation")
    func modeSpecificDiff() {
        let state = promotedState()
        let model = ChecklistViewModel(run: RunSnapshot(record: state.runs[0], state: state, endpointIdentity: configuredAPI.endpoint?.absoluteString), roster: state.roster.map(\.name), engine: UnimplementedSyncEngine())
        model.updateSharedGuests(state.guests!)
        model.selectGuest(state.guests![2])
        #expect(!model.requiresGuestOverwrite)
        #expect(model.guestDiff(for: .merge).added == ["Ann"])
        model.removeGuest(id: UUID(uuidString: wes)!)
        model.draft.unnamedGuests = 0
        #expect(model.guestDiff(for: .merge).removed.isEmpty)
        #expect(model.guestDiff(for: .merge).unnamedAfter == 2)
        #expect(model.guestDiff(for: .overwrite).removed == ["Wes"])
        #expect(model.guestDiff(for: .overwrite).unnamedAfter == 0)
    }

    private func promotedState() -> SheetState {
        SheetState(roster: [RosterEntry(name: "Col", colIndex: 6), RosterEntry(name: "Rene Member", colIndex: 7), RosterEntry(name: "Toby", colIndex: 8)],
            runs: [RunRecord(rowIndex: 42, date: "Fri, 11-Sep", meet: "Beach", run: "Sand", actualKm: 8,
                attendees: ["Toby", "Rene Member"], plusOnes: 3, identity: identity, namedGuestIds: [wes], unnamedGuests: 2, seasonYear: 2026)],
            seasonYear: 2026, sheetRevision: "fresh", apiVersion: 2, capabilities: GuestCapabilities(), spreadsheetId: "review-book", seasonSheetId: 26,
            guests: [SharedGuest(guestId: rene, displayName: "Rene", status: "promoted", memberName: "Rene Member"),
                     SharedGuest(guestId: wes, displayName: "Wes"), SharedGuest(guestId: ann, displayName: "Ann")])
    }
    private func queuedDraft() -> AttendanceDraft {
        AttendanceDraft(rowIndex: 42, expectedDate: "Fri, 11-Sep", expectedRun: "Sand", checks: ["Col": .manual],
            guests: [Guest(id: UUID(uuidString: rene)!, name: "Rene"), Guest(id: UUID(uuidString: ann)!, name: "Ann")], actualKm: 7.2,
            baseRevision: "old", runIdentity: identity, endpointIdentity: configuredAPI.endpoint?.absoluteString, unnamedGuests: 1)
    }
    private func snapshot(mode: SubmissionMode) -> PendingSubmissionSnapshot {
        PendingSubmissionSnapshot(id: UUID(), rowIndex: 42, expectedDate: "Fri, 11-Sep", expectedRun: "Sand", attendees: ["Col"],
            guestNames: ["Rene", "Ann"], plusOnes: 3, actualKm: 7.2, mode: mode, status: .conflict, createdAt: .now,
            runIdentity: identity, namedGuestIds: [rene, ann], unnamedGuests: 1)
    }
}
