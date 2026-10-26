//
//  DrainOwnershipTests.swift
//  FCTCAttendanceKitTests
//
//  One drain owner per store, the structured re-drain, and the drain loop's
//  guards (CC-1, CC-2, CC-8, PLAT-NEW-1).
//

import Foundation
import SwiftData
import Testing

@testable import FCTCAttendanceKit

@Suite("Drain ownership", .timeLimit(.minutes(1)))
struct DrainOwnershipTests {
    private static let written = json("{\"ok\":true,\"written\":39,\"sheetRevision\":\"rev-2\"}")

    /// CC-2: a Settings swap makes a second engine over the same on-disk
    /// store while the first is mid-request. Before the fix nothing linked
    /// them: the second re-queued the first one's in-flight row and sent it
    /// again (two requests for one submission).
    @Test("A replacement engine waits for the old drain: one request, one done row")
    func replacementWaitsForPredecessor() async throws {
        let store = try DiskStore()
        let transport = SuspendingTransport()
        let old = ownershipEngine(store.container, transport: transport)
        let id = try await old.enqueue(.fixture)
        let first = Task { await old.drain() }
        await transport.waitUntilRequested()

        let replacement = ownershipEngine(store.container, transport: transport, replacing: old)
        let second = Task { await replacement.drain() }
        // The replacement's first drain retires the old engine and waits.
        while !(await old.isRetired) { await Task.yield() }

        await transport.resume(returning: Self.written)
        await first.value
        await second.value

        #expect(await transport.requestCount == 1)
        let rows = try ModelContext(store.container).fetch(FetchDescriptor<PendingSubmission>())
        #expect(rows.count == 1)
        let row = try #require(rows.first { $0.id == id })
        #expect(row.status == .done)
        #expect(row.conflictReason == nil)
        #expect(row.conflictStateData == nil)
    }

    @Test("A retired engine never drains again")
    func retiredEngineStops() async throws {
        let store = try DiskStore()
        let transport = StubTransport([.response(Self.written)])
        let engine = ownershipEngine(store.container, transport: transport)
        let id = try await engine.enqueue(.fixture)

        await engine.quiesce()
        await engine.drain()

        #expect(await transport.requestCount == 0)
        #expect(try pendingRow(store.container, id: id)?.status == .queued)
    }

    /// CC-1 (TEST-6): a drain requested mid-drain runs inside the running
    /// call. Before the fix it ran later in a `Task { }` from the `defer`, so
    /// the awaited call returned with the second row unsent and the stream
    /// saw two separate activity brackets.
    @Test("A drain requested during a drain runs again inside the same call")
    func drainRequestedDuringDrainRunsAgain() async throws {
        let store = try DiskStore()
        let transport = SuspendingTransport()
        let engine = ownershipEngine(store.container, transport: transport)
        _ = try await engine.enqueue(.fixture)
        var events = engine.events.makeAsyncIterator()

        let drain = Task { await engine.drain() }
        await transport.waitUntilRequested()
        let secondId = try await engine.enqueue(.fixture)
        // Mid-drain, this only asks the running drain for another pass.
        await engine.drain()
        await transport.resume(returning: Self.written)
        await transport.waitUntilRequested()
        await transport.resume(returning: Self.written)
        await drain.value

        #expect(try pendingRow(store.container, id: secondId)?.status == .done)
        while await engine.isDraining { await Task.yield() }
        engine.eventBroadcaster.yield(.serviceFailed(message: "probe"))
        var activity: [Bool] = []
        while let event = await events.next() {
            if case .syncActivity(let isActive) = event { activity.append(isActive) }
            if event == .serviceFailed(message: "probe") { break }
        }
        #expect(activity == [true, false])
        #expect(await transport.requestCount == 2)
    }

    /// CC-8: an expired background task cancels the drain; it stops before
    /// the next row. Before the fix the loop never checked, so both rows sent.
    @Test("A cancelled drain leaves its rows queued")
    func cancelledDrainStops() async throws {
        let store = try DiskStore()
        let transport = StubTransport([.response(Self.written), .response(Self.written)])
        let engine = ownershipEngine(store.container, transport: transport)
        let first = try await engine.enqueue(.fixture)
        let second = try await engine.enqueue(.fixture)

        await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await engine.drain()
        }.value

        #expect(await transport.requestCount == 0)
        #expect(try pendingRow(store.container, id: first)?.status == .queued)
        #expect(try pendingRow(store.container, id: second)?.status == .queued)
    }

    /// PLAT-NEW-1: with no endpoint (settings unreadable) every saved row
    /// looked foreign. Before the fix the drain parked it for identity review.
    @Test("A drain without an endpoint leaves saved rows alone")
    func drainWithoutEndpointDoesNotPark() async throws {
        let store = try DiskStore()
        let context = ModelContext(store.container)
        let row = PendingSubmission(
            rowIndex: 42, expectedDate: "Fri, 2-Jan", expectedRun: "Soft Sand", attendees: ["Col"], status: .queued
        )
        row.endpointIdentity = configuredAPI.endpoint?.absoluteString
        context.insert(row)
        try context.save()
        let transport = StubTransport()
        let engine = SyncEngine(
            modelContainer: store.container,
            api: SheetAPI(config: AppConfig(), transport: transport),
            clock: ImmediateSyncClock(),
            automaticallyDrains: false
        )

        await engine.drain()

        let saved = try #require(try pendingRow(store.container, id: row.id))
        #expect(saved.status == .queued)
        #expect(saved.conflictReason == nil)
        #expect(await transport.requestCount == 0)
    }
}

/// A throwaway on-disk store. Two engines share one container the way the
/// app's runtime engine and a replacement do; files go when the test ends.
private final class DiskStore {
    let container: ModelContainer
    private let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory
            .appending(path: "DrainOwnershipTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        container = try ModelContainer(
            for: AttendanceSchema.schema,
            configurations: ModelConfiguration(
                "DrainOwnershipTests",
                schema: AttendanceSchema.schema,
                url: folder.appending(path: "outbox.store")
            )
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }
}

private func ownershipEngine(
    _ container: ModelContainer,
    transport: any HTTPTransport,
    replacing predecessor: (any SyncEngineClient)? = nil
) -> SyncEngine {
    SyncEngine(
        modelContainer: container,
        api: SheetAPI(config: configuredAPI, transport: transport),
        clock: ImmediateSyncClock(),
        automaticallyDrains: false,
        replacing: predecessor
    )
}

private func pendingRow(_ container: ModelContainer, id: UUID) throws -> PendingSubmission? {
    try ModelContext(container).fetch(FetchDescriptor<PendingSubmission>()).first { $0.id == id }
}
