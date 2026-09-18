import Foundation
import Observation

@MainActor @Observable
public final class GuestRecoveryViewModel {
    public private(set) var candidates: [GuestRecoverySnapshot] = []
    public private(set) var guests: [SharedGuest] = []
    public private(set) var seasons: [SupportedSeason] = []
    public private(set) var selectedSeasonState: SheetState?
    public private(set) var preview: GuestImportPreview?
    public private(set) var isWorking = false
    public private(set) var errorMessage: String?
    public private(set) var statusMessage: String?
    public private(set) var operationId: UUID?
    private var seasonRequest = 0
    @ObservationIgnored private let engine: any SyncEngineClient

    public init(engine: any SyncEngineClient) { self.engine = engine }

    public func load() async {
        do {
            candidates = try await engine.recoveryCandidates(includeDismissed: true)
            guests = try await engine.sharedGuests()
            let state = try await engine.refreshState()
            seasons = (state.supportedSeasons ?? []).sorted { $0.seasonYear > $1.seasonYear }
            guests = state.guests ?? guests
        } catch { errorMessage = UserFacingError.sync(error) }
    }

    public func selectSeason(_ id: Int) async {
        seasonRequest += 1
        let request = seasonRequest
        selectedSeasonState = nil; preview = nil; errorMessage = nil
        guard seasons.contains(where: { $0.seasonSheetId == id }) else { isWorking = false; return }
        isWorking = true
        defer { if request == seasonRequest { isWorking = false } }
        do {
            let state = try await engine.refreshState(seasonSheetId: id)
            guard request == seasonRequest else { return }
            guard state.seasonSheetId == id else { throw SheetAPIError.badPayload(message: "The returned season does not match your selection.") }
            selectedSeasonState = state
        } catch {
            if request == seasonRequest { errorMessage = UserFacingError.sync(error) }
        }
    }

    public func review(candidate: GuestRecoverySnapshot, guestId: String, runId: String, attendanceVerified: Bool) async {
        guard attendanceVerified, candidate.status != .imported,
              let state = selectedSeasonState, let run = state.runs.first(where: { $0.runId == runId }),
              let identity = run.identity, guests.contains(where: { $0.guestId == guestId && $0.isActive }) else {
            errorMessage = "Select the person, season and run, then confirm the attendance evidence."
            return
        }
        isWorking = true; errorMessage = nil; preview = nil
        defer { isWorking = false }
        do {
            let entry = GuestImportEntry(identity: identity, expectedDate: run.date, expectedRun: run.run)
            try await engine.updateRecoveryCandidate(id: candidate.id, guestId: guestId, run: entry, status: .pending)
            preview = try await engine.previewGuestImport(guestId: guestId, entries: [entry])
        } catch { errorMessage = UserFacingError.sync(error) }
    }

    public func importReviewed(candidateId: String) async {
        guard let preview, !isWorking else { return }
        isWorking = true; errorMessage = nil
        defer { isWorking = false }
        do {
            if operationId == nil { operationId = try await engine.importGuestHistory(preview, candidateIds: [candidateId]) }
            else { await engine.drain() }
            guard let operationId, let operation = try await engine.guestOperation(id: operationId) else {
                statusMessage = "Checking saved import. This evidence remains on your phone."; return
            }
            switch operation.phase {
            case .completed:
                statusMessage = "History imported. The headcount stays the same."
                candidates = try await engine.recoveryCandidates(includeDismissed: true)
                self.preview = nil; self.operationId = nil
                do {
                    let state = try await engine.refreshState(seasonSheetId: preview.entries.first?.seasonSheetId)
                    guests = state.guests ?? guests
                    if state.seasonSheetId == selectedSeasonState?.seasonSheetId { selectedSeasonState = state }
                } catch {
                    statusMessage = "History imported. Connect again to refresh the confirmed totals."
                }
            case .queued, .checking:
                statusMessage = "Import pending. Check again when connected."
            case .conflict, .rejected, .superseded:
                errorMessage = operation.message ?? operation.conflict?.message ?? "Review this history again."
                self.preview = nil; self.operationId = nil
            }
        } catch { errorMessage = UserFacingError.sync(error) }
    }

    public func setStatus(_ status: GuestRecoveryStatus, for candidate: GuestRecoverySnapshot) async {
        do {
            try await engine.updateRecoveryCandidate(id: candidate.id, guestId: candidate.selectedGuestId, run: candidate.selectedRun, status: status)
            candidates = try await engine.recoveryCandidates(includeDismissed: true)
        } catch { errorMessage = UserFacingError.sync(error) }
    }
}
