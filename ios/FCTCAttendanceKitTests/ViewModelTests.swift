//
//  ViewModelTests.swift
//  FCTCAttendanceKitTests
//
//  U4: pure UI-state rules plus protocol-level action routing.
//

import Foundation
import Testing

@testable import FCTCAttendanceKit

@Suite("U4 view models")
@MainActor
struct ViewModelTests {

    private let now = Date(timeIntervalSince1970: 1_786_665_600) // 2026-08-14 UTC

    @Test("Home counts this week and only outstanding submissions")
    func homeCounts() {
        let viewModel = HomeViewModel(engine: ViewModelSyncClient())
        viewModel.update(
            runs: [
                run(row: 1, dayOffset: -1),
                run(row: 2, dayOffset: 0),
                run(row: 3, dayOffset: 10),
            ],
            submissions: [
                submission(status: .queued),
                submission(status: .done),
            ],
            now: now,
            calendar: utcCalendar
        )

        #expect(viewModel.thisWeekCount == 2)
        #expect(viewModel.unsyncedCount == 1)
        #expect(viewModel.todayRun?.rowIndex == 2)
    }

    @Test("Home shows first-load progress only when the cache is empty")
    func homeInitialLoading() async {
        let client = ViewModelSyncClient(suspendRefresh: true)
        let viewModel = HomeViewModel(engine: client)
        let refresh = Task { await viewModel.refresh(hasCachedState: false) }
        await client.waitUntilRefreshRequested()

        #expect(viewModel.isInitialLoading)

        await client.resumeRefresh()
        await refresh.value
        #expect(!viewModel.isInitialLoading)

        let cachedClient = ViewModelSyncClient(suspendRefresh: true)
        let cachedViewModel = HomeViewModel(engine: cachedClient)
        let cachedRefresh = Task { await cachedViewModel.refresh(hasCachedState: true) }
        await cachedClient.waitUntilRefreshRequested()

        #expect(!cachedViewModel.isInitialLoading)

        await cachedClient.resumeRefresh()
        await cachedRefresh.value
    }

    @Test("Home keeps an empty-cache load failure distinct from no runs")
    func homeInitialLoadFailure() async {
        let client = ViewModelSyncClient(refreshFailures: 1)
        let viewModel = HomeViewModel(engine: client)

        await viewModel.refresh(hasCachedState: false)

        #expect(viewModel.initialLoadFailed)
        #expect(viewModel.syncBanner?.kind == .offline)

        await viewModel.retry(hasCachedState: false)

        #expect(!viewModel.initialLoadFailed)
        #expect(viewModel.syncBanner == nil)
    }

    @Test("Sync events become human and actionable home banners")
    func homeSyncBanners() async {
        let client = ViewModelSyncClient()
        let viewModel = HomeViewModel(engine: client)
        viewModel.update(
            runs: [],
            submissions: [submission(status: .conflict)]
        )
        #expect(viewModel.conflictCount == 1)

        await client.emit(.parked(id: UUID(), message: UserFacingError.busy))
        await waitUntil { viewModel.syncBanner?.kind == .parked }
        #expect(viewModel.syncBanner?.message == UserFacingError.busy)

        await client.emit(.parked(id: UUID(), message: UserFacingError.offline))
        await waitUntil { viewModel.syncBanner?.kind == .offline }
        #expect(viewModel.syncBanner?.message == UserFacingError.offline)

        await client.emit(.authenticationRequired(id: UUID()))
        await waitUntil { viewModel.syncBanner?.kind == .authentication }
        #expect(viewModel.syncBanner?.message == "The shared secret was rejected. Open Settings and scan a new setup code.")
    }

    @Test("Run picker selects the latest unrecorded run at or before now")
    func defaultRunSkipsRecorded() {
        let runs = [
            run(row: 1, dayOffset: -2),
            run(row: 2, dayOffset: -1, attendees: ["Col"]),
            run(row: 3, dayOffset: 0),
            run(row: 4, dayOffset: 1),
        ]

        let selected = RunPickerViewModel.defaultRun(
            from: runs,
            now: now,
            calendar: utcCalendar
        )

        #expect(selected?.rowIndex == 3)
    }

    @Test("Run picker falls back to the latest recorded run when none are pending")
    func defaultRunRecordedFallback() {
        let runs = [
            run(row: 1, dayOffset: -2, attendees: ["Aaron"]),
            run(row: 2, dayOffset: 0, plusOnes: 1),
            run(row: 3, dayOffset: 1),
        ]

        let selected = RunPickerViewModel.defaultRun(
            from: runs,
            now: now,
            calendar: utcCalendar
        )

        #expect(selected?.rowIndex == 2)
    }

    @Test("Run picker produces Today, This Week, Later, and Past sections")
    func runSections() {
        let viewModel = RunPickerViewModel(engine: ViewModelSyncClient())
        viewModel.update(
            runs: [
                run(row: 1, dayOffset: -1),
                run(row: 2, dayOffset: 0),
                run(row: 3, dayOffset: 1),
                run(row: 4, dayOffset: 10),
            ],
            now: now,
            calendar: utcCalendar
        )

        #expect(viewModel.sections.map(\.kind) == [.today, .thisWeek, .later, .past])
    }

    @Test("Run creation routes requests and exposes failures")
    func runCreation() async throws {
        let request = AddRunRequest(
            date: "Sat, 15-Aug",
            meet: "Coast",
            run: "Hills",
            approxKm: 9.2
        )
        let client = ViewModelSyncClient()
        let viewModel = RunPickerViewModel(engine: client)

        try await viewModel.addRun(request)

        #expect(await client.addedRuns == [request])
        #expect(!viewModel.isAddingRun)

        let failingClient = ViewModelSyncClient(addRunFailures: 1)
        let failingViewModel = RunPickerViewModel(engine: failingClient)
        await #expect(throws: ViewModelTestError.offline) {
            try await failingViewModel.addRun(request)
        }
        #expect(failingViewModel.errorMessage == "The app could not update the sheet. Try again from the outbox.")
        #expect(!failingViewModel.isAddingRun)
    }

    @Test("Checklist confirm stays disabled until the draft differs from the sheet")
    func checklistGating() {
        let baseline = run(
            row: 42,
            dayOffset: 0,
            approxKm: 7.1,
            actualKm: 7.1,
            attendees: ["Col"],
            plusOnes: 1
        )
        let viewModel = ChecklistViewModel(
            run: baseline,
            roster: ["Aaron", "Col"],
            engine: ViewModelSyncClient()
        )

        #expect(!viewModel.canConfirm)
        viewModel.toggleMember("Aaron")
        #expect(viewModel.canConfirm)
        viewModel.toggleMember("Aaron")
        #expect(!viewModel.canConfirm)
        viewModel.actualKmText = "8.2"
        #expect(viewModel.canConfirm)
    }

    @Test("Clearing actual kilometres keeps the sheet value unchanged")
    func clearingActualKmIsNoOpinion() {
        let baseline = run(row: 42, dayOffset: 0, actualKm: 7.1)
        let viewModel = ChecklistViewModel(
            run: baseline,
            roster: ["Col"],
            engine: ViewModelSyncClient()
        )

        viewModel.actualKmText = ""

        #expect(viewModel.draft.actualKm == nil)
        #expect(!viewModel.draftDiffersFromSheet)
    }

    @Test("Checklist diff summaries distinguish merge and overwrite")
    func checklistDiffSummary() {
        let baseline = run(
            row: 42,
            dayOffset: 0,
            attendees: ["Aaron", "Col"]
        )
        var draft = AttendanceDraft(
            rowIndex: 42,
            expectedDate: baseline.date,
            expectedRun: baseline.run,
            checks: ["Col": .manual, "Dan B": .ocr, "Toby": .voice],
            plusOnesOverride: 0,
            baseRevision: "rev-1"
        )
        draft.actualKm = baseline.actualKm
        let viewModel = ChecklistViewModel(
            run: baseline,
            roster: ["Aaron", "Col", "Dan B", "Toby"],
            draft: draft,
            engine: ViewModelSyncClient()
        )

        #expect(viewModel.diffSummary(for: .merge) == AttendanceDiff(added: 2, removed: 0))
        #expect(viewModel.diffSummary(for: .overwrite) == AttendanceDiff(added: 2, removed: 1))
        #expect(viewModel.diffSummary(for: .overwrite).summary == "Will add 2, remove 1")
    }

    @Test("Checklist quick-add promotes a guest and checks the new member")
    func quickAddPromotesGuest() async throws {
        let client = ViewModelSyncClient()
        let baseline = run(row: 42, dayOffset: 0)
        var draft = AttendanceDraft(
            rowIndex: 42,
            expectedDate: baseline.date,
            expectedRun: baseline.run,
            guests: [Guest(name: "Priya")]
        )
        draft.plusOnesOverride = nil
        let viewModel = ChecklistViewModel(
            run: baseline,
            roster: ["Aaron"],
            draft: draft,
            engine: client
        )

        viewModel.quickAddName = "Priya"
        try await viewModel.commitQuickAdd()

        #expect(viewModel.roster == ["Aaron", "Priya"])
        #expect(viewModel.draft.guestNames.isEmpty)
        #expect(viewModel.draft.isChecked("Priya"))
        #expect(viewModel.draft.baseRevision == "rev-2")
        #expect(await client.addedMembers == ["Priya"])
    }

    @Test("Quick-add rollback keeps a failed member retryable")
    func quickAddFailureCanRetry() async throws {
        let client = ViewModelSyncClient(addMemberFailures: 1)
        let baseline = run(row: 42, dayOffset: 0)
        let draft = AttendanceDraft(
            rowIndex: 42,
            expectedDate: baseline.date,
            expectedRun: baseline.run,
            guests: [Guest(name: "Priya")]
        )
        let viewModel = ChecklistViewModel(
            run: baseline,
            roster: ["Aaron"],
            draft: draft,
            engine: client
        )
        viewModel.quickAddName = "Priya"

        await #expect(throws: ViewModelTestError.offline) {
            try await viewModel.commitQuickAdd()
        }

        #expect(viewModel.roster == ["Aaron"])
        #expect(!viewModel.draft.isChecked("Priya"))
        #expect(viewModel.draft.guestNames == ["Priya"])
        #expect(viewModel.quickAddName == "Priya")

        try await viewModel.commitQuickAdd()
        #expect(viewModel.roster == ["Aaron", "Priya"])
        #expect(await client.addedMembers == ["Priya", "Priya"])
    }

    @Test("Quick-add searches retained guest history")
    func quickAddSearchesGuestHistory() {
        let baseline = run(row: 42, dayOffset: 0)
        let viewModel = ChecklistViewModel(
            run: baseline,
            roster: ["Aaron"],
            guestHistory: ["Priya", "priya", "Toby"],
            engine: ViewModelSyncClient()
        )

        viewModel.quickAddName = "pri"

        #expect(viewModel.matchingGuests.map(\.name) == ["Priya"])
    }

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

    @Test("Settings load, save, QR import, and refresh use their protocol seams")
    func settingsActions() async throws {
        let persistence = MemoryConfigPersistence(
            config: AppConfig(
                endpoint: URL(string: "https://example.test/exec"),
                secret: "old-secret",
                deviceName: "Colin's iPhone"
            )
        )
        let client = ViewModelSyncClient()
        let viewModel = SettingsViewModel(persistence: persistence, engine: client)

        #expect(viewModel.endpoint == "https://example.test/exec")
        let saved = try viewModel.importAndSaveSetupCode(
            """
            {"endpoint":"https://new.example/exec","secret":"new-secret","deviceName":"Run phone"}
            """
        )
        try await viewModel.refreshRoster()

        #expect(saved.secret == "new-secret")
        #expect(try persistence.load() == saved)
        #expect(await client.refreshCount == 1)
    }

    @Test("Scanned config persistence sends the secret only to its secure seam")
    func configPersistenceSeparatesSecret() throws {
        let suite = "FCTCAttendanceKitTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let secretStore = MemorySecretStore()
        let persistence = UserDefaultsAppConfigPersistence(
            defaults: defaults,
            secretStore: secretStore
        )
        let viewModel = SettingsViewModel(
            persistence: persistence,
            engine: ViewModelSyncClient()
        )

        let config = try viewModel.importAndSaveSetupCode(
            """
            {"endpoint":"https://example.test/exec","secret":"qr-secret-not-real","deviceName":"Run phone"}
            """
        )

        #expect(try persistence.load() == config)
        #expect(secretStore.value == "qr-secret-not-real")
        #expect(!defaults.dictionaryRepresentation().values.contains {
            ($0 as? String) == "qr-secret-not-real"
        })
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }

    private func run(
        row: Int,
        dayOffset: Int,
        approxKm: Double? = 7.1,
        actualKm: Double? = nil,
        attendees: [String] = [],
        plusOnes: Int = 0
    ) -> RunSnapshot {
        let date = utcCalendar.date(byAdding: .day, value: dayOffset, to: now)!
        return RunSnapshot(
            rowIndex: row,
            date: "Fri, 14-Aug",
            scheduledAt: date,
            meet: "Il Lido",
            run: "Soft Sand",
            approxKm: approxKm,
            actualKm: actualKm,
            attendees: attendees,
            plusOnes: plusOnes,
            cachedRevision: "rev-1"
        )
    }

    private func submission(status: SubmissionStatus) -> PendingSubmissionSnapshot {
        PendingSubmissionSnapshot(
            id: UUID(),
            rowIndex: 42,
            expectedDate: "Fri, 14-Aug",
            expectedRun: "Soft Sand",
            attendees: ["Col"],
            plusOnes: 0,
            actualKm: 7.1,
            mode: .merge,
            status: status,
            createdAt: now
        )
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<30 where !condition() { await Task.yield() }
    }
}

private struct ResolutionCall: Hashable, Sendable {
    let id: UUID
    let action: ConflictResolutionAction
}

private enum ViewModelTestError: LocalizedError, Equatable, Sendable {
    case offline

    var errorDescription: String? { "Offline" }
}

private actor ViewModelSyncClient: SyncEngineClient {
    nonisolated var events: AsyncStream<SyncEvent> { eventBroadcaster.stream() }
    private nonisolated let eventBroadcaster = SyncEventBroadcaster()
    private(set) var addedMembers: [String] = []
    private(set) var addedRuns: [AddRunRequest] = []
    private(set) var resolutions: [ResolutionCall] = []
    private(set) var refreshCount = 0
    private var addMemberFailures: Int
    private var addRunFailures: Int
    private var resolutionFailures: Int
    private let suspendRefresh: Bool
    private var refreshFailures: Int
    private var refreshContinuation: CheckedContinuation<SheetState, Never>?

    init(
        addMemberFailures: Int = 0,
        addRunFailures: Int = 0,
        resolutionFailures: Int = 0,
        suspendRefresh: Bool = false,
        refreshFailures: Int = 0
    ) {
        self.addMemberFailures = addMemberFailures
        self.addRunFailures = addRunFailures
        self.resolutionFailures = resolutionFailures
        self.suspendRefresh = suspendRefresh
        self.refreshFailures = refreshFailures
    }

    func refreshState() async throws -> SheetState {
        refreshCount += 1
        if refreshFailures > 0 {
            refreshFailures -= 1
            throw SheetAPIError.network("Offline")
        }
        if suspendRefresh {
            return await withCheckedContinuation { refreshContinuation = $0 }
        }
        return SheetState(sheetRevision: "rev-1")
    }

    func waitUntilRefreshRequested() async {
        while refreshCount == 0 { await Task.yield() }
    }

    func resumeRefresh() {
        refreshContinuation?.resume(returning: SheetState(sheetRevision: "rev-1"))
        refreshContinuation = nil
    }

    func enqueue(_ submission: AttendanceSubmission) async throws -> UUID { UUID() }

    func enqueue(
        draft: AttendanceDraft,
        mode: SubmissionMode,
        deviceName: String?
    ) async throws -> UUID { UUID() }

    func drain() async {}

    func addMember(name: String) async throws -> AddMemberResult {
        addedMembers.append(name)
        if addMemberFailures > 0 {
            addMemberFailures -= 1
            throw ViewModelTestError.offline
        }
        return AddMemberResult(
            roster: [RosterEntry(name: name, colIndex: 1)],
            sheetRevision: "rev-2"
        )
    }

    func addRun(_ request: AddRunRequest) async throws -> AddRunResult {
        addedRuns.append(request)
        if addRunFailures > 0 {
            addRunFailures -= 1
            throw ViewModelTestError.offline
        }
        return AddRunResult(runs: [], sheetRevision: "rev-2")
    }

    func resolveConflict(
        id: UUID,
        action: ConflictResolutionAction
    ) async throws -> UUID? {
        resolutions.append(ResolutionCall(id: id, action: action))
        if resolutionFailures > 0 {
            resolutionFailures -= 1
            throw ViewModelTestError.offline
        }
        return action == .discard ? nil : UUID()
    }

    func emit(_ event: SyncEvent) {
        eventBroadcaster.yield(event)
    }
}

private final class MemoryConfigPersistence: AppConfigPersisting, @unchecked Sendable {
    private var config: AppConfig

    init(config: AppConfig) {
        self.config = config
    }

    func load() throws -> AppConfig { config }

    func save(_ config: AppConfig) throws {
        self.config = config
    }
}

private final class MemorySecretStore: SecretStoring, @unchecked Sendable {
    var value: String?

    func readSecret() throws -> String? { value }

    func writeSecret(_ value: String) throws {
        self.value = value
    }
}
