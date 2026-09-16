import Foundation
import SwiftData
import Testing
@testable import FCTCAttendanceKit

@Suite("Undelivered shared operations", .serialized)
struct UndeliveredOperationTests {
    @Test("A refused first connection retains the request and saves once after restart", arguments: [false, true])
    func offlineRestart(withGuest: Bool) async throws {
        let url = storeURL()
        let container = try guestContainer(url)
        let transport = try RecoveryTransport(failure: .beforeDelivery)
        let engine = guestEngine(container, transport)
        _ = try await engine.refreshState()
        var draft = guestDraft()
        if withGuest {
            draft.guests = [try await engine.createGuest(name: "New guest")]
            // A later structural operation must stay behind the unsent first one.
            _ = try await engine.createGuest(name: "Later guest")
        }
        let attendanceID = try await engine.enqueue(draft: draft, mode: .merge, deviceName: nil)
        await engine.drain()
        let context = ModelContext(container)
        let attendance = try #require(context.fetch(FetchDescriptor<PendingSubmission>()).first)
        let failedRequest = try #require(await transport.mutations.first)
        let savedData: Data
        if withGuest {
            let guests = try context.fetch(FetchDescriptor<PendingGuestOperation>(sortBy: [SortDescriptor(\.createdAt)]))
            let first = try #require(guests.first)
            #expect(first.phase == .queued)
            #expect(await transport.mutations.count == 1)
            #expect(attendance.sharedOperationData == nil)
            savedData = first.operationData
        } else {
            #expect(attendance.status == .queued)
            #expect(attendance.verificationPending == false)
            savedData = try #require(attendance.sharedOperationData)
        }
        #expect(await transport.acceptedMutations == 0)

        // Reopen the actual disk store, so retry depends on persisted delivery state.
        let reopened = try guestContainer(url)
        let online = try RecoveryTransport()
        let restarted = guestEngine(reopened, online)
        await restarted.drain()
        await restarted.drain()
        let requests = await online.mutations
        let retried = try #require(requests.first)
        #expect(retried == failedRequest)
        #expect(retried["operationId"] == failedRequest["operationId"])
        #expect(retried["requestDigest"] == failedRequest["requestDigest"])
        #expect(await online.receiptChecks == 0)
        #expect(await online.acceptedMutations == (withGuest ? 3 : 1))
        let after = ModelContext(reopened)
        let saved = try #require(after.fetch(FetchDescriptor<PendingSubmission>()).first)
        #expect(saved.id == attendanceID)
        #expect(saved.outcome == .committed)
        if withGuest {
            let guests = try after.fetch(FetchDescriptor<PendingGuestOperation>(sortBy: [SortDescriptor(\.createdAt)]))
            #expect(guests.allSatisfy { $0.phase == .completed })
            #expect(guests.first?.operationData == savedData)
            #expect(requests.map { $0["action"]?.string } == ["createGuest", "createGuest", "submitAttendance"])
            #expect(requests.last?["namedGuestIds"] == .array([try #require(retried["guestId"])]))
        } else {
            #expect(saved.sharedOperationData == savedData)
        }
    }

    @Test("Missing receipts never replay an unknown delivery after restart", arguments: [false, true])
    func unknownRestart(withGuest: Bool) async throws {
        let url = storeURL()
        let container = try guestContainer(url)
        let transport = try RecoveryTransport(failure: .unknown)
        let engine = guestEngine(container, transport)
        _ = try await engine.refreshState()
        var draft = guestDraft()
        if withGuest { draft.guests = [try await engine.createGuest(name: "New guest")] }
        _ = try await engine.enqueue(draft: draft, mode: .merge, deviceName: nil)
        await engine.drain()
        let reopened = try guestContainer(url)
        let online = try RecoveryTransport()
        let restarted = guestEngine(reopened, online)
        await restarted.drain()
        await restarted.drain()
        #expect(await online.receiptChecks == 2)
        #expect(await online.mutations.isEmpty)
        let context = ModelContext(reopened)
        if withGuest {
            #expect(try context.fetch(FetchDescriptor<PendingGuestOperation>()).first?.phase == .checking)
            #expect(try context.fetch(FetchDescriptor<PendingSubmission>()).first?.sharedOperationData == nil)
        } else {
            #expect(try context.fetch(FetchDescriptor<PendingSubmission>()).first?.verificationPending == true)
        }
    }

    @Test("Rejected and not-applied receipts park both queues without replay",
          arguments: [false, true], ["rejected", "not_applied"])
    func terminalReceipt(withGuest: Bool, status: String) async throws {
        let container = try guestContainer()
        let transport = try RecoveryTransport(failure: .unknown, receiptStatus: status)
        let engine = guestEngine(container, transport)
        _ = try await engine.refreshState()
        if withGuest { _ = try await engine.createGuest(name: "New guest") }
        else { _ = try await engine.enqueue(draft: guestDraft(), mode: .merge, deviceName: nil) }
        await engine.drain()
        await engine.drain()
        await engine.drain()
        #expect(await transport.mutations.count == 1)
        #expect(await transport.receiptChecks == 1)
        let context = ModelContext(container)
        if withGuest {
            #expect(try context.fetch(FetchDescriptor<PendingGuestOperation>()).first?.phase == .rejected)
        } else {
            #expect(try context.fetch(FetchDescriptor<PendingSubmission>()).first?.status == .conflict)
        }
    }

    private func storeURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("fctc-delivery-\(UUID()).sqlite")
    }
}

/// Uses the real URLSession transport for an initial connection refusal, then an
/// action-aware server for reconnect. Missing receipts remain absent forever.
private actor RecoveryTransport: HTTPTransport {
    enum Failure { case beforeDelivery, unknown }
    private var failure: Failure?
    private let receiptStatus: String?
    private let state: Data
    private(set) var mutations: [GuestJSON] = []
    private(set) var acceptedMutations = 0
    private(set) var receiptChecks = 0

    init(failure: Failure? = nil, receiptStatus: String? = nil) throws {
        self.failure = failure
        self.receiptStatus = receiptStatus
        state = try guestStateResponse()
    }

    func post(_ body: Data) async throws -> Data {
        let request = try JSONDecoder().decode(GuestJSON.self, from: body)
        if request["action"]?.string == "getState" { return state }
        if request["action"]?.string == "getOperationStatus" {
            receiptChecks += 1
            guard let receiptStatus, let original = mutations.first else {
                return json("{\"ok\":true,\"operation\":null}")
            }
            return try JSONEncoder().encode(GuestJSON.object(["ok": .bool(true), "operation": .object([
                "operationId": original["operationId"]!, "requestDigest": original["requestDigest"]!,
                "status": .string(receiptStatus), "response": .null
            ])]))
        }
        mutations.append(request)
        if let failure {
            self.failure = nil
            switch failure {
            case .beforeDelivery:
                let configuration = URLSessionConfiguration.ephemeral
                configuration.connectionProxyDictionary = [:]
                configuration.timeoutIntervalForRequest = 3
                let session = URLSession(configuration: configuration)
                defer { session.invalidateAndCancel() }
                let transport = URLSessionTransport(endpoint: URL(string: "http://127.0.0.1:9/not-a-service")!, session: session)
                return try await transport.post(body)
            case .unknown:
                throw URLError(.timedOut)
            }
        }
        acceptedMutations += 1
        if request["action"]?.string == "createGuest" {
            return try JSONEncoder().encode(GuestJSON.object(["ok": .bool(true), "guest": .object([
                "guestId": request["guestId"]!, "displayName": request["displayName"]!,
                "status": .string("active"), "revision": .number(1)
            ])]))
        }
        return json("{\"ok\":true,\"written\":1,\"sheetRevision\":\"after\"}")
    }
}
