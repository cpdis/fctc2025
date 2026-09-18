import Foundation
import SwiftData
import Testing
@testable import FCTCAttendanceKit

@Suite("Guest response ordering", .serialized)
struct GuestCacheOrderingTests {
    @Test("A delayed read cannot undo a confirmed name", arguments: ["getState", "getGuestHistory"])
    func delayedRead(action: String) async throws {
        let container = try guestContainer()
        let initial = try JSONDecoder().decode(SheetState.self, from: guestStateResponse())
        let original = try #require(initial.guests?.first)
        var renamed = original
        renamed.displayName = "Adam X"; renamed.revision += 1
        let history = GuestHistory(guest: original, guestRevision: "old", attendance: [])
        let read = action == "getState" ? try stateData(initial) : try response(history)
        let transport = HeldGuestTransport([try stateData(initial), read, try responseGuest(renamed)])
        let engine = guestEngine(container, transport)
        _ = try await engine.refreshState()
        await transport.holdNext()
        let reading = Task { () throws -> SharedGuest? in
            if action == "getState" { _ = try await engine.refreshState(); return nil }
            return try await engine.guestHistory(id: original.guestId).guest
        }
        await transport.waitUntilHeld()
        let id = try await engine.renameGuest(original, name: renamed.displayName)
        #expect(try await engine.guestOperation(id: id)?.phase == .completed)
        await transport.release()
        let returnedGuest = try await reading.value
        #expect(try await engine.sharedGuests().first == renamed)
        if action == "getGuestHistory" { #expect(returnedGuest == renamed) }
    }

    @Test("An older mutation receipt cannot replace a newer shared identity")
    func delayedMutation() async throws {
        let container = try guestContainer()
        var state = try JSONDecoder().decode(SheetState.self, from: guestStateResponse())
        let original = try #require(state.guests?.first)
        var renamed = original
        renamed.displayName = "Adam X"; renamed.revision += 1
        var newer = renamed
        newer.displayName = "Adam Y"; newer.revision += 1; newer.confirmedRuns = 12
        let initial = try stateData(state)
        state.guests?[0] = newer
        let transport = HeldGuestTransport([initial, try responseGuest(renamed), try stateData(state)])
        let engine = guestEngine(container, transport)
        _ = try await engine.refreshState()
        await transport.holdNext()
        let saving = Task { try await engine.renameGuest(original, name: renamed.displayName) }
        await transport.waitUntilHeld()
        _ = try await engine.refreshState()
        await transport.release()
        let id = try await saving.value
        #expect(try await engine.guestOperation(id: id)?.phase == .completed)
        #expect(try await engine.sharedGuests().first == newer)
    }

    @Test("Attendance totals can refresh without an identity revision change")
    func equalRevisionTotals() async throws {
        let container = try guestContainer()
        var state = try JSONDecoder().decode(SheetState.self, from: guestStateResponse())
        let first = try stateData(state)
        state.guests?[0].confirmedRuns = 12
        let transport = HeldGuestTransport([first, try stateData(state)])
        let engine = guestEngine(container, transport)
        _ = try await engine.refreshState()
        _ = try await engine.refreshState()
        #expect(try await engine.sharedGuests().first?.confirmedRuns == 12)
    }

    private func response<T: Encodable>(_ value: T) throws -> Data {
        guard case .object(var fields) = try GuestJSON.value(value) else { throw SheetAPIError.notImplemented }
        fields["ok"] = .bool(true)
        return try JSONEncoder().encode(GuestJSON.object(fields))
    }
    private func responseGuest(_ guest: SharedGuest) throws -> Data {
        try JSONEncoder().encode(GuestJSON.object(["ok": .bool(true), "guest": try .value(guest)]))
    }
}

/// Hold one already-started response while another request completes. No timing sleeps.
private actor HeldGuestTransport: HTTPTransport {
    private var responses: [Data]
    private var shouldHold = false
    private var held: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?
    init(_ responses: [Data]) { self.responses = responses }
    func holdNext() { shouldHold = true }
    func post(_ body: Data) async throws -> Data {
        guard !responses.isEmpty else { throw SheetAPIError.notImplemented }
        let response = responses.removeFirst()
        if shouldHold {
            shouldHold = false
            await withCheckedContinuation { continuation in
                held = continuation; started?.resume(); started = nil
            }
        }
        return response
    }
    func waitUntilHeld() async {
        guard held == nil else { return }
        await withCheckedContinuation { started = $0 }
    }
    func release() { held?.resume(); held = nil }
}
