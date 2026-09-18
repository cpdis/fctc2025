import Foundation
import Testing
@testable import FCTCAttendanceKit

@Suite("Shared guest presentation")
@MainActor
struct SharedGuestViewModelTests {
    static let reneID = "11111111-1111-4111-8111-111111111111"
    static let identity = RunIdentity(spreadsheetId: "book", seasonSheetId: 26, runId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")

    @Test("Reopening a saved run preserves shared identity and its unnamed remainder")
    func restoredRun() {
        let run = RunSnapshot(rowIndex: 42, date: "Fri, 11-Sep", scheduledAt: nil, meet: "Beach", run: "Sand", actualKm: 7,
            plusOnes: 2, cachedRevision: "rev", runIdentity: Self.identity, endpointIdentity: "test", namedGuestIds: [Self.reneID], unnamedGuests: 1)
        let model = ChecklistViewModel(run: run, roster: [], engine: UnimplementedSyncEngine())
        #expect(model.draft.runIdentity == Self.identity)
        #expect(model.draft.namedGuestIds == [Self.reneID])
        #expect(model.draft.unnamedGuests == 1)
        #expect(!model.draftDiffersFromSheet)
    }

    @Test("Replacing a named guest requires review even when headcount is unchanged")
    func replacementIsAChange() {
        let run = RunSnapshot(rowIndex: 42, date: "Fri, 11-Sep", scheduledAt: nil, meet: "Beach", run: "Sand", actualKm: 7,
            plusOnes: 1, cachedRevision: "rev", runIdentity: Self.identity, endpointIdentity: "test", namedGuestIds: [Self.reneID], unnamedGuests: 0)
        let draft = AttendanceDraft(rowIndex: 42, expectedDate: run.date, expectedRun: run.run,
            guests: [Guest(name: "Toby")], actualKm: 7, baseRevision: "rev", runIdentity: Self.identity, endpointIdentity: "test", unnamedGuests: 0)
        let model = ChecklistViewModel(run: run, roster: [], draft: draft, engine: UnimplementedSyncEngine())
        #expect(model.draft.plusOnes == run.plusOnes)
        #expect(model.draftDiffersFromSheet)
    }
}

extension SharedGuestViewModelTests {
    private var rene: SharedGuest { SharedGuest(guestId: Self.reneID, displayName: "Rene", confirmedRuns: 10) }
    private func model(plus: Int = 1, unnamed: Int = 1, named: [String] = [], client: any SyncEngineClient = UnimplementedSyncEngine()) -> ChecklistViewModel {
        let run = RunSnapshot(rowIndex: 42, date: "Fri, 11-Sep", scheduledAt: nil, meet: "Beach", run: "Sand", actualKm: 7,
            plusOnes: plus, cachedRevision: "rev", runIdentity: Self.identity, endpointIdentity: "test", namedGuestIds: named, unnamedGuests: unnamed)
        let model = ChecklistViewModel(run: run, roster: ["Col"], engine: client)
        model.updateSharedGuests([rene])
        return model
    }

    @Test("Naming a saved unnamed slot keeps the count and includes both sides of the diff")
    func unnamedAssignment() {
        let model = model()
        model.selectGuest(rene, namingUnnamed: true)
        #expect(model.draft.plusOnes == 1)
        #expect(model.draft.unnamedGuests == 0)
        #expect(model.draftDiffersFromSheet)
        #expect(model.guestDiff(for: .overwrite).added == ["Rene"])
        #expect(model.guestDiff(for: .overwrite).unnamedBefore == 1)
        #expect(model.guestDiff(for: .overwrite).unnamedAfter == 0)
        model.selectGuest(rene, namingUnnamed: true)
        #expect(model.draft.plusOnes == 1)
    }

    @Test("Replacement keeps one guest slot, removal removes it exactly once")
    func replacementAndRemoval() throws {
        let model = model(unnamed: 0, named: [Self.reneID])
        let toby = SharedGuest(guestId: UUID().uuidString, displayName: "Toby", confirmedRuns: 9)
        model.updateSharedGuests([rene, toby])
        model.selectGuest(toby, replacing: try #require(UUID(uuidString: Self.reneID)))
        #expect(model.draft.plusOnes == 1)
        #expect(model.guestDiff(for: .overwrite).removed == ["Rene"])
        #expect(model.guestDiff(for: .overwrite).added == ["Toby"])
        model.removeGuest(id: try #require(toby.draftGuest).id)
        model.removeGuest(id: try #require(toby.draftGuest).id)
        #expect(model.draft.plusOnes == 0)
    }

    @Test("Returning guests stay unchecked on a new run")
    func returningUnchecked() {
        let model = model(plus: 0, unnamed: 0)
        #expect(model.sharedGuests.count == 1)
        #expect(model.draft.guests.isEmpty)
    }

    @Test("Voice guest labels require an explicit shared identity selection")
    func proposedNamesRequireSelection() {
        let model = model(plus: 0, unnamed: 0)
        let set = DraftProposalSet(guestNames: ["Rene"], provenance: .voice)
        model.applyProposals(checks: [], from: set)
        #expect(model.unresolvedGuestNames == ["Rene"])
        #expect(model.draft.guests.isEmpty)
        #expect(!model.canConfirm)
        model.selectGuest(rene)
        model.resolveProposedName("Rene")
        #expect(model.draft.namedGuestIds == [Self.reneID])
        #expect(model.canConfirm)
    }

    @Test("Save then promote checks the attendance receipt before previewing eleven runs")
    func saveThenPromote() async {
        let client = GuestPresentationClient()
        let checklist = model(plus: 0, unnamed: 0, client: client)
        checklist.selectGuest(rene)
        let promotion = GuestPromotionViewModel(guest: rene, engine: client)
        await promotion.prepare(checklist: checklist)
        #expect(promotion.runMessage == "Run saved.")
        #expect(promotion.preview?.confirmedRuns == 11)
        #expect(await client.previewCalls == 1)
    }

    @Test("Queued run remains pending and never starts promotion")
    func pendingRunPreventsPromotion() async {
        let client = GuestPresentationClient(committed: false)
        let checklist = model(plus: 0, unnamed: 0, client: client)
        checklist.selectGuest(rene)
        let promotion = GuestPromotionViewModel(guest: rene, engine: client)
        await promotion.prepare(checklist: checklist)
        #expect(promotion.waitingForRun)
        #expect(promotion.preview == nil)
        #expect(await client.previewCalls == 0)
        await promotion.prepare(checklist: checklist)
        #expect(await client.enqueueCalls == 1)
    }

    @Test("Promotion failure preserves the separately saved run outcome")
    func promotionFailureAfterSave() async {
        let client = GuestPresentationClient(previewFails: true)
        let checklist = model(plus: 0, unnamed: 0, client: client)
        checklist.selectGuest(rene)
        let promotion = GuestPromotionViewModel(guest: rene, engine: client)
        await promotion.prepare(checklist: checklist)
        #expect(promotion.runMessage == "Run saved.")
        #expect(promotion.promotionMessage == "Promotion has not completed. The run is saved.")
        #expect(!promotion.completed)
    }

    @Test("Pending promotion checks the existing receipt without committing twice")
    func pendingPromotionDoesNotReplay() async {
        let client = GuestPresentationClient(operationPhase: .checking)
        let promotion = GuestPromotionViewModel(guest: rene, engine: client)
        await promotion.prepare(checklist: nil)
        await promotion.commit()
        await promotion.commit()
        #expect(!promotion.completed)
        #expect(await client.commitCalls == 1)
        #expect(promotion.operationId != nil)
    }

    @Test("Cache scoping does not mix equal row numbers across workbooks and seasons")
    func scopedRuns() {
        let current = model().run
        var old = current; old.runIdentity?.seasonSheetId = 25
        var other = current; other.runIdentity?.spreadsheetId = "other"
        var endpoint = current; endpoint.endpointIdentity = "another-endpoint"
        let state = SheetState(spreadsheetId: "book", seasonSheetId: 26)
        #expect(RunCacheScope.runs([current, old, other, endpoint], endpoint: "test", state: state) == [current])
    }

    @Test("Recovery ignores an older season response after a newer selection")
    func recoverySeasonRace() async {
        let client = GuestPresentationClient()
        let recovery = GuestRecoveryViewModel(engine: client)
        await recovery.load()
        await client.delaySeasons()
        let old = Task { await recovery.selectSeason(25) }
        await client.waitForSeason(25)
        let current = Task { await recovery.selectSeason(26) }
        await client.waitForSeason(26)
        await client.releaseSeason(26)
        await current.value
        #expect(recovery.selectedSeasonState?.seasonSheetId == 26)
        await client.releaseSeason(25)
        await old.value
        #expect(recovery.selectedSeasonState?.seasonSheetId == 26)
    }

    @Test("Promoted guest review uses the stored mapping and preserves other guest slots")
    func promotedReview() throws {
        let id = UUID()
        let submission = PendingSubmissionSnapshot(id: id, rowIndex: 42, expectedDate: "Fri, 11-Sep", expectedRun: "Sand", attendees: ["Col"], guestNames: ["Rene"], plusOnes: 2, actualKm: 7,
            mode: .merge, status: .conflict, createdAt: .now, runIdentity: Self.identity, namedGuestIds: [Self.reneID], unnamedGuests: 1)
        let record = RunRecord(rowIndex: 42, date: "Fri, 11-Sep", meet: "Beach", run: "Sand", identity: Self.identity)
        let state = SheetState(roster: [RosterEntry(name: "Rene D", colIndex: 6), RosterEntry(name: "Col", colIndex: 7)], runs: [record], sheetRevision: "latest", spreadsheetId: "book", seasonSheetId: 26,
            guests: [SharedGuest(guestId: Self.reneID, displayName: "Rene", status: "promoted", memberName: "Rene D")])
        let review = try PromotedGuestReview(submission: submission, state: state, endpointIdentity: "test")
        #expect(review.draft.attendees == ["Col", "Rene D"])
        #expect(review.draft.guests.isEmpty)
        #expect(review.draft.plusOnes == 1)
        #expect(review.draft.attendees.count + review.draft.plusOnes == 3)
        #expect(review.draft.baseRevision == "latest")
    }
}

private actor GuestPresentationClient: SyncEngineClient {
    let committed: Bool
    let previewFails: Bool
    let operationPhase: GuestOperationPhase
    private let submissionId = UUID()
    private let operationId = UUID()
    private(set) var previewCalls = 0
    private(set) var enqueueCalls = 0
    private(set) var commitCalls = 0
    private var delayedSeasons = false
    private var seasonContinuations: [Int: CheckedContinuation<Void, Never>] = [:]
    func delaySeasons() { delayedSeasons = true }
    func waitForSeason(_ id: Int) async { while seasonContinuations[id] == nil { await Task.yield() } }
    func releaseSeason(_ id: Int) { seasonContinuations.removeValue(forKey: id)?.resume() }
    init(committed: Bool = true, previewFails: Bool = false, operationPhase: GuestOperationPhase = .completed) {
        self.committed = committed; self.previewFails = previewFails; self.operationPhase = operationPhase
    }
    nonisolated var events: AsyncStream<SyncEvent> { AsyncStream { $0.finish() } }
    func refreshState() async throws -> SheetState { state() }
    func refreshState(seasonSheetId: Int?) async throws -> SheetState {
        if delayedSeasons, let id = seasonSheetId { await withCheckedContinuation { seasonContinuations[id] = $0 } }
        var value = state()
        value.seasonSheetId = seasonSheetId ?? 26
        return value
    }
    private func state() -> SheetState {
        let identity = RunIdentity(spreadsheetId: "book", seasonSheetId: 26, runId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")
        return SheetState(runs: [RunRecord(rowIndex: 42, date: "Fri, 11-Sep", meet: "Beach", run: "Sand", actualKm: 7, plusOnes: 1,
            identity: identity, namedGuestIds: ["11111111-1111-4111-8111-111111111111"], unnamedGuests: 0)],
            seasonYear: 2026, sheetRevision: "saved", spreadsheetId: "book", seasonSheetId: 26,
            guests: [SharedGuest(guestId: "11111111-1111-4111-8111-111111111111", displayName: "Rene", confirmedRuns: 11)],
            supportedSeasons: [SupportedSeason(seasonSheetId: 25, seasonYear: 2025), SupportedSeason(seasonSheetId: 26, seasonYear: 2026)])
    }
    func enqueue(_ submission: AttendanceSubmission) async throws -> UUID { enqueueCalls += 1; return submissionId }
    func enqueue(draft: AttendanceDraft, mode: SubmissionMode, deviceName: String?) async throws -> UUID { enqueueCalls += 1; return submissionId }
    func pendingSubmission(id: UUID) async throws -> PendingSubmissionSnapshot? {
        PendingSubmissionSnapshot(id: id, rowIndex: 42, expectedDate: "Fri, 11-Sep", expectedRun: "Sand", attendees: [], plusOnes: 1, actualKm: 7,
            mode: .overwrite, status: committed ? .done : .queued, createdAt: .now, outcome: committed ? .committed : nil)
    }
    func drain() async {}
    func addMember(name: String) async throws -> AddMemberResult { throw SheetAPIError.notImplemented }
    func addRun(_ request: AddRunRequest) async throws -> AddRunResult { throw SheetAPIError.notImplemented }
    func resolveConflict(id: UUID, action: ConflictResolutionAction) async throws -> UUID? { nil }
    func previewPromotion(guestId: String, memberName: String, targetMode: PromotionTargetMode) async throws -> PromotionPreview {
        previewCalls += 1
        if previewFails { throw SheetAPIError.badPayload(message: "Correct allocation first.") }
        return PromotionPreview(guestId: guestId, memberName: memberName, confirmedRuns: 11, previewToken: "preview", targetMode: targetMode, seasons: [], changes: [])
    }
    func commitPromotion(_ preview: PromotionPreview) async throws -> UUID { commitCalls += 1; return operationId }
    func guestOperation(id: UUID) async throws -> GuestOperationSnapshot? { GuestOperationSnapshot(id: id, action: "commitPromotion", phase: operationPhase) }
}
