import Foundation
import Testing
@testable import FCTCAttendanceKit

@Suite("Home refresh binding", .timeLimit(.minutes(1)))
@MainActor
struct HomeRefreshBindingTests {
    @Test("Old engine success or failure cannot replace the current workbook", arguments: [false, true])
    func replacedEngine(oldFails: Bool) async {
        let old = ControlledHomeSyncClient(), current = ControlledHomeSyncClient()
        let home = HomeViewModel(engine: old)
        let oldRefresh = Task { await home.refresh(hasCachedState: false) }
        await old.waitForRequests(1)
        home.replaceEngine(current)
        #expect(!home.isInitialLoading)
        let refresh = Task { await home.refresh(hasCachedState: false) }
        await current.waitForRequests(1)
        await current.complete(1, with: .success(state("current", season: 26)))
        await refresh.value
        await old.complete(1, with: oldFails ? .failure(SheetAPIError.network("old failure")) : .success(state("old", season: 25)))
        await oldRefresh.value
        #expect(home.activeState?.spreadsheetId == "current")
        #expect(home.activeState?.seasonSheetId == 26)
        #expect(home.syncBanner == nil)
        #expect(!home.initialLoadFailed)
        #expect(!home.isInitialLoading)
    }

    @Test("Replacing the engine clears the previous workbook and banner immediately")
    func clearPriorConnection() async {
        let old = ControlledHomeSyncClient()
        let home = HomeViewModel(engine: old)
        let refresh = Task { await home.refresh() }
        await old.waitForRequests(1)
        await old.complete(1, with: .success(state("old", season: 25)))
        await refresh.value
        old.emit(.serviceFailed(message: "Old connection"))
        await receiveEvents()
        #expect(home.syncBanner != nil)
        #expect(home.lastSyncedAt != nil)
        home.replaceEngine(ControlledHomeSyncClient())
        #expect(home.activeState == nil)
        #expect(home.syncBanner == nil)
        #expect(!home.initialLoadFailed)
        // The old sheet's refresh time says nothing about the new sheet.
        #expect(home.syncStatus == .idle(updatedAt: nil))
    }

    @Test("A refresh reads as checking, then idle with the time it landed")
    func refreshStatus() async throws {
        let client = ControlledHomeSyncClient()
        let home = HomeViewModel(engine: client)
        #expect(home.syncStatus == .idle(updatedAt: nil))
        let refresh = Task { await home.refresh() }
        await client.waitForRequests(1)
        #expect(home.syncStatus == .checking)
        #expect(home.syncStatus.isWorking)
        let before = Date.now
        await client.complete(1, with: .success(state("sheet", season: 26)))
        await refresh.value
        let updatedAt = try #require(home.lastSyncedAt)
        #expect(updatedAt >= before && updatedAt <= .now)
        #expect(home.syncStatus == .idle(updatedAt: updatedAt))
        #expect(!home.syncStatus.isWorking)
        #expect(!home.syncFailed)
    }

    @Test("A failed refresh keeps the last good time and shows its banner")
    func failedRefreshStatus() async {
        let client = ControlledHomeSyncClient()
        let home = HomeViewModel(engine: client)
        let first = Task { await home.refresh() }
        await client.waitForRequests(1)
        await client.complete(1, with: .success(state("sheet", season: 26)))
        await first.value
        let updatedAt = home.lastSyncedAt
        let second = Task { await home.refresh() }
        await client.waitForRequests(2)
        await client.complete(2, with: .failure(SheetAPIError.network("offline")))
        await second.value
        #expect(home.syncStatus == .idle(updatedAt: updatedAt))
        #expect(home.syncBanner?.kind == .offline)
        // The old time stays true, but it must not read as this sync's success.
        #expect(home.syncFailed)
    }

    @Test("A sent change is a success with its own time; a parked one is a failure")
    func sendOutcome() async {
        let client = ControlledHomeSyncClient()
        let home = HomeViewModel(engine: client)
        let before = Date.now
        client.emit(.written(id: UUID()))
        await receiveEvents()
        #expect(!home.syncFailed)
        #expect(home.lastSyncedAt.map { $0 >= before } == true)
        let sentAt = home.lastSyncedAt
        client.emit(.parked(id: UUID(), message: UserFacingError.offline))
        await receiveEvents()
        #expect(home.syncFailed)
        #expect(home.lastSyncedAt == sentAt)
    }

    @Test("Any engine read of the sheet moves the sync time, not only Runs' refresh")
    func engineReadTime() async {
        let client = ControlledHomeSyncClient()
        let home = HomeViewModel(engine: client)
        // The read a shared write makes after its confirmation.
        client.emit(.rosterRefreshed(state("sheet", season: 26)))
        await receiveEvents()
        #expect(home.lastSyncedAt != nil)
        #expect(home.syncStatus == .idle(updatedAt: home.lastSyncedAt))
    }

    @Test("A drain reads as sending only while changes wait", arguments: [0, 2])
    func sendingStatus(unsent: Int) async {
        let client = ControlledHomeSyncClient()
        let home = HomeViewModel(engine: client)
        home.update(runs: [], submissions: [], pendingGuestChanges: unsent)
        client.emit(.syncActivity(isActive: true))
        await receiveEvents()
        #expect(home.syncStatus == (unsent > 0 ? .sending(unsent) : .idle(updatedAt: nil)))
        client.emit(.syncActivity(isActive: false))
        await receiveEvents()
        #expect(home.syncStatus == .idle(updatedAt: nil))
    }

    @Test("Sending wins over checking while a drain and a refresh overlap")
    func sendingBeforeChecking() async {
        let client = ControlledHomeSyncClient()
        let home = HomeViewModel(engine: client)
        // Back on Runs after Confirm: the refresh on appear and the send overlap.
        let refresh = Task { await home.refresh() }
        await client.waitForRequests(1)
        home.update(runs: [], submissions: [], pendingGuestChanges: 1)
        client.emit(.syncActivity(isActive: true))
        await receiveEvents()
        #expect(home.syncStatus == .sending(1))
        // The send lands first; the read is still out.
        home.update(runs: [], submissions: [])
        client.emit(.syncActivity(isActive: false))
        await receiveEvents()
        #expect(home.syncStatus == .checking)
        await client.complete(1, with: .success(state("sheet", season: 26)))
        await refresh.value
        #expect(home.syncStatus == .idle(updatedAt: home.lastSyncedAt))
    }

    @Test("Only the newest refresh owns the loading state and result",
          arguments: [false, true], [false, true])
    func overlappingRefresh(olderFinishesLast: Bool, olderFails: Bool) async {
        let client = ControlledHomeSyncClient()
        let home = HomeViewModel(engine: client)
        let first = Task { await home.refresh(hasCachedState: false) }
        await client.waitForRequests(1)
        let second = Task { await home.refresh(hasCachedState: false) }
        await client.waitForRequests(2)
        let oldResult: Result<SheetState, any Error> = olderFails ? .failure(SheetAPIError.network("old")) : .success(state("older", season: 25))
        if olderFinishesLast {
            await client.complete(2, with: .success(state("newest", season: 26)))
            await second.value
            await client.complete(1, with: oldResult)
            await first.value
        } else {
            await client.complete(1, with: oldResult)
            await first.value
            #expect(home.isInitialLoading)
            #expect(home.syncStatus == .checking)
            #expect(home.activeState == nil)
            #expect(home.syncBanner == nil)
            #expect(!home.initialLoadFailed)
            await client.complete(2, with: .success(state("newest", season: 26)))
            await second.value
        }
        #expect(home.activeState?.spreadsheetId == "newest")
        #expect(home.syncBanner == nil)
        #expect(!home.initialLoadFailed)
        #expect(!home.isInitialLoading)
    }

    @Test("The old engine cannot clear loading while the replacement is pending")
    func oldLoadingCleanup() async {
        let old = ControlledHomeSyncClient(), current = ControlledHomeSyncClient()
        let home = HomeViewModel(engine: old)
        let first = Task { await home.refresh(hasCachedState: false) }
        await old.waitForRequests(1)
        home.replaceEngine(current)
        let second = Task { await home.refresh(hasCachedState: false) }
        await current.waitForRequests(1)
        await old.complete(1, with: .success(state("old", season: 25)))
        await first.value
        #expect(home.isInitialLoading)
        #expect(home.activeState == nil)
        await current.complete(1, with: .success(state("current", season: 26)))
        await second.value
        #expect(!home.isInitialLoading)
    }

    @Test("Queued and later events from the replaced engine cannot change current banners")
    func oldEvents() async {
        let old = ControlledHomeSyncClient(), current = ControlledHomeSyncClient()
        let home = HomeViewModel(engine: old)
        old.emit(.serviceFailed(message: "Queued old event"))
        home.replaceEngine(current)
        current.emit(.written(id: UUID()))
        await receiveEvents()
        #expect(home.syncBanner?.kind == .success)
        old.emit(.authenticationRequired(id: UUID()))
        await receiveEvents()
        #expect(home.syncBanner?.kind == .success)
    }

    @Test("A proven unsent refresh uses the offline banner")
    func unsentBanner() async {
        let client = ControlledHomeSyncClient()
        let home = HomeViewModel(engine: client)
        let refresh = Task { await home.refresh(hasCachedState: false) }
        await client.waitForRequests(1)
        await client.complete(1, with: .failure(SheetAPIError.requestNotSent("Connection refused")))
        await refresh.value
        #expect(home.syncBanner?.kind == .offline)
        #expect(home.initialLoadFailed)
    }

    private func state(_ workbook: String, season: Int) -> SheetState {
        var state = SheetState(sheetRevision: "\(workbook)-revision")
        state.spreadsheetId = workbook
        state.seasonSheetId = season
        return state
    }

    private func receiveEvents() async {
        for _ in 0..<30 { await Task.yield() }
    }
}

/// Controlled completions exercise actual suspension order without wall-clock sleeps.
private actor ControlledHomeSyncClient: SyncEngineClient {
    private var requestCount = 0
    private var continuations: [Int: CheckedContinuation<SheetState, any Error>] = [:]
    private nonisolated let broadcaster = SyncEventBroadcaster()
    nonisolated var events: AsyncStream<SyncEvent> { broadcaster.stream() }
    nonisolated func emit(_ event: SyncEvent) { broadcaster.yield(event) }

    func refreshState() async throws -> SheetState {
        requestCount += 1
        let id = requestCount
        return try await withCheckedThrowingContinuation { continuations[id] = $0 }
    }

    func waitForRequests(_ count: Int) async {
        while requestCount < count { await Task.yield() }
    }

    func complete(_ id: Int, with result: Result<SheetState, any Error>) {
        continuations.removeValue(forKey: id)?.resume(with: result)
    }

    func enqueue(_ submission: AttendanceSubmission) async throws -> UUID { throw SheetAPIError.notImplemented }
    func enqueue(draft: AttendanceDraft, mode: SubmissionMode, deviceName: String?) async throws -> UUID { throw SheetAPIError.notImplemented }
    func drain() async {}
    func addMember(name: String) async throws -> AddMemberResult { throw SheetAPIError.notImplemented }
    func addRun(_ request: AddRunRequest) async throws -> AddRunResult { throw SheetAPIError.notImplemented }
    func resolveConflict(id: UUID, action: ConflictResolutionAction) async throws -> UUID? { throw SheetAPIError.notImplemented }
}
