import Foundation
import SwiftData
import Testing
@testable import FCTCAttendanceKit

/// The guest queue is serial: an unresolved head blocks every newer
/// operation, so a head that can never resolve must leave the queue.
@Suite("Guest operation queue", .serialized)
struct GuestOperationSyncTests {
    /// CA-12: entry points run the serial drain, so a newer rename waits
    /// behind an older operation whose delivery is still unknown.
    @Test("A new rename waits behind an unknown head")
    func newerWaitsBehindHead() async throws {
        let (container, engine, transport, guest) = try await guestQueue()
        let head = try insertHead(container, guest: guest, phase: .checking)
        await transport.append(.response(try receiptResponse(id: head.id, digest: head.digest, status: "pending")))
        let id = try await engine.renameGuest(guest, name: "Adam X")
        #expect(try await engine.guestOperation(id: id)?.phase == .queued)
        #expect(try await engine.guestOperation(id: head.id)?.phase == .checking)
        #expect(try await actions(transport).filter { $0 == "renameGuest" }.isEmpty)
    }
    @Test("A shared member add reports pending while an unknown head blocks it")
    func addMemberWaitsBehindHead() async throws {
        let (container, engine, transport, guest) = try await guestQueue()
        let head = try insertHead(container, guest: guest, phase: .checking)
        await transport.append(.response(try receiptResponse(id: head.id, digest: head.digest, status: "pending")))
        await #expect(throws: SheetAPIError.self) { try await engine.addMember(name: "New Runner") }
        #expect(try await actions(transport).filter { $0 == "addMember" }.isEmpty)
    }
    /// CA-11 and CA-27: a digest mismatch is certain, so the head is rejected
    /// and the rename behind it still drains.
    @Test("A receipt digest mismatch rejects the head and a later rename drains")
    func digestMismatchUnblocks() async throws {
        let (container, engine, transport, guest) = try await guestQueue()
        let head = try insertHead(container, guest: guest, phase: .checking)
        await transport.append(.response(try receiptResponse(id: head.id, digest: "another-request", status: "completed")))
        await transport.append(.response(json("{\"ok\":true}")))
        let id = try await engine.renameGuest(guest, name: "Adam X")
        #expect(try await engine.guestOperation(id: head.id)?.phase == .rejected)
        #expect(try await engine.guestOperation(id: id)?.phase == .completed)
    }
    @Test("A saved operation that cannot decode is rejected and a later rename drains")
    func corruptHeadUnblocks() async throws {
        let (container, engine, transport, guest) = try await guestQueue()
        let head = try insertHead(container, guest: guest, phase: .queued, corrupt: true)
        await transport.append(.response(json("{\"ok\":true}")))
        let id = try await engine.renameGuest(guest, name: "Adam X")
        #expect(try await engine.guestOperation(id: head.id)?.phase == .rejected)
        #expect(try await engine.guestOperation(id: id)?.phase == .completed)
    }
    /// A fence naming another operation proves this one was not dispatched,
    /// so it re-queues. Otherwise the receipt decides.
    @Test("A server fence re-queues only when it names another operation",
          arguments: ["pending_verification", "pending_operation"], FenceOwner.allCases)
    func guestFence(reason: String, owner: FenceOwner) async throws {
        let (container, engine, transport, guest) = try await guestQueue()
        let head = try insertHead(container, guest: guest, phase: .queued)
        await transport.append(.response(try fenceResponse(reason: reason, owner: owner, id: head.id)))
        await engine.drain()
        let snapshot = try #require(try await engine.guestOperation(id: head.id))
        #expect(snapshot.phase == (owner == .foreign ? .queued : .checking))
        #expect(snapshot.message == UserFacingError.checkingSavedChanges)
        #expect(try await actions(transport) == ["getState", "renameGuest"])
    }
}

/// A refreshed shared-guest engine with an empty transport, and its first guest.
private func guestQueue() async throws -> (ModelContainer, SyncEngine, StubTransport, SharedGuest) {
    let container = try guestContainer()
    let state = try JSONDecoder().decode(SheetState.self, from: guestStateResponse())
    let transport = StubTransport([.response(try stateData(state))])
    let engine = guestEngine(container, transport)
    _ = try await engine.refreshState()
    return (container, engine, transport, try #require(state.guests?.first))
}

/// Insert an older rename at the head of the queue, optionally with bytes
/// that no longer decode. Returns its id and digest.
private func insertHead(_ container: ModelContainer, guest: SharedGuest, phase: GuestOperationPhase,
                        corrupt: Bool = false) throws -> (id: UUID, digest: String) {
    let operation = try SharedGuestOperation(action: "renameGuest", fields: [
        "guestId": .string(guest.guestId), "displayName": .string("Older name"),
        "baseGuestRevision": .number(Double(guest.revision))
    ])
    let row = try PendingGuestOperation(operation: operation,
        endpointIdentity: configuredAPI.endpoint!.absoluteString, spreadsheetId: "illustrative-workbook")
    row.phase = phase; row.createdAt = .distantPast
    if corrupt { row.operationData = Data("not json".utf8) }
    let context = ModelContext(container)
    context.insert(row); try context.save()
    return (row.id, operation.digest)
}

/// The `action` of every request the transport received.
private func actions(_ transport: StubTransport) async throws -> [String] {
    try await transport.requests.compactMap { try JSONDecoder().decode(GuestJSON.self, from: $0)["action"]?.string }
}
