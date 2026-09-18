import Foundation
import Testing
@testable import FCTCAttendanceKit

@Suite("Guest name editor")
@MainActor
struct GuestNameViewModelTests {
    @Test("A confirmed correction updates the selected name without saving attendance or losing edits")
    func immediateCorrection() async throws {
        let client = NameEditorClient()
        let guest = await client.guest
        let model = GuestNameViewModel(guest: guest, engine: client)
        await model.load()
        model.name = " Adam X "
        await model.save()
        let saved = try #require(model.savedGuest)
        #expect(saved.displayName == "Adam X")
        #expect(model.finished)
        #expect(await client.renameCalls == 1)
        #expect(await client.attendanceCalls == 0)

        let run = RunSnapshot(rowIndex: 42, date: "Fri, 18-Sep", scheduledAt: nil, meet: "Beach", run: "Sand", actualKm: 7,
            plusOnes: 2, cachedRevision: "rev", runIdentity: RunIdentity(spreadsheetId: "book", seasonSheetId: 26, runId: UUID().uuidString),
            endpointIdentity: "test", namedGuestIds: [guest.guestId], unnamedGuests: 1)
        let checklist = ChecklistViewModel(run: run, roster: ["Col"], engine: client)
        checklist.updateSharedGuests([guest])
        #expect(!checklist.draftDiffersFromSheet)
        checklist.updateSharedGuests([saved])
        #expect(checklist.draft.guests.first?.name == "Adam X")
        #expect(!checklist.draftDiffersFromSheet)
        checklist.draft.unnamedGuests = 4
        checklist.draft.actualKm = 8.2
        checklist.updateSharedGuests([saved])
        #expect(checklist.draft.unnamedGuests == 4)
        #expect(checklist.draft.actualKm == 8.2)
        #expect(checklist.draft.namedGuestIds == [guest.guestId])
    }

    @Test("A stale correction presents both names and retries against the reviewed guest")
    func conflictReview() async throws {
        let client = NameEditorClient(phase: .conflict)
        let id = await client.operationId
        let model = GuestNameViewModel(operationId: id, engine: client)
        await model.load()
        #expect(model.needsReview)
        #expect(model.name == "Adam X")
        #expect(model.guest?.displayName == "Rene")
        #expect(model.canSave)
        await model.save()
        #expect(model.finished)
        #expect(model.savedGuest?.displayName == "Adam X")
        #expect(await client.replacementBase == model.guest?.revision)
        #expect(await client.replacementCalls == 1)
        #expect(await client.renameCalls == 0)
    }

    @Test("Keeping the saved name closes the warning without another rename")
    func keepSavedName() async {
        let client = NameEditorClient(phase: .rejected)
        let model = GuestNameViewModel(operationId: await client.operationId, engine: client)
        await model.load()
        await model.keepSavedName()
        #expect(model.finished)
        #expect(model.savedGuest == nil)
        #expect(await client.discardCalls == 1)
        #expect(await client.renameCalls == 0)
        #expect(await client.replacementCalls == 0)
    }

    @Test("Unknown outcomes can be checked but cannot be overwritten or discarded")
    func pendingCorrection() async {
        let client = NameEditorClient(phase: .checking)
        let model = GuestNameViewModel(operationId: await client.operationId, engine: client)
        await model.load()
        #expect(model.isPending)
        #expect(!model.canSave)
        await model.save()
        await model.keepSavedName()
        await model.check()
        #expect(!model.finished)
        #expect(await client.renameCalls == 0)
        #expect(await client.replacementCalls == 0)
        #expect(await client.discardCalls == 0)
        await client.confirmPending()
        await model.observeSavedChange()
        #expect(model.finished)
        #expect(model.savedGuest?.displayName == "Adam X")
    }

    @Test("Completion during a history read survives success or failure", arguments: [false, true])
    func completionDuringHistoryRead(historyFails: Bool) async {
        let client = NameEditorClient(phase: .checking)
        let model = GuestNameViewModel(operationId: await client.operationId, engine: client)
        await client.suspendNextHistory()
        let loading = Task { await model.load() }
        await client.waitForSuspendedHistory()

        await client.confirmPending()
        await model.observeSavedChange()
        await model.observeSavedChange()
        #expect(model.isWorking)
        #expect(!model.finished)
        #expect(await client.operationReads == 1)

        await client.finishSuspendedHistory(failing: historyFails)
        await loading.value

        #expect(model.finished)
        #expect(!model.isWorking)
        #expect(model.savedGuest?.displayName == "Adam X")
        #expect(model.name == "Adam X")
        #expect(model.errorMessage == nil)
        // Both notifications share one follow-up read; completion needs no history request.
        #expect(await client.operationReads == 2)
        #expect(await client.historyCalls == 1)
        #expect(await client.renameCalls == 0)
        #expect(await client.replacementCalls == 0)
        #expect(await client.discardCalls == 0)
        #expect(await client.attendanceCalls == 0)
        await model.observeSavedChange()
        #expect(await client.operationReads == 2)
    }

    @Test("A second stale response preserves the typed correction and refreshes the saved name")
    func repeatedConflict() async {
        let client = NameEditorClient(conflictOnSave: true)
        let model = GuestNameViewModel(guest: await client.guest, engine: client)
        await model.load()
        model.name = "Adam X"
        await model.save()
        #expect(!model.finished)
        #expect(model.needsReview)
        #expect(model.name == "Adam X")
        #expect(model.guest?.displayName == "Adam")
        #expect(model.canSave)
    }
}

/// A focused client models save outcomes, while GuestRenameReviewTests exercise
/// the real durable queue and revision guards against a transport.
private actor NameEditorClient: SyncEngineClient {
    var guest = SharedGuest(guestId: "11111111-1111-4111-8111-111111111111", displayName: "Rene", revision: 2, confirmedRuns: 11)
    let operationId = UUID()
    var phase: GuestOperationPhase
    let conflictOnSave: Bool
    var proposed = "Adam X"
    var renameCalls = 0
    var replacementCalls = 0
    var discardCalls = 0
    var attendanceCalls = 0
    var replacementBase: Int?
    var operationReads = 0
    var historyCalls = 0
    private var shouldSuspendNextHistory = false
    private var historyContinuation: CheckedContinuation<Void, any Error>?
    private var historyStartedContinuation: CheckedContinuation<Void, Never>?

    init(phase: GuestOperationPhase = .completed, conflictOnSave: Bool = false) {
        self.phase = phase; self.conflictOnSave = conflictOnSave
    }
    func sharedGuests() async throws -> [SharedGuest] { [guest] }
    func guestHistory(id: String) async throws -> GuestHistory {
        historyCalls += 1
        let history = GuestHistory(guest: guest, guestRevision: "revision", attendance: [])
        if shouldSuspendNextHistory {
            shouldSuspendNextHistory = false
            try await withCheckedThrowingContinuation { continuation in
                historyContinuation = continuation
                historyStartedContinuation?.resume()
                historyStartedContinuation = nil
            }
        }
        return history
    }
    func suspendNextHistory() { shouldSuspendNextHistory = true }
    func waitForSuspendedHistory() async {
        guard historyContinuation == nil else { return }
        await withCheckedContinuation { historyStartedContinuation = $0 }
    }
    func finishSuspendedHistory(failing: Bool) {
        if failing { historyContinuation?.resume(throwing: SheetAPIError.notImplemented) }
        else { historyContinuation?.resume() }
        historyContinuation = nil
    }
    func renameGuest(_ guest: SharedGuest, name: String) async throws -> UUID {
        renameCalls += 1; proposed = name
        if conflictOnSave {
            phase = .conflict; self.guest.displayName = "Adam"; self.guest.revision += 1
        } else { confirmPending() }
        return operationId
    }
    func replaceGuestRename(id: UUID, guest: SharedGuest, name: String) async throws -> UUID {
        replacementCalls += 1; replacementBase = guest.revision; proposed = name
        confirmPending(); return operationId
    }
    func discardGuestRename(id: UUID) async throws { discardCalls += 1; phase = .superseded }
    func confirmPending() { phase = .completed; guest.displayName = proposed; guest.revision += 1 }
    func guestOperation(id: UUID) async throws -> GuestOperationSnapshot? {
        operationReads += 1
        return GuestOperationSnapshot(id: id, action: "renameGuest", phase: phase,
            guestId: guest.guestId, proposedName: proposed)
    }
    nonisolated var events: AsyncStream<SyncEvent> { AsyncStream { $0.finish() } }
    func refreshState() async throws -> SheetState { throw SheetAPIError.notImplemented }
    func enqueue(_ submission: AttendanceSubmission) async throws -> UUID { attendanceCalls += 1; return UUID() }
    func enqueue(draft: AttendanceDraft, mode: SubmissionMode, deviceName: String?) async throws -> UUID { attendanceCalls += 1; return UUID() }
    func drain() async {}
    func addMember(name: String) async throws -> AddMemberResult { throw SheetAPIError.notImplemented }
    func addRun(_ request: AddRunRequest) async throws -> AddRunResult { throw SheetAPIError.notImplemented }
    func resolveConflict(id: UUID, action: ConflictResolutionAction) async throws -> UUID? { nil }
}
