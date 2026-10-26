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
    /// Every request that reached the transport, answered or not.
    private(set) var requestCount = 0

    func post(_ body: Data) async throws -> Data {
        requestCount += 1
        return try await withCheckedThrowingContinuation { continuation in
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

@Suite("Sync engine", .timeLimit(.minutes(1)))
struct SyncEngineTests {

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

    /// A dropped connection or an Apps Script hiccup at launch clears on the
    /// next try, so the Home banner never flashes "offline" for it.
    @Test("A refresh retries a transient failure before it gives up")
    func refreshRetriesTransientFailures() async throws {
        let recovered = StubTransport([.failure(.offline), .response(stateResponse)])
        let engine = makeEngine(container: try makeContainer(), transport: recovered)
        #expect(try await engine.refreshState().sheetRevision == "rev-1")
        #expect(await recovered.requestCount == 2)

        let down = StubTransport([.failure(.offline), .failure(.offline), .failure(.offline), .response(stateResponse)])
        let offline = makeEngine(container: try makeContainer(), transport: down)
        await #expect(throws: SheetAPIError.self) { try await offline.refreshState() }
        #expect(await down.requestCount == 3)
    }

    /// The Dashboard counts "Sat 3-Jan" and "9-Jan" (the web and Apps Script
    /// rule), so the Runs tab must give them a day too, not file them "Later".
    @Test("Loose sheet dates still get a scheduled day")
    func looseDatesScheduled() async throws {
        let container = try makeContainer()
        let response = json(
            """
            {
              "ok":true,
              "roster":[],
              "runs":[
                {"rowIndex":42,"date":"Sat 3-Jan","meet":"Il Lido","run":"Soft Sand",
                 "approxKm":5,"actualKm":null,"attendees":[],"plusOnes":0},
                {"rowIndex":43,"date":"9-Jan","meet":"Il Lido","run":"Tempo",
                 "approxKm":5,"actualKm":null,"attendees":[],"plusOnes":0},
                {"rowIndex":44,"date":"Notes","meet":"","run":"",
                 "approxKm":null,"actualKm":null,"attendees":[],"plusOnes":0}
              ],
              "seasonYear":2026,
              "sheetRevision":"rev-1"
            }
            """
        )
        let engine = makeEngine(container: container, transport: StubTransport([.response(response)]))

        _ = try await engine.refreshState()

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let days = try fetchRuns(container).sorted { $0.rowIndex < $1.rowIndex }.map { run in
            run.scheduledAt.map { calendar.dateComponents([.year, .month, .day, .hour], from: $0) }
        }
        #expect(days == [
            DateComponents(year: 2026, month: 1, day: 3, hour: 0),
            DateComponents(year: 2026, month: 1, day: 9, hour: 0),
            nil,
        ])
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

    @Test("refresh caches lifetime totals onto the roster")
    func refreshCachesLifetimeTotals() async throws {
        let container = try makeContainer()
        let engine = makeEngine(
            container: container,
            transport: StubTransport([.response(stateResponseWithTotals)])
        )

        _ = try await engine.refreshState()

        let members = try fetchMembers(container)
        #expect(members.first { $0.name == "Aaron" }?.lifetimeRuns == 129)
        #expect(members.first { $0.name == "Col" }?.lifetimeRuns == 47)
        // "Ghost" has a total but is not on the roster, so it must not become a member.
        #expect(!members.contains { $0.name == "Ghost" })
        #expect(members.count == 2)
    }

    @Test("A second refresh updates totals in place rather than duplicating members")
    func refreshUpdatesTotalsInPlace() async throws {
        let container = try makeContainer()
        let bumped = json(
            stateResponseWithTotalsText.replacingOccurrences(
                of: "\"runs\": 129",
                with: "\"runs\": 130"
            )
        )
        let engine = makeEngine(
            container: container,
            transport: StubTransport([
                .response(stateResponseWithTotals),
                .response(bumped),
            ])
        )

        _ = try await engine.refreshState()
        _ = try await engine.refreshState()

        let members = try fetchMembers(container)
        #expect(members.count == 2)
        #expect(members.first { $0.name == "Aaron" }?.lifetimeRuns == 130)
    }

    @Test("A script without totals leaves the cached numbers alone")
    func refreshWithoutTotalsKeepsCache() async throws {
        // Back-compat guard: a redeploy rollback, or a conflict payload from an
        // older script, must not blank what the app already knows.
        let container = try makeContainer()
        let engine = makeEngine(
            container: container,
            transport: StubTransport([
                .response(stateResponseWithTotals),
                .response(stateResponse),
            ])
        )

        _ = try await engine.refreshState()
        _ = try await engine.refreshState()

        let members = try fetchMembers(container)
        #expect(members.first { $0.name == "Aaron" }?.lifetimeRuns == 129)
        #expect(members.first { $0.name == "Col" }?.lifetimeRuns == 47)
    }

    @Test("A member the server reports no total for stays at zero")
    func memberWithoutTotalIsZero() async throws {
        let container = try makeContainer()
        let engine = makeEngine(
            container: container,
            transport: StubTransport([.response(stateResponse)])
        )

        _ = try await engine.refreshState()

        let members = try fetchMembers(container)
        #expect(members.allSatisfy { $0.lifetimeRuns == 0 })
    }
}

extension AsyncStream<SyncEvent>.Iterator {
    /// The next event other than drain activity, which now brackets every
    /// drain. Tests that assert a specific sequence of outcomes skip it.
    mutating func nextIgnoringActivity() async -> SyncEvent? {
        while let event = await next() {
            if case .syncActivity = event { continue }
            return event
        }
        return nil
    }
}
