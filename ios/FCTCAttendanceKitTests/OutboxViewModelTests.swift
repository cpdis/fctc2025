//
//  OutboxViewModelTests.swift
//  FCTCAttendanceKitTests
//
//  U4: outbox filtering, conflict resolution routing and sync activity.
//

import Foundation
import Testing

@testable import FCTCAttendanceKit

extension ViewModelTests {
    @Test("Outbox filters retained history on isOutstanding")
    func outboxFiltering() {
        let viewModel = OutboxViewModel(engine: ViewModelSyncClient())
        let queued = submission(status: .queued)
        let conflict = submission(status: .conflict)
        let done = submission(status: .done)

        #expect(viewModel.outstanding(from: [queued, conflict, done]).map(\.id) == [queued.id, conflict.id])
        #expect(viewModel.canRetry([conflict]) == false)
        #expect(viewModel.canRetry([conflict, queued]))
    }

    @Test("Conflict diff compares every writable field")
    func outboxConflictDiff() {
        let viewModel = OutboxViewModel(engine: ViewModelSyncClient())
        var conflict = submission(status: .conflict)
        conflict.attendees = ["Col", "Toby"]
        conflict.plusOnes = 2
        conflict.actualKm = 8.2
        conflict.conflictState = SheetState(
            runs: [
                RunRecord(
                    rowIndex: conflict.rowIndex,
                    date: conflict.expectedDate,
                    meet: "Il Lido",
                    run: conflict.expectedRun,
                    actualKm: 7.1,
                    attendees: ["Aaron", "Col"],
                    plusOnes: 1
                ),
            ]
        )

        let diff = viewModel.conflictDiff(for: conflict)

        #expect(diff.attendance == AttendanceDiff(added: 1, removed: 1))
        #expect(diff.localPlusOnes == 2)
        #expect(diff.serverPlusOnes == 1)
        #expect(diff.plusOnesChanged)
        #expect(diff.localActualKm == 8.2)
        #expect(diff.serverActualKm == 7.1)
        #expect(diff.actualKmChanged)
    }

    @Test("Conflict merge and overwrite choices route through re-enqueue")
    func conflictResolutionRoutes() async throws {
        let client = ViewModelSyncClient()
        let viewModel = OutboxViewModel(engine: client)
        let first = UUID()
        let second = UUID()

        try await viewModel.resolve(id: first, action: .merge)
        try await viewModel.resolve(id: second, action: .overwrite)

        #expect(await client.resolutions == [
            ResolutionCall(id: first, action: .merge),
            ResolutionCall(id: second, action: .overwrite),
        ])
    }

    @Test("Conflict resolution keeps failures visible for retry")
    func conflictResolutionFailure() async {
        let client = ViewModelSyncClient(resolutionFailures: 1)
        let viewModel = OutboxViewModel(engine: client)

        await #expect(throws: ViewModelTestError.offline) {
            try await viewModel.resolve(id: UUID(), action: .merge)
        }

        #expect(viewModel.errorMessage == "The app could not update the sheet. Try again from the outbox.")
        #expect(!viewModel.isResolving)
    }

    @Test("The view-model test client broadcasts events")
    func testClientEventBroadcast() async {
        let client = ViewModelSyncClient()
        var first = client.events.makeAsyncIterator()
        var second = client.events.makeAsyncIterator()
        let event = SyncEvent.queued(id: UUID())

        await client.emit(event)

        #expect(await first.next() == event)
        #expect(await second.next() == event)
    }

    @Test("Outbox and Home show sync activity only while the engine drains")
    func syncActivityTracksDrains() async throws {
        let client = ViewModelSyncClient()
        let outbox = OutboxViewModel(engine: client)
        let home = HomeViewModel(engine: client)
        #expect(!outbox.isSyncing)
        #expect(!home.isSyncing)

        await client.emit(.syncActivity(isActive: true))
        #expect(await waitUntil { outbox.isSyncing && home.isSyncing })
        #expect(outbox.isSyncing)
        #expect(home.isSyncing)

        await client.emit(.syncActivity(isActive: false))
        #expect(await waitUntil { !outbox.isSyncing && !home.isSyncing })
        #expect(!outbox.isSyncing)
        #expect(!home.isSyncing)

        // A replaced connection must not inherit the old engine's spinner.
        await client.emit(.syncActivity(isActive: true))
        try #require(await waitUntil { outbox.isSyncing && home.isSyncing })
        outbox.replaceEngine(ViewModelSyncClient())
        home.replaceEngine(ViewModelSyncClient())
        #expect(!outbox.isSyncing)
        #expect(!home.isSyncing)
    }
}
