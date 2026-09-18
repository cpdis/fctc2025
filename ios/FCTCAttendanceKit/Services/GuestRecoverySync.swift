import Foundation
import SwiftData

extension SyncEngine {
    /// Copy evidence, never reinterpret a legacy `done` record as attendance.
    func prepareLegacyRecovery() throws {
        let candidates = try modelContext.fetch(FetchDescriptor<GuestRecoveryCandidate>())
        let existing = Set(candidates.map(\.id))
        for row in try modelContext.fetch(FetchDescriptor<PendingSubmission>()) where row.runIdentity == nil {
            for (index, name) in row.guestNames.enumerated() where !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let candidate = GuestRecoveryCandidate(submission: row, name: name, index: index)
                if !existing.contains(candidate.id) { modelContext.insert(candidate) }
            }
        }
        try modelContext.save()
    }
    public func recoveryCandidates(includeDismissed: Bool = false) async throws -> [GuestRecoverySnapshot] {
        try prepareLegacyRecovery()
        return try modelContext.fetch(FetchDescriptor<GuestRecoveryCandidate>()).filter {
            includeDismissed || $0.status != .dismissed
        }.map { GuestRecoverySnapshot(id: $0.id, submissionId: $0.submissionId, displayName: $0.displayName,
            expectedDate: $0.expectedDate, expectedRun: $0.expectedRun, evidenceStatus: $0.evidenceStatus,
            status: $0.status, selectedGuestId: $0.selectedGuestId, selectedRun: $0.selectedRun) }
    }
    public func updateRecoveryCandidate(id: String, guestId: String?, run: GuestImportEntry?, status: GuestRecoveryStatus) async throws {
        guard status != .imported else { throw SheetAPIError.badPayload(message: "Only a saved receipt can confirm an import.") }
        guard let candidate = try modelContext.fetch(FetchDescriptor<GuestRecoveryCandidate>()).first(where: { $0.id == id }),
              candidate.status != .imported else { return }
        if let operationId = candidate.operationId, let operation = try guestOperationRecord(id: operationId),
           operation.phase == .checking || operation.phase == .queued {
            throw SheetAPIError.server(code: "pending_verification", message: UserFacingError.checkingSavedChanges)
        }
        candidate.selectedGuestId = guestId
        candidate.selectedRunData = try run.map { try JSONEncoder().encode($0) }
        candidate.status = status
        try modelContext.save()
    }
    public func previewGuestImport(guestId: String, entries: [GuestImportEntry]) async throws -> GuestImportPreview {
        _ = try requireSharedState()
        return try await api.sharedRead(action: "previewGuestImport", fields: ["guestId": .string(guestId), "entries": try .value(entries)]).decoded()
    }
    public func importGuestHistory(_ preview: GuestImportPreview, candidateIds: [String]) async throws -> UUID {
        let state = try requireSharedState()
        let candidates = try modelContext.fetch(FetchDescriptor<GuestRecoveryCandidate>()).filter { candidateIds.contains($0.id) }
        guard candidates.count == Set(candidateIds).count, candidates.allSatisfy({
            $0.status != .imported && $0.selectedGuestId == preview.guestId && $0.selectedRun.map(preview.entries.contains) == true
        }) else { throw SheetAPIError.badPayload(message: "Review each local name, season and run before importing.") }
        let operation = try SharedGuestOperation(action: "importGuestHistory", fields: [
            "guestId": .string(preview.guestId), "baseGuestRevision": .number(Double(preview.baseGuestRevision)),
            "baseRevision": .string(preview.baseRevision), "entries": try .value(preview.entries)
        ])
        _ = try saveGuestOperation(operation, state: state)
        for candidate in candidates { candidate.operationId = operation.id }
        try modelContext.save()
        await drainGuestOperation(id: operation.id)
        return operation.id
    }
}
