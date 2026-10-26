//
//  ViewModelTests.swift
//  FCTCAttendanceKitTests
//
//  U4: pure UI-state rules plus protocol-level action routing.
//

import Foundation
import Testing

@testable import FCTCAttendanceKit

@Suite("U4 view models", .timeLimit(.minutes(1)))
@MainActor
struct ViewModelTests {

    let now = Date(timeIntervalSince1970: 1_786_665_600) // 2026-08-14 UTC

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

    @Test("A failed refresh says what the phone shows, and Retry Now refreshes again")
    func homeRefreshFailureRetry() async {
        let client = ViewModelSyncClient(refreshFailures: 1)
        let viewModel = HomeViewModel(engine: client)

        await viewModel.refresh(hasCachedState: true)

        #expect(viewModel.syncBanner?.kind == .offline)
        #expect(viewModel.syncBanner?.message == UserFacingError.refreshOffline)
        #expect(viewModel.refreshFailed)

        await viewModel.retry(hasCachedState: true)

        #expect(await client.refreshCount == 2)
        #expect(viewModel.syncBanner == nil)
        #expect(!viewModel.refreshFailed)
    }

    /// Switching tab or pushing a screen cancels the view's refresh task, and
    /// URLSession reports that as a transport error. It is not "offline".
    @Test("A refresh cancelled with its view leaves no banner")
    func homeCancelledRefresh() async {
        let client = ViewModelSyncClient(cancellableRefresh: true)
        let viewModel = HomeViewModel(engine: client)

        let refresh = Task { await viewModel.refresh(hasCachedState: true) }
        await client.waitUntilRefreshRequested()
        refresh.cancel()
        await refresh.value

        #expect(viewModel.syncBanner == nil)
        #expect(!viewModel.refreshFailed)
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
        #expect(await waitUntil { viewModel.syncBanner?.kind == .parked })
        #expect(viewModel.syncBanner?.message == UserFacingError.busy)

        await client.emit(.parked(id: UUID(), message: UserFacingError.offline))
        #expect(await waitUntil { viewModel.syncBanner?.kind == .offline })
        #expect(viewModel.syncBanner?.message == UserFacingError.offline)

        await client.emit(.authenticationRequired(id: UUID()))
        #expect(await waitUntil { viewModel.syncBanner?.kind == .authentication })
        #expect(viewModel.syncBanner?.message == "The shared secret was rejected. Open Settings and scan a new setup code.")
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

    @Test("A malformed distance blocks Confirm and names itself")
    func malformedActualKmBlocksConfirmAndNamesItself() async {
        let baseline = run(row: 42, dayOffset: 0, actualKm: 7.1)
        let viewModel = ChecklistViewModel(
            run: baseline,
            roster: ["Col", "Dan"],
            engine: ViewModelSyncClient()
        )
        viewModel.toggleMember("Dan")
        #expect(viewModel.canConfirm)

        viewModel.actualKmText = "8..2"

        #expect(viewModel.distanceIsMalformed)
        #expect(viewModel.draft.actualKm == nil)
        #expect(viewModel.canConfirm == false)
        await #expect(throws: ChecklistError.malformedDistance) {
            try await viewModel.confirm(mode: .merge)
        }

        viewModel.actualKmText = "8.2"
        #expect(viewModel.distanceIsMalformed == false)
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

    @Test("A prefilled approx distance alone does not enable Confirm")
    func prefilledApproxIsNotADiff() {
        let baseline = run(row: 42, dayOffset: 0, approxKm: 7.1, actualKm: nil)
        let viewModel = ChecklistViewModel(run: baseline, roster: ["Col"], engine: ViewModelSyncClient())

        #expect(viewModel.actualKmText == DistanceText.format(7.1))
        #expect(!viewModel.draftDiffersFromSheet)
        #expect(!viewModel.canConfirm)

        viewModel.toggleMember("Col")
        #expect(viewModel.draftDiffersFromSheet)
        #expect(viewModel.canConfirm)
        // The untouched prefilled value still rides along as the actual distance.
        #expect(viewModel.draft.actualKm == 7.1)
    }

    @Test("A typed distance differs from the prefilled approx only when it changes it")
    func typedDistanceAgainstPrefilledApprox() {
        let baseline = run(row: 42, dayOffset: 0, approxKm: 7.1, actualKm: nil)
        let viewModel = ChecklistViewModel(run: baseline, roster: ["Col"], engine: ViewModelSyncClient())

        viewModel.actualKmText = "7.5"
        #expect(viewModel.draftDiffersFromSheet)
        viewModel.actualKmText = "7.1"
        #expect(!viewModel.draftDiffersFromSheet)
        viewModel.actualKmText = ""
        #expect(!viewModel.draftDiffersFromSheet)
    }

    @Test("A recorded actual distance is the prefilled value, not the approx")
    func typedDistanceAgainstRecordedActual() {
        let baseline = run(row: 42, dayOffset: 0, approxKm: 7.1, actualKm: 8.0)
        let viewModel = ChecklistViewModel(run: baseline, roster: ["Col"], engine: ViewModelSyncClient())

        #expect(!viewModel.draftDiffersFromSheet)
        viewModel.actualKmText = "8.2"
        #expect(viewModel.draftDiffersFromSheet)
        // The approx km differs from the recorded actual, so it is a real change.
        viewModel.actualKmText = "7.1"
        #expect(viewModel.draftDiffersFromSheet)
        viewModel.actualKmText = ""
        #expect(!viewModel.draftDiffersFromSheet)
    }

    @Test("A typed distance on a run with no distance at all is a change")
    func typedDistanceWithoutAnyDistance() {
        let baseline = run(row: 42, dayOffset: 0, approxKm: nil, actualKm: nil)
        let viewModel = ChecklistViewModel(run: baseline, roster: ["Col"], engine: ViewModelSyncClient())

        #expect(!viewModel.draftDiffersFromSheet)
        viewModel.actualKmText = "5"
        #expect(viewModel.draftDiffersFromSheet)
        #expect(viewModel.canConfirm)
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

    @Test("Quick-add creates a member without erasing guest evidence")
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
        #expect(viewModel.draft.guestNames == ["Priya"])
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

    /// UI-1: the triage awaits each "Add as new person" in turn, through the
    /// closure both triage sheets now pass. The old dictation closure returned
    /// before the add ran and shared the quick-add field, so one name was lost.
    @Test("Two new people from one triage both reach the roster")
    func triageAddsTwoNewPeople() async throws {
        let client = ViewModelSyncClient()
        let viewModel = ChecklistViewModel(run: run(row: 42, dayOffset: 0), roster: ["Aaron"], engine: client)
        let addPerson: (String) async throws -> Void = viewModel.addProposedPerson
        for name in ["Priya", "Sam"] { try await addPerson(name) }

        #expect(viewModel.roster == ["Aaron", "Priya", "Sam"])
        #expect(await client.addedMembers == ["Priya", "Sam"])
        // Unchecked, so the apply step checks them with the proposal's provenance.
        #expect(!viewModel.draft.isChecked("Priya") && !viewModel.draft.isChecked("Sam"))
        #expect(viewModel.quickAddName.isEmpty)
    }

    /// CC-13: a failed add undoes only itself. A guest added while the
    /// request was in flight is the organiser's edit and stays.
    @Test("A failed quick add keeps edits made during the request")
    func failedQuickAddKeepsConcurrentEdits() async throws {
        let client = ViewModelSyncClient(addMemberFailures: 1, suspendAddMember: true)
        let viewModel = ChecklistViewModel(run: run(row: 42, dayOffset: 0), roster: ["Aaron"], engine: client)
        let add = Task { try await viewModel.commitQuickAdd(name: "Sam") }
        await client.waitUntilAddMemberRequested()

        viewModel.addGuest(name: "Rene")
        viewModel.toggleMember("Aaron")
        await client.resumeAddMember()
        await #expect(throws: ViewModelTestError.offline) { try await add.value }

        #expect(viewModel.roster == ["Aaron"])
        #expect(!viewModel.draft.isChecked("Sam"))
        #expect(viewModel.draft.isChecked("Aaron"))
        #expect(viewModel.draft.guestNames == ["Rene"])
    }

    /// CC-4: the busy flag is checked before the first await, so a second tap
    /// that lands before the first request finishes does nothing.
    @Test("A double tap resolves a conflict once")
    func doubleTapResolvesOnce() async throws {
        let client = ViewModelSyncClient()
        let viewModel = OutboxViewModel(engine: client)
        let id = UUID()
        let first = Task { try await viewModel.resolve(id: id, action: .discard) }
        let second = Task { try await viewModel.resolve(id: id, action: .discard) }

        _ = try await first.value
        await #expect(throws: CancellationError.self) { try await second.value }
        #expect(await client.resolutions == [ResolutionCall(id: id, action: .discard)])
    }

    @Test("A double tap adds a run once")
    func doubleTapAddsRunOnce() async throws {
        let request = AddRunRequest(date: "Sat, 15-Aug", meet: "Coast", run: "Hills", approxKm: 9.2)
        let client = ViewModelSyncClient()
        let viewModel = RunPickerViewModel(engine: client)
        let first = Task { try await viewModel.addRun(request) }
        let second = Task { try await viewModel.addRun(request) }

        try await first.value
        await #expect(throws: CancellationError.self) { try await second.value }
        #expect(await client.addedRuns == [request])
    }

    /// CA-16: a refused Confirm or Save says why instead of failing silently.
    @Test("Refused confirm and save set a message")
    func refusalsSetMessages() async throws {
        // The sheet already holds the distance, so the seeded draft is unchanged.
        // A run with only an approx km is unchanged too: the prefilled km is not a diff.
        let checklist = ChecklistViewModel(run: run(row: 42, dayOffset: 0, actualKm: 7.1), roster: ["Aaron"], engine: ViewModelSyncClient())
        await #expect(throws: ChecklistError.unchangedDraft) { try await checklist.confirm(mode: .merge) }
        #expect(checklist.errorMessage == ChecklistError.unchangedDraft.errorDescription)

        let settings = SettingsViewModel(
            persistence: MemoryConfigPersistence(config: AppConfig(endpoint: nil, secret: "", deviceName: nil)),
            engine: ViewModelSyncClient()
        )
        settings.endpoint = "http://not-secure.example"
        #expect(throws: SettingsError.invalidEndpoint) { try settings.save() }
        #expect(settings.errorMessage == SettingsError.invalidEndpoint.errorDescription)
    }

    @Test("Shared guest labels refresh without replacing stable identities")
    func sharedGuestLabels() {
        let guest = Guest(name: "Rene")
        let baseline = run(row: 42, dayOffset: 0)
        let draft = AttendanceDraft(rowIndex: 42, expectedDate: baseline.date, expectedRun: baseline.run, guests: [guest])
        let model = ChecklistViewModel(run: baseline, roster: [], draft: draft, engine: ViewModelSyncClient())
        model.updateSharedGuests([SharedGuest(guestId: guest.id.uuidString, displayName: "René", confirmedRuns: 11)])
        #expect(model.draft.guests.first?.id == guest.id)
        #expect(model.draft.guests.first?.name == "René")
    }


    var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }

    func run(
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

    func submission(status: SubmissionStatus) -> PendingSubmissionSnapshot {
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

    /// Yields up to 30 times; returns whether the condition became true.
    func waitUntil(_ condition: @escaping @MainActor () -> Bool) async -> Bool {
        for _ in 0..<30 where !condition() { await Task.yield() }
        return condition()
    }
}
