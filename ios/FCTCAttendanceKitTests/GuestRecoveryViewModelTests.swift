import Foundation
import Testing
@testable import FCTCAttendanceKit

@Suite("Guest recovery presentation") @MainActor
struct GuestRecoveryViewModelTests {
    @Test("Unverified local evidence cannot preview an import")
    func requiresVerification() async throws {
        let client = RecoveryPresentationClient()
        let model = GuestRecoveryViewModel(engine: client)
        await model.load(); await model.selectSeason(26)
        let candidate = try #require(model.candidates.first)
        await model.review(candidate: candidate, guestId: "guest", runId: "run", attendanceVerified: false)
        #expect(model.preview == nil)
        #expect(await client.previewCalls == 0)
    }

    @Test("Confirmed import refreshes shared totals and cannot be imported again after reopening")
    func importRefreshes() async throws {
        let client = RecoveryPresentationClient()
        let model = GuestRecoveryViewModel(engine: client)
        await model.load(); await model.selectSeason(26)
        let candidate = try #require(model.candidates.first)
        await model.review(candidate: candidate, guestId: "guest", runId: "run", attendanceVerified: true)
        #expect(model.preview != nil)
        await model.importReviewed(candidateId: candidate.id)
        #expect(model.candidates.first?.status == .imported)
        #expect(model.guests.first?.confirmedRuns == 11)
        let reopened = GuestRecoveryViewModel(engine: client)
        await reopened.load(); await reopened.selectSeason(26)
        await reopened.review(candidate: try #require(reopened.candidates.first), guestId: "guest", runId: "run", attendanceVerified: true)
        #expect(reopened.preview == nil)
        #expect(await client.importCalls == 1)
    }

    @Test("Missing guest allocation stays unresolved and never imports")
    func missingAllocation() async throws {
        let client = RecoveryPresentationClient(allocationMissing: true)
        let model = GuestRecoveryViewModel(engine: client)
        await model.load(); await model.selectSeason(26)
        await model.review(candidate: try #require(model.candidates.first), guestId: "guest", runId: "run", attendanceVerified: true)
        #expect(model.preview == nil)
        #expect(model.errorMessage != nil)
        #expect(await client.importCalls == 0)
    }

    @Test("Dismissal preserves evidence and reopening shows the dismissed status")
    func dismissal() async throws {
        let client = RecoveryPresentationClient()
        let model = GuestRecoveryViewModel(engine: client)
        await model.load()
        await model.setStatus(.dismissed, for: try #require(model.candidates.first))
        let reopened = GuestRecoveryViewModel(engine: client)
        await reopened.load()
        #expect(reopened.candidates.first?.displayName == "Rene")
        #expect(reopened.candidates.first?.status == .dismissed)
        #expect(reopened.candidates.first?.evidenceStatus == "legacy_ambiguous")
    }
}

private actor RecoveryPresentationClient: SyncEngineClient {
    let allocationMissing: Bool
    private var candidate = GuestRecoverySnapshot(id: "candidate", submissionId: UUID(), displayName: "Rene", expectedDate: "Fri, 11-Sep", expectedRun: "Sand", evidenceStatus: "legacy_ambiguous", status: .pending)
    private var confirmed = 10
    private(set) var previewCalls = 0
    private(set) var importCalls = 0
    init(allocationMissing: Bool = false) { self.allocationMissing = allocationMissing }
    nonisolated var events: AsyncStream<SyncEvent> { AsyncStream { $0.finish() } }
    func refreshState() async throws -> SheetState { state() }
    func refreshState(seasonSheetId: Int?) async throws -> SheetState { state() }
    private func state() -> SheetState {
        SheetState(runs: [RunRecord(rowIndex: 42, date: "Fri, 11-Sep", meet: "Beach", run: "Sand", plusOnes: 1,
            identity: RunIdentity(spreadsheetId: "book", seasonSheetId: 26, runId: "run"), namedGuestIds: [], unnamedGuests: 1)],
            seasonYear: 2026, spreadsheetId: "book", seasonSheetId: 26,
            guests: [SharedGuest(guestId: "guest", displayName: "Rene", confirmedRuns: confirmed)],
            supportedSeasons: [SupportedSeason(seasonSheetId: 26, seasonYear: 2026)])
    }
    func recoveryCandidates(includeDismissed: Bool) async throws -> [GuestRecoverySnapshot] { [candidate] }
    func updateRecoveryCandidate(id: String, guestId: String?, run: GuestImportEntry?, status: GuestRecoveryStatus) async throws {
        candidate.selectedGuestId = guestId; candidate.selectedRun = run; candidate.status = status
    }
    func previewGuestImport(guestId: String, entries: [GuestImportEntry]) async throws -> GuestImportPreview {
        previewCalls += 1
        if allocationMissing { throw SheetAPIError.badPayload(message: "No unnamed allocation exists.") }
        return GuestImportPreview(guestId: guestId, baseGuestRevision: 1, baseRevision: "review", entries: entries, changes: [], confirmedRuns: confirmed)
    }
    func importGuestHistory(_ preview: GuestImportPreview, candidateIds: [String]) async throws -> UUID {
        importCalls += 1; confirmed = 11; candidate.status = .imported; return UUID()
    }
    func guestOperation(id: UUID) async throws -> GuestOperationSnapshot? { GuestOperationSnapshot(id: id, action: "importGuestHistory", phase: .completed) }
    func enqueue(_ submission: AttendanceSubmission) async throws -> UUID { UUID() }
    func enqueue(draft: AttendanceDraft, mode: SubmissionMode, deviceName: String?) async throws -> UUID { UUID() }
    func drain() async {}
    func addMember(name: String) async throws -> AddMemberResult { throw SheetAPIError.notImplemented }
    func addRun(_ request: AddRunRequest) async throws -> AddRunResult { throw SheetAPIError.notImplemented }
    func resolveConflict(id: UUID, action: ConflictResolutionAction) async throws -> UUID? { nil }
}
