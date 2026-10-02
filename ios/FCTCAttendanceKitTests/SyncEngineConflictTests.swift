//
//  SyncEngineConflictTests.swift
//  FCTCAttendanceKitTests
//
//  Sync engine: stale-revision conflicts, resolution choices and their races.
//

import Foundation
import SwiftData
import Testing

@testable import FCTCAttendanceKit

extension SyncEngineTests {

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
                    "reason":"row_mismatch",
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

        _ = await events.nextIgnoringActivity() // queued
        let event = await events.nextIgnoringActivity()
        let fetchedPending = try fetchPending(container, id: id)
        let pending = try #require(fetchedPending)
        #expect(pending.status == .conflict)
        #expect(pending.conflictReason == "row_mismatch")
        #expect(pending.conflictState?.sheetRevision == "rev-fresh")
        #expect(
            event == .conflict(
                id: id,
                reason: "row_mismatch",
                message: "The sheet changed.",
                state: SheetState(seasonYear: 2026, sheetRevision: "rev-fresh")
            )
        )
    }

    @Test("A merge stale-revision conflict rebases and succeeds once")
    func mergeConflictAutoRetry() async throws {
        let container = try makeContainer()
        let transport = StubTransport([
            .response(staleConflict(revision: "rev-2", attendees: ["Aaron"])),
            .response(json("{\"ok\":true,\"written\":1,\"sheetRevision\":\"rev-3\"}")),
        ])
        let engine = makeEngine(container: container, transport: transport)
        var submission = AttendanceSubmission.fixture
        submission.mode = .merge
        let id = try await engine.enqueue(submission)

        await engine.drain()

        let fetchedPending = try fetchPending(container, id: id)
        let pending = try #require(fetchedPending)
        #expect(pending.status == .done)
        #expect(pending.attemptCount == 2)
        #expect(await transport.requestCount == 2)
        let requests = await transport.requests
        let retryBody = try #require(
            JSONSerialization.jsonObject(with: requests[1]) as? [String: Any]
        )
        #expect(retryBody["baseRevision"] as? String == "rev-2")
    }

    @Test("An overwrite stale-revision conflict still surfaces")
    func overwriteConflictSurfaces() async throws {
        let container = try makeContainer()
        let transport = StubTransport([
            .response(staleConflict(revision: "rev-2", attendees: ["Aaron"])),
        ])
        let engine = makeEngine(container: container, transport: transport)
        var submission = AttendanceSubmission.fixture
        submission.mode = .overwrite
        let id = try await engine.enqueue(submission)

        await engine.drain()

        let fetchedPending = try fetchPending(container, id: id)
        let pending = try #require(fetchedPending)
        #expect(pending.status == .conflict)
        #expect(pending.attemptCount == 1)
        #expect(await transport.requestCount == 1)
    }

    @Test("A second merge conflict surfaces after one automatic retry")
    func doubleMergeConflictSurfaces() async throws {
        let container = try makeContainer()
        let transport = StubTransport([
            .response(staleConflict(revision: "rev-2", attendees: ["Aaron"])),
            .response(staleConflict(revision: "rev-3", attendees: ["Aaron", "Dan"])),
        ])
        let engine = makeEngine(container: container, transport: transport)
        var submission = AttendanceSubmission.fixture
        submission.mode = .merge
        let id = try await engine.enqueue(submission)

        await engine.drain()

        let fetchedPending = try fetchPending(container, id: id)
        let pending = try #require(fetchedPending)
        #expect(pending.status == .conflict)
        #expect(pending.conflictState?.sheetRevision == "rev-3")
        #expect(pending.attemptCount == 2)
        #expect(await transport.requestCount == 2)
    }

    @Test("A merge conflict with a newer distance still surfaces")
    func mergeDistanceConflictSurfaces() async throws {
        let container = try makeContainer()
        let transport = StubTransport([
            .response(staleConflict(
                revision: "rev-2",
                attendees: ["Aaron"],
                actualKm: 8.2
            )),
        ])
        let engine = makeEngine(container: container, transport: transport)
        var submission = AttendanceSubmission.fixture
        submission.mode = .merge
        let id = try await engine.enqueue(submission)

        await engine.drain()

        let fetchedPending = try fetchPending(container, id: id)
        let pending = try #require(fetchedPending)
        #expect(pending.status == .conflict)
        #expect(pending.attemptCount == 1)
        #expect(await transport.requestCount == 1)
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

private func staleConflict(
    revision: String,
    attendees: [String],
    actualKm: Double? = nil
) -> Data {
    let names = attendees.map { "\"\($0)\"" }.joined(separator: ",")
    let distance = actualKm.map { String($0) } ?? "null"
    return json(
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
                "actualKm":\(distance),
                "attendees":[\(names)],
                "plusOnes":0
              }],
              "seasonYear":2026,
              "sheetRevision":"\(revision)"
            }
          }
        }
        """
    )
}

/// Holds every `now()` until `count` callers wait there, then releases them
/// together. Two calls that read the clock are then both suspended at once.
actor GateClock: SyncClock {
    private var count = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func arm(_ count: Int) { self.count = count }

    func now() async -> Date {
        if count > 0 {
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
                guard waiters.count == count else { return }
                count = 0
                waiters.forEach { $0.resume() }
                waiters = []
            }
        }
        return Date(timeIntervalSince1970: 1_700_000_000)
    }

    func sleep(for seconds: TimeInterval) async throws {}
}

@Suite("Conflict resolution races")
struct ConflictResolutionRaceTests {
    /// CC-3: the guard and its mutation must not straddle a clock read, or two
    /// taps on Merge both pass the guard and queue two replacements.
    @Test("Two concurrent resolutions queue one replacement", arguments: [false, true])
    func concurrentResolution(shared: Bool) async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let identity = RunIdentity(spreadsheetId: "book", seasonSheetId: 26, runId: "run-42")
        let conflict = PendingSubmission(rowIndex: 42, expectedDate: "Fri, 2-Jan", expectedRun: "Soft Sand",
                                         attendees: ["Col"], status: .conflict)
        if shared {
            conflict.spreadsheetId = identity.spreadsheetId
            conflict.seasonSheetId = identity.seasonSheetId
            conflict.runId = identity.runId
        }
        let run = RunRecord(rowIndex: 42, date: "Fri, 2-Jan", meet: "Il Lido", run: "Soft Sand", identity: shared ? identity : nil)
        conflict.attachConflict(reason: "stale_revision", message: "The sheet changed.",
                                state: SheetState(runs: [run], sheetRevision: "rev-fresh", spreadsheetId: shared ? "book" : nil))
        context.insert(conflict)
        try context.save()
        let clock = GateClock()
        let engine = makeEngine(container: container, transport: StubTransport([]), clock: clock)
        await clock.arm(2)

        let id = conflict.id
        let results = await withTaskGroup(of: Result<UUID?, any Error>.self) { group in
            for _ in 0..<2 {
                group.addTask {
                    do { return .success(try await engine.resolveConflict(id: id, action: .merge)) }
                    catch { return .failure(error) }
                }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }

        let failures = results.compactMap { result -> SyncEngineError? in
            if case .failure(let error) = result { return error as? SyncEngineError }
            return nil
        }
        #expect(failures == [.conflictNotFound])
        #expect(try fetchAllPending(container).count == 2)
    }
}
