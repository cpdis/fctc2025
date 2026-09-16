import Foundation
import Observation

/// Keep the attendance receipt and promotion receipt separate. A saved run remains
/// saved even when its promotion preview fails or its response needs verification.
@MainActor @Observable
public final class GuestPromotionViewModel {
    public let guest: SharedGuest
    public var memberName: String
    public var targetMode: PromotionTargetMode = .create
    public private(set) var preview: PromotionPreview?
    public private(set) var isWorking = false
    public private(set) var runMessage: String?
    public private(set) var promotionMessage: String?
    public private(set) var errorMessage: String?
    public private(set) var operationId: UUID?
    public private(set) var completed = false
    public private(set) var waitingForRun = false
    private var submissionId: UUID?
    private var runOutcome: SubmissionDisposition?
    @ObservationIgnored private let engine: any SyncEngineClient

    public init(guest: SharedGuest, engine: any SyncEngineClient) {
        self.guest = guest; memberName = guest.displayName; self.engine = engine
    }

    public func prepare(checklist: ChecklistViewModel?, mode: SubmissionMode = .overwrite) async {
        guard !isWorking, operationId == nil else { return }
        isWorking = true; errorMessage = nil; preview = nil
        defer { isWorking = false }
        do {
            if let checklist {
                if submissionId == nil && checklist.draftDiffersFromSheet {
                    submissionId = try await checklist.confirm(mode: mode)
                    runMessage = "Run queued. Waiting for confirmation."
                }
                if let submissionId {
                    await engine.drain()
                    let submission = try await engine.pendingSubmission(id: submissionId)
                    runOutcome = submission?.outcome
                    guard submission?.outcome == .committed else {
                        waitingForRun = true
                        runMessage = submission?.status == .conflict
                            ? "Run needs review in Outbox. Promotion has not started."
                            : "Run pending. Promotion will wait until this run is saved."
                        errorMessage = submission?.conflictMessage
                        return
                    }
                    waitingForRun = false
                    runMessage = "Run saved."
                    let state = try await engine.refreshState(seasonSheetId: checklist.run.runIdentity?.seasonSheetId)
                    checklist.acceptSavedState(state)
                }
            }
            preview = try await engine.previewPromotion(guestId: guest.guestId, memberName: memberName, targetMode: targetMode)
            promotionMessage = "Review all saved runs before adding this member."
        } catch {
            errorMessage = UserFacingError.sync(error)
            promotionMessage = runOutcome == .committed ? "Promotion has not completed. The run is saved." : "Promotion has not completed."
        }
    }

    public func commit() async {
        guard !isWorking, !completed else { return }
        isWorking = true; errorMessage = nil
        defer { isWorking = false }
        do {
            if operationId == nil {
                guard let preview else { return }
                operationId = try await engine.commitPromotion(preview)
            } else { await engine.drain() }
            guard let operationId, let operation = try await engine.guestOperation(id: operationId) else {
                promotionMessage = "Checking saved promotion. Check again before making another change."
                return
            }
            switch operation.phase {
            case .completed:
                completed = true
                promotionMessage = "Added as a member with \(preview?.confirmedRuns ?? guest.confirmedRuns ?? 0) recorded runs."
                _ = try? await engine.refreshState()
            case .queued, .checking:
                promotionMessage = "Checking saved promotion. Check again before making another change."
            case .conflict, .rejected, .superseded:
                errorMessage = operation.message ?? operation.conflict?.message ?? "Review the history again before promotion."
                self.operationId = nil; preview = nil
                promotionMessage = "Promotion has not completed."
            }
        } catch { errorMessage = UserFacingError.sync(error) }
    }
}
