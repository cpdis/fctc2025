import Foundation
import SwiftData

extension SyncEngine {
    /// A reviewed correction is a new request, never a replay of the rejected one.
    /// Check the guest cache because history reads can be newer than the run state.
    public func replaceGuestRename(id: UUID, guest: SharedGuest, name: String) async throws -> UUID {
        let (old, state, guestID) = try reviewableGuestRename(id: id)
        let book = old.spreadsheetId
        let endpoint = old.endpointIdentity
        var guestQuery = FetchDescriptor<CachedGuest>(predicate: #Predicate {
            $0.spreadsheetId == book && $0.guestId == guestID
        })
        guestQuery.fetchLimit = 1
        let cached = try modelContext.fetch(guestQuery).first?.guest
        guard guest.guestId == guestID, let cached, cached.isActive,
              guest.revision == cached.revision, guest.displayName == cached.displayName,
              guest.status == cached.status else {
            throw SheetAPIError.badPayload(message: "This guest changed. Refresh and review the saved name again.")
        }
        // A separate in-flight correction may still commit. Do not overtake it,
        // even when this particular row has a definite terminal result.
        let rows = try modelContext.fetch(FetchDescriptor<PendingGuestOperation>(predicate: #Predicate {
            $0.endpointIdentity == endpoint && $0.spreadsheetId == book
        }))
        guard !rows.contains(where: {
            $0.operation?.action == "renameGuest" && $0.operation?.request["guestId"]?.string == guestID &&
            ($0.phase == .queued || $0.phase == .checking)
        }) else {
            throw SheetAPIError.badPayload(message: "Another name change is still saving. Check it before correcting this name.")
        }
        let correctedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !correctedName.isEmpty else { throw SheetAPIError.badPayload(message: "Enter a guest name.") }
        let operation = try SharedGuestOperation(action: "renameGuest", fields: [
            "guestId": .string(guestID), "displayName": .string(correctedName),
            "baseGuestRevision": .number(Double(guest.revision))
        ])
        do {
            _ = try saveGuestOperation(operation, state: state)
            old.phase = .superseded; old.lastError = nil
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
        // Use the serial drain so older unknown outcomes keep their place.
        await drain()
        return operation.id
    }

    /// Keep the saved name. This only closes a request known not to have applied;
    /// its original bytes and conflict remain as evidence in local history.
    public func discardGuestRename(id: UUID) async throws {
        let (old, _, _) = try reviewableGuestRename(id: id)
        old.phase = .superseded; old.lastError = nil
        do { try modelContext.save() } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func reviewableGuestRename(id: UUID) throws -> (PendingGuestOperation, SheetState, String) {
        guard let row = try guestOperationRecord(id: id), let operation = row.operation,
              operation.action == "renameGuest", row.phase == .conflict || row.phase == .rejected,
              let guestID = operation.request["guestId"]?.string, !guestID.isEmpty else {
            throw SheetAPIError.badPayload(message: "This name change is not ready for review. Check whether it saved first.")
        }
        let state = try requireSharedState()
        guard row.endpointIdentity == api.endpointIdentity, row.spreadsheetId == state.spreadsheetId else {
            throw SheetAPIError.badPayload(message: "Return to the original sheet to review this name change.")
        }
        return (row, state, guestID)
    }
}
