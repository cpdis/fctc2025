import Foundation
import Testing
@testable import FCTCAttendanceKit

@Suite("Home refresh binding")
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
        home.replaceEngine(ControlledHomeSyncClient())
        #expect(home.activeState == nil)
        #expect(home.syncBanner == nil)
        #expect(!home.initialLoadFailed)
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
