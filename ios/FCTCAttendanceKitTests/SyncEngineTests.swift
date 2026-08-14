//
//  SyncEngineTests.swift
//  FCTCAttendanceKitTests
//
//  End-to-end outbox tests with real SwiftData and scripted transport responses.
//


import Foundation
import SwiftData
import Testing

@testable import FCTCAttendanceKit

actor ImmediateSyncClock: SyncClock {
    private(set) var sleeps: [TimeInterval] = []
    private var instant = Date(timeIntervalSince1970: 1_700_000_000)

    func now() async -> Date { instant }

    func sleep(for seconds: TimeInterval) async throws {
        sleeps.append(seconds)
        instant.addTimeInterval(seconds)
    }

    var recordedSleeps: [TimeInterval] { sleeps }
}

actor SuspendingTransport: HTTPTransport {
    private var continuation: CheckedContinuation<Data, any Error>?

    func post(_ body: Data) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilRequested() async {
        while continuation == nil { await Task.yield() }
    }

    func resume(returning data: Data) {
        continuation?.resume(returning: data)
        continuation = nil
    }
}

@Suite("Sync engine")
struct SyncEngineTests {

    @Test("Every view-model event subscriber receives the same event")
    func eventBroadcast() async throws {
        let container = try makeContainer()
        let engine = makeEngine(container: container, transport: StubTransport([]))
        var first = engine.events.makeAsyncIterator()
        var second = engine.events.makeAsyncIterator()

        let id = try await engine.enqueue(.fixture)

        #expect(await first.next() == .queued(id: id))
        #expect(await second.next() == .queued(id: id))
    }

    @Test("A confirmed submission writes and updates the cached run")
    func happyPath() async throws {
        let container = try makeContainer()
        let transport = StubTransport([
            .response(stateResponse),
            .response(json("{\"ok\":true,\"written\":39,\"sheetRevision\":\"rev-2\"}")),
        ])
        let engine = makeEngine(container: container, transport: transport)

        _ = try await engine.refreshState()
        let id = try await engine.enqueue(.fixture)
        await engine.drain()

        let fetchedPending = try fetchPending(container, id: id)
        let runs = try fetchRuns(container)
        let pending = try #require(fetchedPending)
        let run = try #require(runs.first)
        #expect(pending.status == .done)
        #expect(run.attendees == ["Col"])
        #expect(run.actualKm == 7.1)
        #expect(run.plusOnes == 1)
        #expect(run.cachedRevision == "rev-2")
    }

    @Test("Offline work stays queued, parks, then drains on recovery")
    func offlineRecovery() async throws {
        let container = try makeContainer()
        let clock = ImmediateSyncClock()
        let transport = StubTransport(Array(repeating: .failure(.offline), count: 5))
        let engine = makeEngine(container: container, transport: transport, clock: clock)
        let id = try await engine.enqueue(.fixture)

        await engine.drain()

        var fetchedPending = try fetchPending(container, id: id)
        var pending = try #require(fetchedPending)
        #expect(pending.status == .queued)
        #expect(pending.attemptCount == 5)
        #expect(await clock.recordedSleeps == [2, 4, 8, 16])

        await transport.append(
            .response(json("{\"ok\":true,\"written\":39,\"sheetRevision\":\"rev-2\"}"))
        )
        await engine.drain()

        fetchedPending = try fetchPending(container, id: id)
        pending = try #require(fetchedPending)
        #expect(pending.status == .done)
        #expect(pending.attemptCount == 6)
    }

    @Test("An ambiguous timeout safely submits the same absolute payload twice")
    func idempotentRetry() async throws {
        let container = try makeContainer()
        let transport = StubTransport([
            .failure(.ambiguousTimeout),
            .response(json("{\"ok\":true,\"written\":0,\"sheetRevision\":\"rev-2\"}")),
        ])
        let engine = makeEngine(container: container, transport: transport)
        let id = try await engine.enqueue(.fixture)

        await engine.drain()

        let fetchedPending = try fetchPending(container, id: id)
        let pending = try #require(fetchedPending)
        #expect(pending.status == .done)
        #expect(pending.attemptCount == 2)
        #expect(await transport.requestCount == 2)
    }

    @Test("A stale retry is done when fresh state already contains the write")
    func ambiguousSuccessConflict() async throws {
        let container = try makeContainer()
        let transport = StubTransport([
            .failure(.ambiguousTimeout),
            .response(json(
                """
                {
                  "ok":true,
                  "conflict":{
                    "reason":"stale_revision",
                    "message":"The sheet changed.",
                    "state":{
                      "roster":[],
                      "runs":[{
                        "rowIndex":42,
                        "date":"Fri, 2-Jan",
                        "meet":"Il Lido",
                        "run":"Soft Sand",
                        "approxKm":7.1,
                        "actualKm":7.1,
                        "attendees":["Col"],
                        "plusOnes":1
                      }],
                      "seasonYear":2026,
                      "sheetRevision":"rev-2"
                    }
                  }
                }
                """
            )),
        ])
        let engine = makeEngine(container: container, transport: transport)
        let id = try await engine.enqueue(.fixture)

        await engine.drain()

        let fetchedPending = try fetchPending(container, id: id)
        let pending = try #require(fetchedPending)
        #expect(pending.status == .done)
        #expect(pending.baseRevision == "rev-2")
        #expect(pending.conflictState == nil)
        #expect(await transport.requestCount == 2)
        let runs = try fetchRuns(container)
        #expect(runs.first?.cachedRevision == "rev-2")
    }

    @Test("A successful write rebases later rows from the same revision")
    func orderedQueueRebase() async throws {
        let container = try makeContainer()
        let transport = StubTransport([
            .response(json("{\"ok\":true,\"written\":1,\"sheetRevision\":\"rev-2\"}")),
            .response(json("{\"ok\":true,\"written\":1,\"sheetRevision\":\"rev-3\"}")),
        ])
        let engine = makeEngine(container: container, transport: transport)
        let firstID = try await engine.enqueue(.fixture)
        var second = AttendanceSubmission.fixture
        second.rowIndex = 43
        second.expectedDate = "Sat, 3-Jan"
        second.expectedRun = "Parkrun"
        let secondID = try await engine.enqueue(second)

        await engine.drain()

        let firstPending = try fetchPending(container, id: firstID)
        let secondPending = try fetchPending(container, id: secondID)
        #expect(firstPending?.status == .done)
        #expect(secondPending?.status == .done)
        let requests = await transport.requests
        #expect(requests.count == 2)
        let secondBody = try #require(
            JSONSerialization.jsonObject(with: requests[1]) as? [String: Any]
        )
        #expect(secondBody["baseRevision"] as? String == "rev-2")
    }

    @Test("A conflict is persisted and emitted with fresh server state")
    func conflictSurfacing() async throws {
        let container = try makeContainer()
        let transport = StubTransport([
            .response(json(
                """
                {
                  "ok":true,
                  "conflict":{
                    "reason":"stale_revision",
                    "message":"The sheet changed.",
                    "state":{
                      "roster":[],"runs":[],"seasonYear":2026,
                      "sheetRevision":"rev-fresh"
                    }
                  }
                }
                """
            )),
        ])
        let engine = makeEngine(container: container, transport: transport)
        var events = engine.events.makeAsyncIterator()
        let id = try await engine.enqueue(.fixture)

        await engine.drain()

        _ = await events.next() // queued
        let event = await events.next()
        let fetchedPending = try fetchPending(container, id: id)
        let pending = try #require(fetchedPending)
        #expect(pending.status == .conflict)
        #expect(pending.conflictReason == "stale_revision")
        #expect(pending.conflictState?.sheetRevision == "rev-fresh")
        #expect(
            event == .conflict(
                id: id,
                reason: "stale_revision",
                message: "The sheet changed.",
                state: SheetState(seasonYear: 2026, sheetRevision: "rev-fresh")
            )
        )
    }

    @Test("addMember is optimistic, then reconciles to server coordinates")
    func optimisticMember() async throws {
        let container = try makeContainer()
        let transport = SuspendingTransport()
        let api = SheetAPI(config: configuredAPI, transport: transport)
        let engine = SyncEngine(
            modelContainer: container,
            api: api,
            clock: ImmediateSyncClock(),
            automaticallyDrains: false
        )

        let operation = Task { try await engine.addMember(name: "Bilbo") }
        await transport.waitUntilRequested()

        var member = try #require(fetchMembers(container).first { $0.name == "Bilbo" })
        #expect(member.isNew)

        await transport.resume(returning: json(
            """
            {
              "ok":true,
              "roster":[
                {"name":"Aaron","colIndex":6},
                {"name":"Bilbo","colIndex":7},
                {"name":"Col","colIndex":8}
              ],
              "sheetRevision":"rev-2"
            }
            """
        ))
        let result = try await operation.value

        member = try #require(fetchMembers(container).first { $0.name == "Bilbo" })
        #expect(!member.isNew)
        #expect(member.colIndex == 7)
        #expect(result.sheetRevision == "rev-2")
    }

    @Test("A failed member add rolls back the optimistic roster insertion")
    func optimisticMemberRollback() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.insert(Member(name: "Aaron", colIndex: 6))
        context.insert(Member(name: "Col", colIndex: 7))
        try context.save()
        let engine = makeEngine(
            container: container,
            transport: StubTransport([.failure(.offline)])
        )

        await #expect(throws: SheetAPIError.self) {
            try await engine.addMember(name: "Bilbo")
        }

        let members = try fetchMembers(container).sorted { $0.colIndex < $1.colIndex }
        #expect(members.map(\.name) == ["Aaron", "Col"])
        #expect(members.map(\.colIndex) == [6, 7])
        #expect(!members.contains { $0.isNew })
    }

    @Test("Added runs keep the cached season year after row insertion")
    func addRunSeasonYear() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let knownDate = try #require(
            Calendar(identifier: .gregorian).date(
                from: DateComponents(year: 2026, month: 1, day: 9)
            )
        )
        context.insert(
            ScheduledRun(
                rowIndex: 42,
                date: "Fri, 9-Jan",
                scheduledAt: knownDate,
                meet: "Old Meet",
                run: "Old Run"
            )
        )
        try context.save()
        let response = json(
            """
            {
              "ok":true,
              "runs":[
                {
                  "rowIndex":42,"date":"Fri, 2-Jan","meet":"New Meet",
                  "run":"New Run","approxKm":5,"actualKm":null,
                  "attendees":[],"plusOnes":0
                },
                {
                  "rowIndex":43,"date":"Fri, 9-Jan","meet":"Old Meet",
                  "run":"Old Run","approxKm":7,"actualKm":null,
                  "attendees":[],"plusOnes":0
                }
              ],
              "sheetRevision":"rev-2"
            }
            """
        )
        let engine = makeEngine(
            container: container,
            transport: StubTransport([.response(response)])
        )

        _ = try await engine.addRun(
            AddRunRequest(date: "Fri, 2-Jan", meet: "New Meet", run: "New Run")
        )

        let runs = try fetchRuns(container).sorted { $0.rowIndex < $1.rowIndex }
        #expect(runs.map(\.rowIndex) == [42, 43])
        #expect(runs.map(\.run) == ["New Run", "Old Run"])
        let calendar = Calendar(identifier: .gregorian)
        #expect(runs.allSatisfy {
            guard let date = $0.scheduledAt else { return false }
            return calendar.component(.year, from: date) == 2026
        })
    }

    @Test("refresh makes the server authoritative but keeps unsynced local members")
    func refreshReconciliation() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.insert(Member(name: "Gone", colIndex: 6))
        context.insert(Member(name: "Local", colIndex: 7, isNew: true))
        try context.save()

        let engine = makeEngine(
            container: container,
            transport: StubTransport([.response(stateResponse)])
        )
        _ = try await engine.refreshState()

        let members = try fetchMembers(container)
        #expect(!members.contains { $0.name == "Gone" })
        #expect(members.contains { $0.name == "Local" && $0.isNew })
        #expect(members.contains { $0.name == "Aaron" && !$0.isNew })
        let runs = try fetchRuns(container)
        #expect(runs.first?.cachedRevision == "rev-1")
    }

    @Test("Conflict merge and overwrite choices close history and re-enqueue fresh rows")
    func conflictReenqueue() async throws {
        for (action, expectedMode) in [
            (ConflictResolutionAction.merge, SubmissionMode.merge),
            (.overwrite, .overwrite),
        ] {
            let container = try makeContainer()
            let context = ModelContext(container)
            let conflict = PendingSubmission(
                rowIndex: 42,
                expectedDate: "Fri, 2-Jan",
                expectedRun: "Soft Sand",
                attendees: ["Col"],
                plusOnes: 1,
                actualKm: 7.1,
                status: .conflict,
                baseRevision: "rev-old"
            )
            conflict.attachConflict(
                reason: "stale_revision",
                message: "The sheet changed.",
                state: SheetState(
                    runs: [
                        RunRecord(
                            rowIndex: 44,
                            date: "Fri, 2-Jan",
                            meet: "Il Lido",
                            run: "Soft Sand"
                        ),
                    ],
                    seasonYear: 2026,
                    sheetRevision: "rev-fresh"
                )
            )
            context.insert(conflict)
            try context.save()
            let engine = makeEngine(container: container, transport: StubTransport([]))

            let replacementID = try #require(
                try await engine.resolveConflict(id: conflict.id, action: action)
            )

            let rows = try fetchAllPending(container)
            let oldRow = try #require(rows.first { $0.id == conflict.id })
            let replacement = try #require(rows.first { $0.id == replacementID })
            #expect(oldRow.status == .done)
            #expect(!oldRow.isOutstanding)
            #expect(replacement.status == .queued)
            #expect(replacement.mode == expectedMode)
            #expect(replacement.rowIndex == 44)
            #expect(replacement.baseRevision == "rev-fresh")
        }
    }

    @Test("Discard closes a conflict without creating another outbox row")
    func conflictDiscard() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let conflict = PendingSubmission(
            rowIndex: 42,
            expectedDate: "Fri, 2-Jan",
            expectedRun: "Soft Sand",
            attendees: ["Col"],
            status: .conflict
        )
        conflict.attachConflict(
            reason: "stale_revision",
            message: "The sheet changed.",
            state: SheetState(sheetRevision: "rev-fresh")
        )
        context.insert(conflict)
        try context.save()
        let engine = makeEngine(container: container, transport: StubTransport([]))

        let replacementID = try await engine.resolveConflict(id: conflict.id, action: .discard)

        let rows = try fetchAllPending(container)
        #expect(replacementID == nil)
        #expect(rows.count == 1)
        #expect(rows.first?.status == .done)
    }
}

private func makeContainer() throws -> ModelContainer {
    try ModelContainer(
        for: AttendanceSchema.schema,
        configurations: ModelConfiguration(
            "FCTCAttendanceKitTests",
            schema: AttendanceSchema.schema,
            isStoredInMemoryOnly: true
        )
    )
}

private func makeEngine(
    container: ModelContainer,
    transport: any HTTPTransport,
    clock: any SyncClock = ImmediateSyncClock()
) -> SyncEngine {
    let api = SheetAPI(config: configuredAPI, transport: transport)
    return SyncEngine(
        modelContainer: container,
        api: api,
        clock: clock,
        automaticallyDrains: false
    )
}

private func fetchPending(
    _ container: ModelContainer,
    id: UUID
) throws -> PendingSubmission? {
    let context = ModelContext(container)
    return try context.fetch(FetchDescriptor<PendingSubmission>()).first { $0.id == id }
}

private func fetchAllPending(_ container: ModelContainer) throws -> [PendingSubmission] {
    let context = ModelContext(container)
    return try context.fetch(FetchDescriptor<PendingSubmission>())
}

private func fetchMembers(_ container: ModelContainer) throws -> [Member] {
    let context = ModelContext(container)
    return try context.fetch(FetchDescriptor<Member>())
}

private func fetchRuns(_ container: ModelContainer) throws -> [ScheduledRun] {
    let context = ModelContext(container)
    return try context.fetch(FetchDescriptor<ScheduledRun>())
}
