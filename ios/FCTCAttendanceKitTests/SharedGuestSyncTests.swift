import Foundation
import SwiftData
import Testing
@testable import FCTCAttendanceKit

@Suite("Shared guest sync")
struct SharedGuestSyncTests {
    @Test("Two clients reconstruct the same confirmed guest history from the server")
    func secondDevice() async throws {
        let first = try guestContainer(), second = try guestContainer()
        let state = try guestStateResponse()
        let engineA = guestEngine(first, StubTransport([.response(state)]))
        let engineB = guestEngine(second, StubTransport([.response(state)]))
        _ = try await engineA.refreshState(); _ = try await engineB.refreshState()
        #expect(try await engineA.sharedGuests() == engineB.sharedGuests())
        #expect(try await engineB.sharedGuests().first?.confirmedRuns == 11)
        #expect(try ModelContext(second).fetch(FetchDescriptor<PendingSubmission>()).isEmpty)
    }
    @Test("Same row coordinates in two seasons keep separate stable cached runs")
    func seasonCache() async throws {
        let container = try guestContainer()
        let initial = try guestStateResponse()
        var state = try JSONDecoder().decode(SheetState.self, from: initial)
        state.seasonSheetId = 25; state.seasonYear = 2025
        state.runs = [RunRecord(rowIndex: 23, date: "Fri, 3-Jan", meet: "Beach", run: "Trail",
            identity: RunIdentity(spreadsheetId: "illustrative-workbook", seasonSheetId: 25, runId: "00000064-2222-4222-8222-222222222222"), namedGuestIds: [], unnamedGuests: 0)]
        var emptySeason = state; emptySeason.runs = []
        let transport = StubTransport([.response(initial), .response(try stateData(state)), .response(try stateData(emptySeason))])
        let engine = guestEngine(container, transport)
        _ = try await engine.refreshState(); _ = try await engine.refreshState(seasonSheetId: 25)
        let runs = try ModelContext(container).fetch(FetchDescriptor<ScheduledRun>()).filter { $0.rowIndex == 23 }
        #expect(runs.count == 2)
        #expect(Set(runs.map(\.cacheKey)).count == 2)
        let request = try #require(await transport.requests.last)
        #expect(try JSONDecoder().decode(GuestJSON.self, from: request)["seasonSheetId"]?.int == 25)
        _ = try await engine.refreshState(seasonSheetId: 25)
        let afterDeletion = try ModelContext(container).fetch(FetchDescriptor<ScheduledRun>())
        #expect(afterDeletion.filter { $0.seasonSheetId == 25 }.isEmpty)
        #expect(afterDeletion.filter { $0.seasonSheetId == 26 }.count == 8)
    }
    @Test("An unknown attendance result resumes receipt checking without another submit")
    func unknownResultRestart() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("fctc-shared-restart-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("store.sqlite")
        let container = try guestContainer(url)
        let firstTransport = StubTransport([.response(try guestStateResponse()), .failure(.ambiguousTimeout)])
        let firstEngine = guestEngine(container, firstTransport)
        _ = try await firstEngine.refreshState()
        let id = try await firstEngine.enqueue(draft: guestDraft(), mode: .merge, deviceName: nil)
        await firstEngine.drain()
        let pending = try #require(ModelContext(container).fetch(FetchDescriptor<PendingSubmission>()).first)
        let savedBytes = try #require(pending.sharedOperationData)
        let operation = try JSONDecoder().decode(SharedGuestOperation.self, from: savedBytes)
        #expect(operation.id == id)
        #expect(pending.verificationPending == true)
        let receipt = GuestJSON.object(["ok": .bool(true), "operation": .object([
            "operationId": .string(id.uuidString.lowercased()), "requestDigest": .string(operation.digest), "status": .string("completed"),
            "response": .object(["ok": .bool(true), "written": .number(1), "sheetRevision": .string("after")])])])
        let reopened = try guestContainer(url)
        let secondTransport = StubTransport([.response(try JSONEncoder().encode(receipt)), .response(try guestStateResponse())])
        let restartedEngine = guestEngine(reopened, secondTransport)
        await restartedEngine.drain()
        let requests = try await secondTransport.requests.map { try JSONDecoder().decode(GuestJSON.self, from: $0) }
        #expect(requests.first?["action"]?.string == "getOperationStatus")
        #expect(!requests.contains { $0["action"]?.string == "submitAttendance" })
        let saved = try #require(ModelContext(reopened).fetch(FetchDescriptor<PendingSubmission>()).first)
        #expect(saved.outcome == .committed)
        #expect(saved.sharedOperationData == savedBytes)
    }
    @Test("A stale promoted guest is a conflict even when the aggregate count matches")
    func promotedGuestConflict() async throws {
        let container = try guestContainer()
        var conflictState = try JSONDecoder().decode(GuestJSON.self, from: guestStateResponse())
        if case .object(var fields) = conflictState { fields["sheetRevision"] = .string("after-promotion"); conflictState = .object(fields) }
        let response = GuestJSON.object(["ok": .bool(true), "conflict": .object([
            "reason": .string("guest_promoted"), "message": .string("Review Rene as a member."),
            "memberName": .string("Rene"), "state": conflictState])])
        let transport = StubTransport([.response(try guestStateResponse()), .response(try JSONEncoder().encode(response))])
        let engine = guestEngine(container, transport)
        _ = try await engine.refreshState()
        _ = try await engine.enqueue(draft: guestDraft(), mode: .merge, deviceName: nil)
        await engine.drain()
        let row = try #require(ModelContext(container).fetch(FetchDescriptor<PendingSubmission>()).first)
        #expect(row.status == .conflict)
        #expect(row.conflictReason == "guest_promoted")
        #expect(row.outcome == nil)
        #expect(await transport.requestCount == 2)
    }
    @Test("An endpoint change cannot redirect a queued stable run")
    func endpointBinding() async throws {
        let container = try guestContainer()
        let engine = guestEngine(container, StubTransport([.response(try guestStateResponse())]))
        _ = try await engine.refreshState()
        _ = try await engine.enqueue(draft: guestDraft(), mode: .merge, deviceName: nil)
        let transport = StubTransport()
        let otherAPI = SheetAPI(config: AppConfig(endpoint: URL(string: "https://example.com/other"), secret: "test"), transport: transport)
        let changed = SyncEngine(modelContainer: container, api: otherAPI, automaticallyDrains: false)
        await changed.drain()
        #expect(await transport.requestCount == 0)
        #expect(try ModelContext(container).fetch(FetchDescriptor<PendingSubmission>()).first?.status == .conflict)
    }
    @Test("Ambiguous offline identity parks attendance until an explicit existing selection")
    func identityDependency() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fctc-provisional-\(UUID()).sqlite")
        defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) } }
        let container = try guestContainer(url)
        let transport = StubTransport([.response(try guestStateResponse()), .response(json("{\"ok\":true,\"conflict\":{\"reason\":\"identity_ambiguous\",\"message\":\"Choose a person.\",\"guestIds\":[\"00000001-1111-4111-8111-111111111111\"]}}"))])
        let engine = guestEngine(container, transport)
        _ = try await engine.refreshState()
        let provisional = try await engine.createGuest(name: "Rene", confirmDistinct: false)
        var draft = guestDraft(); draft.guests = [provisional]
        _ = try await engine.enqueue(draft: draft, mode: .merge, deviceName: nil)
        await engine.drain()
        #expect(await transport.requestCount == 2)
        let row = try #require(ModelContext(container).fetch(FetchDescriptor<PendingSubmission>()).first)
        #expect(row.sharedOperationData == nil)
        #expect(row.conflictReason == "identity_ambiguous")
        let reopened = try guestContainer(url)
        let restarted = guestEngine(reopened, transport)
        try await restarted.resolveGuestIdentity(provisionalId: provisional.id.uuidString.lowercased(), existingGuestId: guestID, confirmDistinct: false)
        await transport.append(.response(json("{\"ok\":true,\"written\":1,\"sheetRevision\":\"after\"}")))
        await transport.append(.response(try guestStateResponse()))
        await restarted.drain()
        let requests = try await transport.requests.map { try JSONDecoder().decode(GuestJSON.self, from: $0) }
        let attendance = try #require(requests.first { $0["action"]?.string == "submitAttendance" })
        #expect(attendance["namedGuestIds"] == .array([.string(guestID)]))
        #expect(requests.filter { $0["action"]?.string == "createGuest" }.count == 1)
    }
    /// Two runs park on one ambiguous guest. The organiser discards one, then
    /// resolves the identity. Only the run that is still waiting may be sent.
    @Test("Resolving an identity never resends a discarded attendance row", arguments: [false, true])
    func discardedIdentityDependency(asDistinctPerson: Bool) async throws {
        let container = try guestContainer()
        let ambiguous = json("{\"ok\":true,\"conflict\":{\"reason\":\"identity_ambiguous\",\"message\":\"Choose a person.\",\"guestIds\":[\"\(guestID)\"]}}")
        let transport = StubTransport([.response(try guestStateResponse()), .response(ambiguous)])
        let engine = guestEngine(container, transport)
        _ = try await engine.refreshState()
        let provisional = try await engine.createGuest(name: "Rene", confirmDistinct: false)
        let provisionalId = provisional.id.uuidString.lowercased()
        var discardedDraft = guestDraft(); discardedDraft.guests = [provisional]
        var keptDraft = guestDraft(); keptDraft.guests = [provisional]
        keptDraft.rowIndex = 24; keptDraft.expectedDate = "Fri, 7-Jan"
        keptDraft.runIdentity = RunIdentity(spreadsheetId: "illustrative-workbook", seasonSheetId: 26, runId: "00000068-2222-4222-8222-222222222222")
        let discardedId = try await engine.enqueue(draft: discardedDraft, mode: .merge, deviceName: nil)
        let keptId = try await engine.enqueue(draft: keptDraft, mode: .merge, deviceName: nil)
        await engine.drain()
        let parked = try ModelContext(container).fetch(FetchDescriptor<PendingSubmission>())
        #expect(parked.map(\.conflictReason) == ["identity_ambiguous", "identity_ambiguous"])
        _ = try await engine.resolveConflict(id: discardedId, action: .discard)

        try await engine.resolveGuestIdentity(provisionalId: provisionalId,
            existingGuestId: asDistinctPerson ? nil : guestID, confirmDistinct: asDistinctPerson)
        if asDistinctPerson {
            await transport.append(.response(try JSONEncoder().encode(GuestJSON.object(["ok": .bool(true), "guest": .object([
                "guestId": .string(provisionalId), "displayName": .string("Rene"), "status": .string("active"), "revision": .number(1)
            ])]))))
        }
        await transport.append(.response(json("{\"ok\":true,\"written\":1,\"sheetRevision\":\"after\"}")))
        await transport.append(.response(try guestStateResponse()))
        await engine.drain()

        let rows = try ModelContext(container).fetch(FetchDescriptor<PendingSubmission>())
        let discarded = try #require(rows.first { $0.id == discardedId })
        #expect(discarded.status == .done)
        #expect(discarded.outcome == .discarded)
        #expect(discarded.sharedOperationData == nil)
        #expect(rows.first { $0.id == keptId }?.outcome == .committed)
        let writes = try await transport.requests.map { try JSONDecoder().decode(GuestJSON.self, from: $0) }
            .filter { $0["action"]?.string == "submitAttendance" }
        #expect(writes.map { $0["operationId"]?.string } == [keptId.uuidString.lowercased()])
        #expect(writes.first?["namedGuestIds"] == .array([.string(asDistinctPerson ? provisionalId : guestID)]))
    }
}

private let guestID = "00000001-1111-4111-8111-111111111111"
func guestContainer(_ url: URL? = nil) throws -> ModelContainer {
    let config: ModelConfiguration
    if let url { config = ModelConfiguration(schema: AttendanceSchema.schema, url: url) }
    else { config = ModelConfiguration(schema: AttendanceSchema.schema, isStoredInMemoryOnly: true) }
    return try ModelContainer(for: AttendanceSchema.schema, configurations: config)
}
func guestEngine(_ container: ModelContainer, _ transport: any HTTPTransport) -> SyncEngine {
    SyncEngine(modelContainer: container, api: SheetAPI(config: configuredAPI, transport: transport), automaticallyDrains: false)
}
func guestStateResponse() throws -> Data {
    let root = try JSONDecoder().decode(GuestJSON.self, from: Data(contentsOf: Fixtures.url("guests/contract.json")))
    return try JSONEncoder().encode(root["responses"]!["getState"]!)
}
func stateData(_ state: SheetState) throws -> Data {
    guard case .object(var fields) = try GuestJSON.value(state) else { fatalError() }
    fields["ok"] = .bool(true)
    return try JSONEncoder().encode(GuestJSON.object(fields))
}
func guestDraft() -> AttendanceDraft {
    AttendanceDraft(rowIndex: 23, expectedDate: "Fri, 6-Jan", expectedRun: "Soft Sand",
        checks: ["Col": .manual], guests: [Guest(id: UUID(uuidString: guestID)!, name: "Rene")],
        actualKm: 7.2, baseRevision: "sheet-before",
        runIdentity: RunIdentity(spreadsheetId: "illustrative-workbook", seasonSheetId: 26, runId: "00000067-2222-4222-8222-222222222222"),
        endpointIdentity: configuredAPI.endpoint?.absoluteString, unnamedGuests: 0)
}

@Suite("Shared guest mutation recovery")
struct SharedGuestMutationRecoveryTests {
    @Test("A lost promotion response is checked after restart without another commit")
    func structuralReceipt() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fctc-promotion-\(UUID()).sqlite")
        defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) } }
        let container = try guestContainer(url)
        let fixture = try JSONDecoder().decode(GuestJSON.self, from: Data(contentsOf: Fixtures.url("guests/contract.json")))
        let preview: PromotionPreview = try fixture["responses"]!["previewPromotion"]!.decoded()
        let transport = StubTransport([.response(try guestStateResponse()), .failure(.ambiguousTimeout)])
        let first = guestEngine(container, transport)
        _ = try await first.refreshState()
        let id = try await first.commitPromotion(preview)
        let firstSnapshot = try #require(await first.guestOperation(id: id))
        #expect(firstSnapshot.phase == .checking)
        let row = try #require(ModelContext(container).fetch(FetchDescriptor<PendingGuestOperation>()).first)
        let operation = try #require(row.operation)
        let receipt = GuestJSON.object(["ok": .bool(true), "operation": .object([
            "operationId": .string(id.uuidString.lowercased()), "requestDigest": .string(operation.digest),
            "status": .string("completed"), "response": fixture["responses"]!["commitPromotion"]!
        ])])
        let restartedContainer = try guestContainer(url)
        let restartedTransport = StubTransport([.response(try JSONEncoder().encode(receipt))])
        let restarted = guestEngine(restartedContainer, restartedTransport)
        await restarted.drain()
        let result = try #require(await restarted.guestOperation(id: id))
        #expect(result.phase == .completed)
        #expect(result.response?["confirmedRuns"]?.int == 11)
        let requests = try await restartedTransport.requests.map { try JSONDecoder().decode(GuestJSON.self, from: $0) }
        #expect(requests.count == 1)
        #expect(requests[0]["action"]?.string == "getOperationStatus")
        #expect(requests[0]["operationId"]?.string == id.uuidString.lowercased())
    }
    @Test("A pending fence never causes another structural request")
    func pendingFence() async throws {
        let container = try guestContainer()
        let transport = StubTransport([.response(try guestStateResponse()), .failure(.ambiguousTimeout)])
        let engine = guestEngine(container, transport)
        _ = try await engine.refreshState()
        let guest = try #require(await engine.sharedGuests().first)
        let id = try await engine.renameGuest(guest, name: "René")
        let pending = try #require(ModelContext(container).fetch(FetchDescriptor<PendingGuestOperation>()).first)
        let digest = try #require(pending.operation?.digest)
        let receipt = GuestJSON.object(["ok": .bool(true), "operation": .object([
            "operationId": .string(id.uuidString.lowercased()), "requestDigest": .string(digest), "status": .string("pending"), "response": .null
        ])])
        await transport.append(.response(try JSONEncoder().encode(receipt)))
        await engine.drain()
        #expect(try await engine.guestOperation(id: id)?.phase == .checking)
        let requests = try await transport.requests.map { try JSONDecoder().decode(GuestJSON.self, from: $0) }
        #expect(requests.filter { $0["action"]?.string == "renameGuest" }.count == 1)
    }
    @Test("Naming an existing guest slot encodes zero unnamed remainder and no aggregate override")
    func nameOnlySave() async throws {
        let container = try guestContainer()
        let transport = StubTransport([.response(try guestStateResponse()), .response(json("{\"ok\":true,\"written\":1,\"sheetRevision\":\"after\"}")), .response(try guestStateResponse())])
        let engine = guestEngine(container, transport)
        _ = try await engine.refreshState()
        var draft = guestDraft(); draft.plusOnesOverride = 99
        #expect(draft.plusOnes == 1)
        _ = try await engine.enqueue(draft: draft, mode: .overwrite, deviceName: nil)
        await engine.drain()
        let requests = try await transport.requests.map { try JSONDecoder().decode(GuestJSON.self, from: $0) }
        let write = try #require(requests.first { $0["action"]?.string == "submitAttendance" })
        #expect(write["plusOnes"] == nil)
        #expect(write["unnamedGuests"] == .number(0))
        #expect(write["namedGuestIds"] == .array([.string(guestID)]))
        #expect(write["mode"]?.string == "overwrite")
    }
    /// The server answers `bad_secret` after it read the request, so this is a
    /// post-dispatch refusal: the same bytes are sent again after correction.
    @Test("A server authentication rejection retries the same operation after correction")
    func authenticationRetry() async throws {
        let container = try guestContainer()
        let transport = StubTransport([.response(try guestStateResponse()), .response(json("{\"ok\":false,\"error\":\"bad_secret\",\"message\":\"Rejected\"}"))])
        let engine = guestEngine(container, transport)
        _ = try await engine.refreshState()
        _ = try await engine.enqueue(draft: guestDraft(), mode: .merge, deviceName: nil)
        await engine.drain()
        await transport.append(.response(json("{\"ok\":true,\"written\":1,\"sheetRevision\":\"after\"}")))
        await transport.append(.response(try guestStateResponse()))
        await engine.drain()
        let writes = try await transport.requests.map { try JSONDecoder().decode(GuestJSON.self, from: $0) }
            .filter { $0["action"]?.string == "submitAttendance" }
        #expect(writes.count == 2)
        #expect(writes.first?["operationId"] == writes.last?["operationId"])
        #expect(try ModelContext(container).fetch(FetchDescriptor<PendingSubmission>()).first?.outcome == .committed)
    }

    @Test("A fresh endpoint without capabilities cannot create a shared guest")
    func capabilityGate() async throws {
        let container = try guestContainer()
        let transport = StubTransport([.response(stateResponse)])
        let engine = guestEngine(container, transport)
        _ = try await engine.refreshState()
        await #expect(throws: SheetAPIError.notImplemented) { try await engine.createGuest(name: "Rene", confirmDistinct: false) }
        #expect(await transport.requestCount == 1)
        #expect(try ModelContext(container).fetch(FetchDescriptor<ProvisionalGuest>()).isEmpty)
    }
}

/// Outbox rules for shared attendance rows: parking, conflicts without a
/// server snapshot, and the fences that keep one request in flight.
@Suite("Shared attendance outbox", .serialized)
struct SharedAttendanceOutboxTests {
    /// `parkForReview` stores no snapshot. Merge and Overwrite fall back to the
    /// cached live state, which `resolveSharedConflict` checks by run identity.
    @Test("A parked shared row resolves with Merge and Overwrite", arguments: [ConflictResolutionAction.merge, .overwrite])
    func parkedRowResolves(action: ConflictResolutionAction) async throws {
        let container = try guestContainer()
        let transport = StubTransport([.response(try guestStateResponse()), .response(rejection("sheet_unreadable"))])
        let engine = guestEngine(container, transport)
        _ = try await engine.refreshState()
        let id = try await engine.enqueue(draft: guestDraft(), mode: .merge, deviceName: "Col's phone")
        await engine.drain()
        let parked = try #require(try ModelContext(container).fetch(FetchDescriptor<PendingSubmission>()).first)
        #expect(parked.conflictReason == "identity_review_required")
        #expect(parked.conflictState == nil)

        let replacementId = try #require(try await engine.resolveConflict(id: id, action: action))
        let rows = try ModelContext(container).fetch(FetchDescriptor<PendingSubmission>())
        let old = try #require(rows.first { $0.id == id })
        let replacement = try #require(rows.first { $0.id == replacementId })
        #expect(replacement.status == .queued)
        #expect(replacement.mode == (action == .overwrite ? .overwrite : .merge))
        #expect(replacement.runIdentity == old.runIdentity)
        #expect(replacement.sharedOperationData == nil)
        // CA-13: the replacement keeps the device and the old row is closed cleanly.
        #expect(replacement.deviceName == "Col's phone")
        #expect(old.outcome == .superseded)
        #expect(old.lastError == nil)
        #expect(old.conflictReason == nil && old.conflictMessage == nil)
    }
    @Test("A conflict without a server snapshot still resolves with Merge")
    func conflictWithoutState() async throws {
        let container = try guestContainer()
        let conflict = json("{\"ok\":true,\"conflict\":{\"reason\":\"row_mismatch\",\"message\":\"Changed.\"}}")
        let engine = guestEngine(container, StubTransport([.response(try guestStateResponse()), .response(conflict)]))
        _ = try await engine.refreshState()
        let id = try await engine.enqueue(draft: guestDraft(), mode: .merge, deviceName: nil)
        await engine.drain()
        #expect(try await engine.pendingSubmission(id: id)?.conflictState == nil)
        let replacementId = try #require(try await engine.resolveConflict(id: id, action: .merge))
        #expect(try await engine.pendingSubmission(id: replacementId)?.status == .queued)
    }
    @Test("An ambiguous identity asks for a guest review, not a server snapshot")
    func ambiguousIdentityResolution() async throws {
        let container = try guestContainer()
        let ambiguous = json("{\"ok\":true,\"conflict\":{\"reason\":\"identity_ambiguous\",\"message\":\"Choose a person.\",\"guestIds\":[\"\(guestID)\"]}}")
        let engine = guestEngine(container, StubTransport([.response(try guestStateResponse()), .response(ambiguous)]))
        _ = try await engine.refreshState()
        var draft = guestDraft(); draft.guests = [try await engine.createGuest(name: "Rene", confirmDistinct: false)]
        let id = try await engine.enqueue(draft: draft, mode: .merge, deviceName: nil)
        await engine.drain()
        await #expect(throws: SheetAPIError.badPayload(message: "Review the guest identity before saving a new draft.")) {
            try await engine.resolveConflict(id: id, action: .merge)
        }
    }
    /// CA-11: a digest mismatch is certain before any dispatch. It must park
    /// instead of re-queueing as "checking saved changes" forever.
    @Test("A receipt digest mismatch parks the row without another submit")
    func digestMismatchParks() async throws {
        let container = try guestContainer()
        let transport = StubTransport([.response(try guestStateResponse()), .failure(.ambiguousTimeout)])
        let engine = guestEngine(container, transport)
        _ = try await engine.refreshState()
        let id = try await engine.enqueue(draft: guestDraft(), mode: .merge, deviceName: nil)
        await engine.drain()
        await transport.append(.response(try receiptResponse(id: id, digest: "another-request", status: "completed")))
        await engine.drain()
        let row = try #require(try await engine.pendingSubmission(id: id))
        #expect(row.status == .conflict)
        #expect(row.conflictReason == "identity_review_required")
        #expect(try await submits(transport).count == 1)
    }
    @Test("A pending receipt leaves the row checking without another submit")
    func pendingReceipt() async throws {
        let container = try guestContainer()
        let transport = StubTransport([.response(try guestStateResponse()), .failure(.ambiguousTimeout)])
        let engine = guestEngine(container, transport)
        _ = try await engine.refreshState()
        let id = try await engine.enqueue(draft: guestDraft(), mode: .merge, deviceName: nil)
        await engine.drain()
        let digest = try #require(try operationDigest(container))
        await transport.append(.response(try receiptResponse(id: id, digest: digest, status: "pending")))
        await engine.drain()
        let row = try #require(try await engine.pendingSubmission(id: id))
        #expect(row.verificationPending)
        #expect(row.outcome == nil)
        #expect(row.status == .queued)
        #expect(try await submits(transport).count == 1)
    }
    @Test("Busy after dispatch re-queues the same operation and clears verification")
    func busyAfterDispatch() async throws {
        let container = try guestContainer()
        let transport = StubTransport([.response(try guestStateResponse()), .response(rejection("busy"))])
        let engine = guestEngine(container, transport)
        _ = try await engine.refreshState()
        let id = try await engine.enqueue(draft: guestDraft(), mode: .merge, deviceName: nil)
        await engine.drain()
        let row = try #require(try await engine.pendingSubmission(id: id))
        #expect(row.status == .queued)
        #expect(!row.verificationPending)
        #expect(row.lastError == UserFacingError.busy)
        await transport.append(.response(json("{\"ok\":true,\"written\":1,\"sheetRevision\":\"after\"}")))
        await transport.append(.response(try guestStateResponse()))
        await engine.drain()
        let writes = try await submits(transport)
        #expect(writes.count == 2)
        #expect(writes.first?["operationId"] == writes.last?["operationId"])
        #expect(try await engine.pendingSubmission(id: id)?.outcome == .committed)
    }
    @Test("A workbook with a pending operation holds a new attendance row before it is built")
    func pendingOperationGate() async throws {
        let container = try guestContainer()
        var state = try JSONDecoder().decode(SheetState.self, from: guestStateResponse())
        state.pendingOperationId = UUID().uuidString.lowercased()
        let transport = StubTransport([.response(try stateData(state))])
        let engine = guestEngine(container, transport)
        _ = try await engine.refreshState()
        let id = try await engine.enqueue(draft: guestDraft(), mode: .merge, deviceName: nil)
        await engine.drain()
        let row = try #require(try await engine.pendingSubmission(id: id))
        #expect(row.status == .queued)
        #expect(row.lastError == UserFacingError.checkingSavedChanges)
        #expect(try ModelContext(container).fetch(FetchDescriptor<PendingSubmission>()).first?.sharedOperationData == nil)
        #expect(await transport.requestCount == 1)
    }
    /// A fence that names another operation proves this request was not
    /// applied. A fence naming this one, or no one, keeps the receipt check.
    @Test("A server fence keeps verification only for this operation",
          arguments: ["pending_verification", "pending_operation"], FenceOwner.allCases)
    func attendanceFence(reason: String, owner: FenceOwner) async throws {
        let container = try guestContainer()
        let transport = StubTransport([.response(try guestStateResponse())])
        let engine = guestEngine(container, transport)
        _ = try await engine.refreshState()
        let id = try await engine.enqueue(draft: guestDraft(), mode: .merge, deviceName: nil)
        await transport.append(.response(try fenceResponse(reason: reason, owner: owner, id: id)))
        await engine.drain()
        let row = try #require(try await engine.pendingSubmission(id: id))
        #expect(row.status == .queued)
        #expect(row.verificationPending == (owner != .foreign))
        #expect(row.lastError == UserFacingError.checkingSavedChanges)
    }
}

/// Who a `pending_verification` or `pending_operation` fence names.
enum FenceOwner: CaseIterable, Sendable { case own, foreign, none }

/// A fence conflict as the server sends it, naming `owner`'s operation id.
func fenceResponse(reason: String, owner: FenceOwner, id: UUID) throws -> Data {
    var conflict: [String: GuestJSON] = ["reason": .string(reason), "message": .string("Another change is saving.")]
    switch owner {
    case .own: conflict["operationId"] = .string(id.uuidString.lowercased())
    case .foreign: conflict["operationId"] = .string(UUID().uuidString.lowercased())
    case .none: break
    }
    return try JSONEncoder().encode(GuestJSON.object(["ok": .bool(true), "conflict": .object(conflict)]))
}

/// A `getOperationStatus` answer for `id`.
func receiptResponse(id: UUID, digest: String, status: String) throws -> Data {
    let receipt = GuestOperationReceipt(operationId: id.uuidString.lowercased(), requestDigest: digest, status: status)
    return try JSONEncoder().encode(GuestJSON.object(["ok": .bool(true), "operation": try .value(receipt)]))
}

/// The digest of the one saved attendance operation.
private func operationDigest(_ container: ModelContainer) throws -> String? {
    try ModelContext(container).fetch(FetchDescriptor<PendingSubmission>()).first?.sharedOperationData
        .map { try JSONDecoder().decode(SharedGuestOperation.self, from: $0).digest }
}

/// Every `submitAttendance` request the transport received.
private func submits(_ transport: StubTransport) async throws -> [GuestJSON] {
    try await transport.requests.map { try JSONDecoder().decode(GuestJSON.self, from: $0) }
        .filter { $0["action"]?.string == "submitAttendance" }
}

/// A server error envelope, as Apps Script sends it after it read the request.
func rejection(_ code: String) -> Data {
    json("{\"ok\":false,\"error\":\"\(code)\",\"message\":\"Rejected\"}")
}
