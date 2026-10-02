import Foundation
import SwiftData

extension SyncEngine {
    func drainGuestOperations() async {
        do {
            // Exclude the terminal phases rather than match the two live ones:
            // an unknown raw phase reads as `.checking` and must still drain.
            let completed = GuestOperationPhase.completed.rawValue, conflict = GuestOperationPhase.conflict.rawValue
            let rejected = GuestOperationPhase.rejected.rawValue, superseded = GuestOperationPhase.superseded.rawValue
            let rows = try modelContext.fetch(FetchDescriptor<PendingGuestOperation>(
                predicate: #Predicate {
                    $0.phaseRaw != completed && $0.phaseRaw != conflict && $0.phaseRaw != rejected && $0.phaseRaw != superseded
                },
                sortBy: [SortDescriptor(\.createdAt)]
            ))
            // Checked again per row: another call can settle a row while an
            // earlier one is awaiting the sheet.
            for row in rows where row.phase == .queued || row.phase == .checking {
                await drainGuestOperation(id: row.id)
                // Retrying an unsent head must not let newer structural changes
                // overtake it. Unknown delivery still blocks on its receipt.
                if row.phase == .checking || row.phase == .queued { break }
            }
        } catch { eventBroadcaster.yield(.serviceFailed(message: UserFacingError.sync(error))) }
    }
    func drainGuestOperation(id: UUID) async {
        var attemptedDispatch = false
        do {
            guard let row = try guestOperationRecord(id: id),
                  row.phase == .queued || row.phase == .checking else { return }
            // Decode explicitly: corrupt bytes must reject the row, not return
            // early and leave a head that blocks every later operation.
            let operation = try JSONDecoder().decode(SharedGuestOperation.self, from: row.operationData)
            guard row.endpointIdentity == api.endpointIdentity,
                  try currentSharedState()?.spreadsheetId == row.spreadsheetId else {
                row.lastError = "Return to the original sheet to check this saved change."; try modelContext.save(); return
            }
            let response: GuestJSON
            if row.phase == .checking {
                switch try await checkedGuestReceipt(for: operation) {
                case .missing:
                    row.lastError = UserFacingError.checkingSavedChanges; try modelContext.save(); return
                case .pending: return
                case .notApplied:
                    row.phase = .rejected; row.lastError = "This change was not applied. Review it before submitting a new change."
                    try modelContext.save(); return
                case .completed(let saved): response = saved
                }
            } else {
                // Save checking before entering the transport; restart never repeats
                // a structural request whose delivery may already have happened.
                row.phase = .checking; row.lastError = UserFacingError.checkingSavedChanges
                try modelContext.save()
                attemptedDispatch = true
                response = try await api.perform(operation)
            }
            row.phase = .completed; row.lastError = nil; row.responseData = try JSONEncoder().encode(response)
            row.conflictData = nil
            if let guestJSON = response["guest"], let guest = try? guestJSON.decoded(SharedGuest.self) {
                if let cached = try cachedGuest(spreadsheetId: row.spreadsheetId, guestId: guest.guestId) {
                    // Mutation responses need not contain a total. Preserve the
                    // confirmed snapshot until an authoritative state refresh.
                    try cached.updateGuest(guest, preserveMissingTotals: true)
                } else { modelContext.insert(try CachedGuest(spreadsheetId: row.spreadsheetId, guest: guest)) }
                let provisionals = try modelContext.fetch(FetchDescriptor<ProvisionalGuest>(predicate: #Predicate { $0.operationId == id }))
                for provisional in provisionals {
                    provisional.resolvedGuestId = guest.guestId
                }
            }
            // Optional on both sides: #Predicate will not promote a UUID to UUID?.
            let operationId: UUID? = id
            let candidates = try modelContext.fetch(FetchDescriptor<GuestRecoveryCandidate>(predicate: #Predicate { $0.operationId == operationId }))
            for candidate in candidates {
                candidate.status = .imported
            }
            try modelContext.save()
        } catch let conflict as SharedGuestConflict {
            guard let row = try? guestOperationRecord(id: id) else { return }
            if conflict.reason == "pending_verification" || conflict.reason == "pending_operation" {
                // Another operation's fence proves this request was not dispatched.
                row.phase = conflict.operationId != nil && conflict.operationId != id.uuidString.lowercased() ? .queued : .checking
                row.lastError = UserFacingError.checkingSavedChanges
            } else {
                row.phase = .conflict; row.conflictData = try? JSONEncoder().encode(conflict); row.lastError = conflict.message
            }
            try? modelContext.save()
        } catch {
            guard let row = try? guestOperationRecord(id: id) else { return }
            switch OutboxFailure(error, attemptedDispatch: attemptedDispatch) {
            case .notSent: row.phase = .queued; row.lastError = UserFacingError.offline
            case .refused(let error): row.phase = .queued; row.lastError = UserFacingError.sync(error)
            // A rejected head no longer blocks the queue behind it.
            case .rejected(let message): row.phase = .rejected; row.lastError = message
            case .unknown: row.lastError = UserFacingError.checkingSavedChanges
            }
            try? modelContext.save()
        }
    }
    func completedGuestResponse(id: UUID) throws -> GuestJSON {
        guard let row = try guestOperationRecord(id: id) else { throw SheetAPIError.badPayload(message: "Missing saved operation.") }
        if let conflict = row.conflict { throw conflict }
        guard row.phase == .completed, let data = row.responseData else {
            throw SheetAPIError.server(code: "pending_verification", message: row.lastError ?? UserFacingError.checkingSavedChanges)
        }
        return try JSONDecoder().decode(GuestJSON.self, from: data)
    }
    func addSharedMember(name: String, state: SheetState) async throws -> AddMemberResult {
        guard let season = state.seasonSheetId else { throw SheetAPIError.notConfigured }
        let operation = try SharedGuestOperation(action: "addMember", fields: [
            "name": .string(name), "seasonSheetId": .number(Double(season)), "baseRevision": .string(state.sheetRevision)
        ])
        _ = try saveGuestOperation(operation, state: state); try modelContext.save()
        // The serial drain keeps older unknown outcomes ahead of this one. If
        // it cannot send yet, `completedGuestResponse` throws pending.
        await drain()
        let result: AddMemberResult = try completedGuestResponse(id: operation.id).decoded()
        _ = try await refreshState(seasonSheetId: season)
        return result
    }
    func addSharedRun(_ request: AddRunRequest, state: SheetState) async throws -> AddRunResult {
        guard let book = state.spreadsheetId, let season = state.seasonSheetId else { throw SheetAPIError.notConfigured }
        let operation = try SharedGuestOperation(action: "addRun", fields: [
            "spreadsheetId": .string(book), "seasonSheetId": .number(Double(season)),
            "date": .string(request.date), "meet": .string(request.meet), "run": .string(request.run),
            "approxKm": request.approxKm.map(GuestJSON.number) ?? .null, "baseRevision": .string(state.sheetRevision)
        ])
        _ = try saveGuestOperation(operation, state: state); try modelContext.save()
        await drain()
        let result: AddRunResult = try completedGuestResponse(id: operation.id).decoded()
        _ = try await refreshState(seasonSheetId: season)
        return result
    }
}


/// Both queue types validate the same receipt, then retain their own persistence policy.
enum CheckedGuestReceipt { case missing, pending, notApplied, completed(GuestJSON) }

extension SyncEngine {
    func checkedGuestReceipt(for operation: SharedGuestOperation) async throws -> CheckedGuestReceipt {
        guard let receipt = try await api.operationStatus(id: operation.id) else { return .missing }
        guard receipt.requestDigest == operation.digest else {
            throw SheetAPIError.badPayload(message: "The saved receipt does not match this request.")
        }
        if receipt.status == "pending" { return .pending }
        guard receipt.status == "completed", let saved = receipt.response else { return .notApplied }
        return .completed(saved)
    }
}
