import Foundation
import SwiftData

extension SyncEngine {
    /// Read persisted disposition; enqueueing alone is never a saved-run receipt.
    public func pendingSubmission(id: UUID) async throws -> PendingSubmissionSnapshot? {
        guard let row = try pending(id: id) else { return nil }
        return PendingSubmissionSnapshot(id: row.id, rowIndex: row.rowIndex,
            expectedDate: row.expectedDate, expectedRun: row.expectedRun,
            attendees: row.attendees, guestNames: row.guestNames, plusOnes: row.plusOnes,
            actualKm: row.actualKm, mode: row.mode, status: row.status, createdAt: row.createdAt,
            lastError: row.lastError, conflictReason: row.conflictReason,
            conflictMessage: row.conflictMessage, conflictState: row.conflictState,
            outcome: row.outcome, runIdentity: row.runIdentity, namedGuestIds: row.namedGuestIds,
            unnamedGuests: row.unnamedGuests, verificationPending: row.verificationPending == true)
    }

    /// The organiser reviews a fresh run with promoted guests mapped to members.
    /// Persist replacement and supersession together so no discarded intent gap exists.
    public func replacePromotedGuestSubmission(id: UUID, reviewedDraft: AttendanceDraft) async throws -> UUID {
        let createdAt = await clock.now()
        guard let old = try pending(id: id), old.status == .conflict,
              old.conflictReason == "guest_promoted" else { throw SyncEngineError.conflictNotFound }
        let state = try requireSharedState()
        guard let identity = old.runIdentity, reviewedDraft.runIdentity == identity,
              old.endpointIdentity == api.endpointIdentity, reviewedDraft.endpointIdentity == api.endpointIdentity,
              state.spreadsheetId == identity.spreadsheetId, state.seasonSheetId == identity.seasonSheetId,
              reviewedDraft.baseRevision == state.sheetRevision,
              let run = state.runs.first(where: { $0.identity == identity }),
              run.date == reviewedDraft.expectedDate, run.run == reviewedDraft.expectedRun,
              reviewedDraft.unmatched.isEmpty, let unnamed = reviewedDraft.unnamedGuests, unnamed >= 0 else {
            throw SheetAPIError.badPayload(message: "Refresh and review the original run before converting its guests.")
        }
        let roster = Set(state.roster.map(\.name)), guests = state.guests ?? []
        let promoted = guests.filter { (old.namedGuestIds ?? []).contains($0.guestId) && $0.status == "promoted" }
        let selected = Set(reviewedDraft.namedGuestIds)
        guard !promoted.isEmpty, Set(reviewedDraft.checks.keys).isSubset(of: roster),
              selected.isSubset(of: Set(guests.filter(\.isActive).map(\.guestId))),
              promoted.allSatisfy({ guest in
                  guard let name = guest.memberName else { return false }
                  return reviewedDraft.checks[name] != nil && roster.contains(name)
              }) else {
            throw SheetAPIError.badPayload(message: "Select each promoted person as a member and review the remaining guests.")
        }
        if old.mode == .merge {
            // A reviewed replacement uses overwrite for revision protection, but
            // must preserve the original additive intent and concurrent choices.
            let requiredMembers = Set(run.attendees).union(old.attendees)
            let activeIDs = Set(guests.filter(\.isActive).map(\.guestId))
            let requiredGuests = Set(run.namedGuestIds ?? []).union(old.namedGuestIds ?? []).intersection(activeIDs)
            let currentUnnamed = run.unnamedGuests ?? max(0, run.plusOnes - (run.namedGuestIds?.count ?? 0))
            guard requiredMembers.isSubset(of: Set(reviewedDraft.attendees)), requiredGuests.isSubset(of: selected),
                  unnamed >= max(currentUnnamed, old.unnamedGuests ?? 0) else {
                throw SheetAPIError.badPayload(message: "A merge must keep the sheet's saved members and guests. Refresh and review the conversion again.")
            }
        }
        var draft = reviewedDraft
        draft.rowIndex = run.rowIndex
        let replacement = PendingSubmission.from(draft: draft, mode: .overwrite,
            deviceName: old.deviceName, createdAt: createdAt)
        modelContext.insert(replacement)
        old.status = .done; old.outcomeRaw = SubmissionDisposition.superseded.rawValue
        old.lastError = nil; old.clearConflict()
        do { try modelContext.save() } catch {
            modelContext.rollback()
            throw error
        }
        eventBroadcaster.yield(.queued(id: replacement.id))
        startAutomaticDrainIfNeeded()
        return replacement.id
    }
}
