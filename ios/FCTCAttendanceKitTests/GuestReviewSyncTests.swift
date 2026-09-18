import Foundation
import SwiftData
import Testing
@testable import FCTCAttendanceKit

@Suite("Reviewed guest submission sync", .serialized)
struct GuestReviewSyncTests {
    @Test("Save-before-promotion distinguishes queued and committed receipts")
    func receiptSnapshot() async throws {
        let container = try guestContainer()
        let transport = StubTransport([.response(try guestStateResponse()), .response(json("{\"ok\":true,\"written\":1}")), .response(try guestStateResponse())])
        let engine = guestEngine(container, transport)
        _ = try await engine.refreshState()
        let id = try await engine.enqueue(draft: guestDraft(), mode: .merge, deviceName: nil)
        #expect(try await engine.pendingSubmission(id: id)?.outcome == nil)
        await engine.drain()
        #expect(try await engine.pendingSubmission(id: id)?.outcome == .committed)
    }
    @Test("Reviewed conversion supersedes evidence and queues one replacement")
    func reviewedConversion() async throws {
        let (container, engine, oldID, draft) = try await promotedConflict()
        let newID = try await engine.replacePromotedGuestSubmission(id: oldID, reviewedDraft: draft)
        let rows = try ModelContext(container).fetch(FetchDescriptor<PendingSubmission>())
        let original = try #require(rows.first { $0.id == oldID }), replacement = try #require(rows.first { $0.id == newID })
        #expect(rows.count == 2)
        #expect(original.outcome == .superseded)
        #expect(original.guestNames == ["Rene"])
        #expect(replacement.status == .queued)
        #expect(replacement.attendees.sorted() == ["Col", "Rene", "Toby"])
        #expect(replacement.namedGuestIds == [])
        #expect(replacement.unnamedGuests == 0)
        #expect(replacement.mode == .overwrite)
        await #expect(throws: SyncEngineError.self) { try await engine.replacePromotedGuestSubmission(id: oldID, reviewedDraft: draft) }
    }
    @Test("Invalid review cannot close the original conflict")
    func invalidReview() async throws {
        for defect in ["revision", "member", "endpoint", "run"] {
            let (container, engine, oldID, initial) = try await promotedConflict()
            var draft = initial
            switch defect {
            case "revision": draft.baseRevision = "stale"
            case "member": draft.checks.removeValue(forKey: "Rene")
            case "endpoint": draft.endpointIdentity = "https://other.invalid"
            default: draft.runIdentity?.seasonSheetId = 25
            }
            await #expect(throws: SheetAPIError.self) { try await engine.replacePromotedGuestSubmission(id: oldID, reviewedDraft: draft) }
            let rows = try ModelContext(container).fetch(FetchDescriptor<PendingSubmission>())
            #expect(rows.count == 1)
            #expect(rows.first?.status == .conflict)
            #expect(rows.first?.outcome == nil)
        }
    }
}
private func promotedConflict() async throws -> (ModelContainer, SyncEngine, UUID, AttendanceDraft) {
    let container = try guestContainer()
    var state = try JSONDecoder().decode(SheetState.self, from: guestStateResponse())
    state.roster.append(RosterEntry(name: "Rene", colIndex: 8))
    state.guests?[0].status = "promoted"; state.guests?[0].memberName = "Rene"
    state.runs[0].attendees.append("Rene")
    state.runs[0].namedGuestIds = []; state.runs[0].plusOnes = 0
    state.sheetRevision = "reviewed-promotion"
    let engine = guestEngine(container, StubTransport([.response(try stateData(state))]))
    _ = try await engine.refreshState()
    let context = ModelContext(container)
    let old = PendingSubmission.from(draft: guestDraft(), mode: .merge, deviceName: nil, createdAt: .now)
    old.status = .conflict; old.conflictReason = "guest_promoted"
    context.insert(old); try context.save()
    let snapshot = try #require(try await engine.pendingSubmission(id: old.id))
    let draft = try PromotedGuestReview(submission: snapshot, state: state, endpointIdentity: configuredAPI.endpoint?.absoluteString).draft
    return (container, engine, old.id, draft)
}
