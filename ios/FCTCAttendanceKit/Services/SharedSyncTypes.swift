import Foundation

public struct GuestRecoverySnapshot: Hashable, Sendable, Identifiable {
    public var id: String
    public var submissionId: UUID
    public var displayName: String
    public var expectedDate: String
    public var expectedRun: String
    public var evidenceStatus: String
    public var status: GuestRecoveryStatus
    public var selectedGuestId: String?
    public var selectedRun: GuestImportEntry?

    public init(id: String, submissionId: UUID, displayName: String, expectedDate: String, expectedRun: String, evidenceStatus: String, status: GuestRecoveryStatus, selectedGuestId: String? = nil, selectedRun: GuestImportEntry? = nil) {
        self.id = id
        self.submissionId = submissionId
        self.displayName = displayName
        self.expectedDate = expectedDate
        self.expectedRun = expectedRun
        self.evidenceStatus = evidenceStatus
        self.status = status
        self.selectedGuestId = selectedGuestId
        self.selectedRun = selectedRun
    }
}

extension SyncEngineClient {
    public func refreshState(seasonSheetId: Int?) async throws -> SheetState {
        guard seasonSheetId == nil else { throw SheetAPIError.notImplemented }
        return try await refreshState()
    }
    /// Clients without shared seasons have no last season to compare against.
    public func previousSeasonSnapshot() async throws -> SheetState? { nil }
    public func sharedGuests() async throws -> [SharedGuest] { [] }
    public func guestHistory(id: String) async throws -> GuestHistory { throw SheetAPIError.notImplemented }
    public func createGuest(name: String, confirmDistinct: Bool = false) async throws -> Guest { throw SheetAPIError.notImplemented }
    public func resolveGuestIdentity(provisionalId: String, existingGuestId: String?, confirmDistinct: Bool) async throws { throw SheetAPIError.notImplemented }
    public func renameGuest(_ guest: SharedGuest, name: String) async throws -> UUID { throw SheetAPIError.notImplemented }
    public func replaceGuestRename(id: UUID, guest: SharedGuest, name: String) async throws -> UUID { throw SheetAPIError.notImplemented }
    public func discardGuestRename(id: UUID) async throws { throw SheetAPIError.notImplemented }
    public func previewPromotion(guestId: String, memberName: String, targetMode: PromotionTargetMode) async throws -> PromotionPreview { throw SheetAPIError.notImplemented }
    public func commitPromotion(_ preview: PromotionPreview) async throws -> UUID { throw SheetAPIError.notImplemented }
    public func recoveryCandidates(includeDismissed: Bool = false) async throws -> [GuestRecoverySnapshot] { [] }
    public func updateRecoveryCandidate(id: String, guestId: String?, run: GuestImportEntry?, status: GuestRecoveryStatus) async throws { throw SheetAPIError.notImplemented }
    public func previewGuestImport(guestId: String, entries: [GuestImportEntry]) async throws -> GuestImportPreview { throw SheetAPIError.notImplemented }
    public func importGuestHistory(_ preview: GuestImportPreview, candidateIds: [String]) async throws -> UUID { throw SheetAPIError.notImplemented }
    public func guestOperation(id: UUID) async throws -> GuestOperationSnapshot? { nil }
    public func pendingSubmission(id: UUID) async throws -> PendingSubmissionSnapshot? { nil }
    public func replacePromotedGuestSubmission(id: UUID, reviewedDraft: AttendanceDraft) async throws -> UUID { throw SheetAPIError.notImplemented }
}

public struct GuestOperationSnapshot: Hashable, Sendable, Identifiable {
    public var id: UUID
    public var action: String
    public var phase: GuestOperationPhase
    public var message: String?
    public var conflict: SharedGuestConflict?
    public var response: GuestJSON?
    /// The name intent stays visible even when the server rejects the correction.
    public var guestId: String?
    public var proposedName: String?

    public init(id: UUID, action: String, phase: GuestOperationPhase, message: String? = nil, conflict: SharedGuestConflict? = nil, response: GuestJSON? = nil, guestId: String? = nil, proposedName: String? = nil) {
        self.id = id
        self.action = action
        self.phase = phase
        self.message = message
        self.conflict = conflict
        self.response = response
        self.guestId = guestId
        self.proposedName = proposedName
    }
}
