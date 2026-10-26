//
//  SyncEngineDrainTests.swift
//  FCTCAttendanceKitTests
//
//  Sync engine: event fan-out, drain activity, retries and rejected secrets.
//

import Foundation
import SwiftData
import Testing

@testable import FCTCAttendanceKit

extension SyncEngineTests {

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

    @Test("A drain reports its activity, and a late subscriber still sees it",
          .timeLimit(.minutes(1)))
    func drainActivity() async throws {
        let container = try makeContainer()
        let transport = SuspendingTransport()
        let engine = makeEngine(container: container, transport: transport)
        _ = try await engine.enqueue(.fixture)
        var early = engine.events.makeAsyncIterator()

        let drain = Task { await engine.drain() }
        await transport.waitUntilRequested()
        #expect(await early.next() == .syncActivity(isActive: true))

        // A screen opened mid-drain must still learn that work is running.
        var late = engine.events.makeAsyncIterator()
        #expect(await late.next() == .syncActivity(isActive: true))

        await transport.resume(
            returning: json("{\"ok\":true,\"written\":39,\"sheetRevision\":\"rev-2\"}")
        )
        await drain.value

        var finished = false
        while let event = await early.next() {
            if event == .syncActivity(isActive: false) { finished = true; break }
        }
        #expect(finished)

        // Once idle, a new subscriber receives no stale activity: the first
        // event it sees is the probe sent after it subscribed.
        var idle = engine.events.makeAsyncIterator()
        engine.eventBroadcaster.yield(.serviceFailed(message: "probe"))
        #expect(await idle.next() == .serviceFailed(message: "probe"))
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

    @Test("Busy retry exhaustion stays distinct from offline")
    func busyRetryExhaustion() async throws {
        let container = try makeContainer()
        let response = json("{\"ok\":false,\"error\":\"busy\",\"message\":\"Locked\"}")
        let transport = StubTransport(Array(repeating: .response(response), count: 5))
        let engine = makeEngine(container: container, transport: transport)
        var events = engine.events.makeAsyncIterator()
        let id = try await engine.enqueue(.fixture)

        await engine.drain()

        #expect(await events.nextIgnoringActivity() == .queued(id: id))
        #expect(
            await events.nextIgnoringActivity() == .parked(
                id: id,
                message: "The sheet is busy with another update. Wait a moment and try again."
            )
        )
        #expect(try fetchPending(container, id: id)?.attemptCount == 5)
    }

    @Test("A rejected secret emits a Settings route instead of a raw error")
    func badSecretRoutesToSettings() async throws {
        let container = try makeContainer()
        let transport = StubTransport([
            .response(json("{\"ok\":false,\"error\":\"bad_secret\",\"message\":\"Nope\"}")),
        ])
        let engine = makeEngine(container: container, transport: transport)
        var events = engine.events.makeAsyncIterator()
        let id = try await engine.enqueue(.fixture)

        await engine.drain()

        _ = await events.nextIgnoringActivity()
        #expect(await events.nextIgnoringActivity() == .authenticationRequired(id: id))
        #expect(try fetchPending(container, id: id)?.status == .queued)
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
}
