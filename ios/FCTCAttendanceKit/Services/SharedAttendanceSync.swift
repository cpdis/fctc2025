import Foundation
import SwiftData

extension SyncEngine {
    func drainSharedAttendance(id: UUID) async {
        var attemptedDispatch = false
        do {
            guard let row = try pending(id: id), let identity = row.runIdentity else { return }
            guard row.endpointIdentity == api.endpointIdentity,
                  try currentSharedState()?.spreadsheetId == identity.spreadsheetId else {
                try parkForReview(row, message: "Return to the original workbook to save this run."); return
            }
            if row.sharedOperationData == nil {
                guard try resolveDependencies(row) else { return }
                let state = try requireSharedState()
                if state.pendingOperationId != nil {
                    row.lastError = UserFacingError.checkingSavedChanges; try modelContext.save(); return
                }
                let operation = try attendanceOperation(row)
                row.sharedOperationData = try JSONEncoder().encode(operation)
                try modelContext.save()
            }
            guard let bytes = row.sharedOperationData else { return }
            let operation = try JSONDecoder().decode(SharedGuestOperation.self, from: bytes)
            let response: GuestJSON
            if row.verificationPending == true || row.status == .inFlight {
                switch try await checkedGuestReceipt(for: operation) {
                case .missing:
                    row.lastError = UserFacingError.checkingSavedChanges; try modelContext.save(); return
                case .pending: return
                case .notApplied:
                    try parkForReview(row, message: "This run was not saved. Review it before submitting a new change."); return
                case .completed(let saved): response = saved
                }
            } else {
                row.status = .inFlight; row.verificationPending = true; row.lastAttemptAt = await clock.now()
                row.attemptCount += 1; row.lastError = UserFacingError.checkingSavedChanges
                try modelContext.save()
                attemptedDispatch = true
                response = try await api.perform(operation)
            }
            row.status = .done; row.outcomeRaw = SubmissionDisposition.committed.rawValue
            row.verificationPending = false; row.lastError = nil; row.clearConflict()
            if let revision = response["sheetRevision"]?.string { row.baseRevision = revision }
            try modelContext.save()
            eventBroadcaster.yield(.written(id: id))
            // Counts and allocations must be reconstructed from the server. A lost
            // refresh cannot turn a confirmed receipt back into a queued write.
            _ = try? await refreshState(seasonSheetId: identity.seasonSheetId)
        } catch let conflict as SharedGuestConflict {
            guard let row = try? pending(id: id) else { return }
            if conflict.reason == "pending_verification" || conflict.reason == "pending_operation" {
                row.verificationPending = conflict.operationId == nil || conflict.operationId == id.uuidString.lowercased()
                row.status = .queued; row.lastError = UserFacingError.checkingSavedChanges
            } else {
                row.verificationPending = false; row.status = .conflict; row.lastError = conflict.message
                row.conflictReason = conflict.reason; row.conflictMessage = conflict.message
                if let state = conflict.state {
                    row.conflictStateData = try? JSONEncoder().encode(state)
                    try? reconcile(state, seenAt: await clock.now())
                    eventBroadcaster.yield(.conflict(id: id, reason: conflict.reason, message: conflict.message, state: state))
                }
            }
            try? modelContext.save()
        } catch {
            guard let row = try? pending(id: id) else { return }
            if attemptedDispatch, case SheetAPIError.requestNotSent = error {
                // Keep the exact saved UUID and digest. Only this dispatch's
                // proven non-delivery can clear its persisted verification flag.
                row.status = .queued; row.verificationPending = false
                row.lastError = UserFacingError.offline
                try? modelContext.save()
                eventBroadcaster.yield(.parked(id: id, message: UserFacingError.offline))
            } else if attemptedDispatch, let error = error as? SheetAPIError,
               error.code == "bad_secret" || error.code == "busy" {
                row.status = .queued; row.verificationPending = false
                row.lastError = UserFacingError.sync(error)
                try? modelContext.save()
                if error.code == "bad_secret" { eventBroadcaster.yield(.authenticationRequired(id: id)) }
            } else if attemptedDispatch, let error = error as? SheetAPIError,
                      !error.isRetryable, error.code != "decoding", error.code != "internal_error" {
                try? parkForReview(row, message: UserFacingError.sync(error))
            } else {
                row.status = .queued; row.lastError = UserFacingError.checkingSavedChanges
                try? modelContext.save()
                eventBroadcaster.yield(.parked(id: id, message: UserFacingError.checkingSavedChanges))
            }
        }
    }
    func resolveDependencies(_ row: PendingSubmission) throws -> Bool {
        let provisional = try modelContext.fetch(FetchDescriptor<ProvisionalGuest>())
        var ids = row.namedGuestIds ?? []
        for (index, id) in ids.enumerated() {
            guard let dependency = provisional.first(where: {
                $0.guestId == id && $0.spreadsheetId == row.spreadsheetId && $0.endpointIdentity == row.endpointIdentity
            }) else { continue }
            if let resolved = dependency.resolvedGuestId { ids[index] = resolved; continue }
            let operation = try guestOperationRecord(id: dependency.operationId)
            row.lastError = operation?.phase == .conflict ? "Choose the shared guest or confirm a different person." : "Waiting for the guest to be saved."
            if operation?.phase == .conflict {
                row.status = .conflict; row.conflictReason = "identity_ambiguous"; row.conflictMessage = row.lastError
            }
            try modelContext.save(); return false
        }
        row.namedGuestIds = Array(Set(ids)).sorted()
        return true
    }
    func attendanceOperation(_ row: PendingSubmission) throws -> SharedGuestOperation {
        guard let identity = row.runIdentity, let names = row.namedGuestIds,
              let unnamed = row.unnamedGuests, unnamed >= 0 else {
            throw SheetAPIError.badPayload(message: "Review the named and unnamed guests before saving.")
        }
        return try SharedGuestOperation(id: row.id, action: "submitAttendance", fields: [
            "spreadsheetId": .string(identity.spreadsheetId), "seasonSheetId": .number(Double(identity.seasonSheetId)),
            "runId": .string(identity.runId), "rowIndex": .number(Double(row.rowIndex)),
            "expectedDate": .string(row.expectedDate), "expectedRun": .string(row.expectedRun),
            "attendees": .array(row.attendees.map(GuestJSON.string)), "namedGuestIds": .array(names.map(GuestJSON.string)),
            "unnamedGuests": .number(Double(unnamed)), "actualKm": row.actualKm.map(GuestJSON.number) ?? .null,
            "mode": .string(row.mode.rawValue), "baseRevision": row.baseRevision.map(GuestJSON.string) ?? .null
        ])
    }
    func parkForReview(_ row: PendingSubmission, message: String) throws {
        row.status = .conflict; row.conflictReason = "identity_review_required"
        row.conflictMessage = message; row.lastError = message
        try modelContext.save()
        eventBroadcaster.yield(.parked(id: row.id, message: message))
    }
    func resolveSharedConflict(_ old: PendingSubmission, action: ConflictResolutionAction, state: SheetState) async throws -> UUID {
        guard let identity = old.runIdentity,
              let run = state.runs.first(where: { $0.identity == identity }),
              state.spreadsheetId == identity.spreadsheetId else {
            throw SheetAPIError.badPayload(message: "Refresh and select the original run. Its identity could not be verified.")
        }
        // A promotion needs a reviewed guest-to-member conversion, not aggregate
        // merge or overwrite. The UI constructs a new draft against this state.
        guard old.conflictReason != "guest_promoted", old.conflictReason != "identity_ambiguous" else {
            throw SheetAPIError.badPayload(message: "Review the guest identity before saving a new draft.")
        }
        let replacement = PendingSubmission(rowIndex: run.rowIndex, expectedDate: run.date, expectedRun: run.run,
            attendees: old.attendees, guestNames: old.guestNames, plusOnes: old.plusOnes, actualKm: old.actualKm,
            mode: action == .overwrite ? .overwrite : .merge, baseRevision: state.sheetRevision, createdAt: await clock.now())
        replacement.endpointIdentity = old.endpointIdentity; replacement.spreadsheetId = identity.spreadsheetId
        replacement.seasonSheetId = identity.seasonSheetId; replacement.runId = identity.runId
        replacement.namedGuestIds = old.namedGuestIds; replacement.unnamedGuests = old.unnamedGuests
        old.status = .done; old.outcomeRaw = SubmissionDisposition.superseded.rawValue
        return try persistAndStart(replacement)
    }
}
