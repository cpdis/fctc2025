import Foundation
import SwiftData
import Testing
@testable import FCTCAttendanceKit

@Suite("Reviewed guest name corrections", .serialized)
struct GuestRenameReviewTests {
    @Test("A stale correction retains its proposed name and a reviewed retry gets a new receipt")
    func reviewedCorrection() async throws {
        let container = try guestContainer()
        var state = try JSONDecoder().decode(SheetState.self, from: guestStateResponse())
        let original = try #require(state.guests?.first)
        let conflict = SharedGuestConflict(reason: "stale_guest_revision", message: "Review this name again.")
        let conflictResponse = GuestJSON.object(["ok": .bool(true), "conflict": try .value(conflict)])
        let transport = StubTransport([.response(try stateData(state)), .response(try JSONEncoder().encode(conflictResponse))])
        let engine = guestEngine(container, transport)
        _ = try await engine.refreshState()
        let oldID = try await engine.renameGuest(original, name: "Adam X")
        let oldSnapshot = try #require(await engine.guestOperation(id: oldID))
        #expect(oldSnapshot.phase == .conflict)
        #expect(oldSnapshot.proposedName == "Adam X")
        let originalBytes = try #require(ModelContext(container).fetch(FetchDescriptor<PendingGuestOperation>()).first?.operationData)

        var reviewed = original
        reviewed.revision += 1; reviewed.displayName = "Adam"
        state.guests?[0] = reviewed
        await transport.append(.response(try stateData(state)))
        _ = try await engine.refreshState()
        var saved = reviewed
        saved.revision += 1; saved.displayName = "Adam X"
        await transport.append(.response(try renameResponse(saved)))
        let newID = try await engine.replaceGuestRename(id: oldID, guest: reviewed, name: " Adam X ")

        let rows = try ModelContext(container).fetch(FetchDescriptor<PendingGuestOperation>())
        #expect(newID != oldID)
        #expect(rows.count == 2)
        #expect(rows.first { $0.id == oldID }?.phase == .superseded)
        #expect(rows.first { $0.id == oldID }?.operationData == originalBytes)
        #expect(rows.first { $0.id == oldID }?.conflict == conflict)
        #expect(rows.first { $0.id == newID }?.phase == .completed)
        #expect(rows.filter { $0.phase != .completed && $0.phase != .superseded }.isEmpty)
        #expect(try await engine.sharedGuests().first?.displayName == "Adam X")
        let requests = try await transport.requests.map { try JSONDecoder().decode(GuestJSON.self, from: $0) }
        let renames = requests.filter { $0["action"]?.string == "renameGuest" }
        #expect(renames.count == 2)
        #expect(renames.last?["operationId"]?.string == newID.uuidString.lowercased())
        #expect(renames.last?["baseGuestRevision"]?.int == reviewed.revision)
        #expect(renames.last?["displayName"]?.string == "Adam X")
        #expect(!requests.contains { $0["action"]?.string == "submitAttendance" })
    }

    @Test("Keeping the saved name closes either terminal result without a server write")
    func keepSavedName() async throws {
        for phase in [GuestOperationPhase.conflict, .rejected] {
            let fixture = try await renameReviewFixture(phase: phase)
            let before = try #require(await fixture.engine.guestOperation(id: fixture.id))
            try await fixture.engine.discardGuestRename(id: fixture.id)
            let after = try #require(await fixture.engine.guestOperation(id: fixture.id))
            #expect(after.phase == .superseded)
            #expect(after.guestId == before.guestId)
            #expect(after.proposedName == before.proposedName)
            #expect(after.conflict == before.conflict)
            #expect(try await fixture.engine.sharedGuests().first?.displayName == fixture.guest.displayName)
            #expect(await fixture.transport.requestCount == 1)
            await #expect(throws: SheetAPIError.self) { try await fixture.engine.discardGuestRename(id: fixture.id) }
        }
    }

    @Test("An invalid or stale review cannot replace the original conflict")
    func staleReview() async throws {
        for defect in ["revision", "name", "identity", "status", "empty"] {
            let fixture = try await renameReviewFixture()
            var guest = fixture.guest
            var name = "Adam X"
            switch defect {
            case "revision": guest.revision -= 1
            case "name": guest.displayName = "Unreviewed name"
            case "identity": guest.guestId = UUID().uuidString.lowercased()
            case "status": guest.status = "promoted"
            default: name = " \n "
            }
            await #expect(throws: SheetAPIError.self) {
                try await fixture.engine.replaceGuestRename(id: fixture.id, guest: guest, name: name)
            }
            #expect(try await fixture.engine.guestOperation(id: fixture.id)?.phase == .conflict)
            #expect(try ModelContext(fixture.container).fetch(FetchDescriptor<PendingGuestOperation>()).count == 1)
            #expect(await fixture.transport.requestCount == 1)
        }
    }

    @Test("History revisions take precedence over the older run snapshot")
    func reviewedHistory() async throws {
        let fixture = try await renameReviewFixture()
        var fresh = fixture.guest
        fresh.revision += 1; fresh.displayName = "Adam"
        let history = GuestHistory(guest: fresh, guestRevision: "fresh-history", attendance: [])
        guard case .object(var response) = try GuestJSON.value(history) else { return }
        response["ok"] = .bool(true)
        await fixture.transport.append(.response(try JSONEncoder().encode(GuestJSON.object(response))))
        _ = try await fixture.engine.guestHistory(id: fresh.guestId)
        await #expect(throws: SheetAPIError.self) {
            try await fixture.engine.replaceGuestRename(id: fixture.id, guest: fixture.guest, name: "Adam X")
        }
        var saved = fresh
        saved.revision += 1; saved.displayName = "Adam X"
        await fixture.transport.append(.response(try renameResponse(saved)))
        let id = try await fixture.engine.replaceGuestRename(id: fixture.id, guest: fresh, name: saved.displayName)
        #expect(try await fixture.engine.guestOperation(id: id)?.phase == .completed)
        #expect(try ModelContext(fixture.container).fetch(FetchDescriptor<PendingGuestOperation>())
            .first { $0.id == id }?.operation?.request["baseGuestRevision"]?.int == fresh.revision)
    }

    @Test("Review cannot redirect an operation to another endpoint or workbook")
    func originalConnection() async throws {
        for defect in ["endpoint", "workbook"] {
            let fixture = try await renameReviewFixture(
                endpoint: defect == "endpoint" ? "https://example.com/other" : nil,
                workbook: defect == "workbook" ? "other-workbook" : nil)
            await #expect(throws: SheetAPIError.self) {
                try await fixture.engine.replaceGuestRename(id: fixture.id, guest: fixture.guest, name: "Adam X")
            }
            await #expect(throws: SheetAPIError.self) { try await fixture.engine.discardGuestRename(id: fixture.id) }
            #expect(try await fixture.engine.guestOperation(id: fixture.id)?.phase == .conflict)
            #expect(await fixture.transport.requestCount == 1)
        }
    }

    @Test("Queued, unknown, completed and superseded requests cannot be replaced or discarded")
    func terminalGuard() async throws {
        for phase in [GuestOperationPhase.queued, .checking, .completed, .superseded] {
            let fixture = try await renameReviewFixture(phase: phase)
            await #expect(throws: SheetAPIError.self) {
                try await fixture.engine.replaceGuestRename(id: fixture.id, guest: fixture.guest, name: "Adam X")
            }
            await #expect(throws: SheetAPIError.self) { try await fixture.engine.discardGuestRename(id: fixture.id) }
            #expect(try await fixture.engine.guestOperation(id: fixture.id)?.phase == phase)
            #expect(try ModelContext(fixture.container).fetch(FetchDescriptor<PendingGuestOperation>()).count == 1)
            #expect(await fixture.transport.requestCount == 1)
        }
    }

    @Test("Another unresolved correction for the same guest blocks a new request")
    func concurrentUnknownCorrection() async throws {
        for phase in [GuestOperationPhase.queued, .checking] {
            let fixture = try await renameReviewFixture()
            let context = ModelContext(fixture.container)
            let operation = try renameOperation(fixture.guest, name: "Another correction")
            let unresolved = try PendingGuestOperation(operation: operation,
                endpointIdentity: configuredAPI.endpoint!.absoluteString, spreadsheetId: "illustrative-workbook")
            unresolved.phase = phase
            context.insert(unresolved); try context.save()
            await #expect(throws: SheetAPIError.self) {
                try await fixture.engine.replaceGuestRename(id: fixture.id, guest: fixture.guest, name: "Adam X")
            }
            #expect(try await fixture.engine.guestOperation(id: fixture.id)?.phase == .conflict)
            #expect(try await fixture.engine.guestOperation(id: operation.id)?.phase == phase)
            #expect(await fixture.transport.requestCount == 1)
        }
    }

    @Test("A lost rename response remains unknown and cannot be dismissed or repeated")
    func lostResponse() async throws {
        let container = try guestContainer()
        let transport = StubTransport([.response(try guestStateResponse()), .failure(.ambiguousTimeout)])
        let engine = guestEngine(container, transport)
        _ = try await engine.refreshState()
        let guest = try #require(await engine.sharedGuests().first)
        let id = try await engine.renameGuest(guest, name: "Adam X")
        #expect(try await engine.guestOperation(id: id)?.phase == .checking)
        await #expect(throws: SheetAPIError.self) { try await engine.replaceGuestRename(id: id, guest: guest, name: "Adam X") }
        await #expect(throws: SheetAPIError.self) { try await engine.discardGuestRename(id: id) }
        #expect(await transport.requestCount == 2)
        #expect(try await engine.guestOperation(id: id)?.phase == .checking)
    }

    @Test("The serial drain checks an older unknown operation before sending a replacement")
    func earlierUnknownOperation() async throws {
        let fixture = try await renameReviewFixture()
        let context = ModelContext(fixture.container)
        var otherGuest = fixture.guest
        otherGuest.guestId = UUID().uuidString.lowercased()
        let operation = try renameOperation(otherGuest, name: "Other guest")
        let unresolved = try PendingGuestOperation(operation: operation,
            endpointIdentity: configuredAPI.endpoint!.absoluteString, spreadsheetId: "illustrative-workbook")
        unresolved.phase = .checking; unresolved.createdAt = .distantPast
        context.insert(unresolved); try context.save()
        let receipt = GuestOperationReceipt(operationId: operation.id.uuidString.lowercased(),
            requestDigest: operation.digest, status: "pending")
        await fixture.transport.append(.response(try JSONEncoder().encode(GuestJSON.object([
            "ok": .bool(true), "operation": try .value(receipt)
        ]))))

        let replacementID = try await fixture.engine.replaceGuestRename(id: fixture.id,
            guest: fixture.guest, name: "Adam X")
        #expect(try await fixture.engine.guestOperation(id: fixture.id)?.phase == .superseded)
        #expect(try await fixture.engine.guestOperation(id: replacementID)?.phase == .queued)
        #expect(try await fixture.engine.guestOperation(id: operation.id)?.phase == .checking)
        let requests = try await fixture.transport.requests.map { try JSONDecoder().decode(GuestJSON.self, from: $0) }
        #expect(requests.count == 2)
        #expect(requests.last?["action"]?.string == "getOperationStatus")
        #expect(!requests.contains { $0["action"]?.string == "renameGuest" })
    }

    @Test("A review closes only the selected correction and retains other terminal evidence")
    func explicitSelectionOnly() async throws {
        let fixture = try await renameReviewFixture()
        let context = ModelContext(fixture.container)
        let other = try PendingGuestOperation(operation: renameOperation(fixture.guest, name: "Older correction"),
            endpointIdentity: configuredAPI.endpoint!.absoluteString, spreadsheetId: "illustrative-workbook")
        other.phase = .rejected
        context.insert(other); try context.save()
        var saved = fixture.guest
        saved.revision += 1; saved.displayName = "Adam X"
        await fixture.transport.append(.response(try renameResponse(saved)))
        _ = try await fixture.engine.replaceGuestRename(id: fixture.id, guest: fixture.guest, name: saved.displayName)
        #expect(try await fixture.engine.guestOperation(id: other.id)?.phase == .rejected)
        #expect(try await fixture.engine.guestOperation(id: fixture.id)?.phase == .superseded)
    }
}

private struct RenameReviewFixture {
    var container: ModelContainer
    var engine: SyncEngine
    var transport: StubTransport
    var id: UUID
    var guest: SharedGuest
}

private func renameReviewFixture(phase: GuestOperationPhase = .conflict,
                                 endpoint: String? = nil, workbook: String? = nil) async throws -> RenameReviewFixture {
    let container = try guestContainer()
    var state = try JSONDecoder().decode(SheetState.self, from: guestStateResponse())
    var guest = try #require(state.guests?.first)
    guest.revision += 1; state.guests?[0] = guest
    let context = ModelContext(container)
    let operation = try renameOperation(guest, name: "Adam X")
    let row = try PendingGuestOperation(operation: operation,
        endpointIdentity: endpoint ?? configuredAPI.endpoint!.absoluteString,
        spreadsheetId: workbook ?? state.spreadsheetId!)
    row.phase = phase
    if phase == .conflict {
        row.conflictData = try JSONEncoder().encode(SharedGuestConflict(
            reason: "stale_guest_revision", message: "Review this name again."))
    }
    context.insert(row); try context.save()
    let transport = StubTransport([.response(try stateData(state))])
    let engine = guestEngine(container, transport)
    _ = try await engine.refreshState()
    return RenameReviewFixture(container: container, engine: engine, transport: transport, id: row.id, guest: guest)
}

private func renameOperation(_ guest: SharedGuest, name: String) throws -> SharedGuestOperation {
    try SharedGuestOperation(action: "renameGuest", fields: [
        "guestId": .string(guest.guestId), "displayName": .string(name),
        "baseGuestRevision": .number(Double(guest.revision))
    ])
}

private func renameResponse(_ guest: SharedGuest) throws -> Data {
    try JSONEncoder().encode(GuestJSON.object(["ok": .bool(true), "guest": try .value(guest)]))
}
