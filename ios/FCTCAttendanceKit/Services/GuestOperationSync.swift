import Foundation
import SwiftData

extension SyncEngine {
    func drainGuestOperations() async {
        do {
            let rows = try modelContext.fetch(FetchDescriptor<PendingGuestOperation>(sortBy: [SortDescriptor(\.createdAt)]))
            for row in rows where row.phase == .queued || row.phase == .checking {
                await drainGuestOperation(id: row.id)
                if row.phase == .checking { break }
            }
        } catch { eventBroadcaster.yield(.serviceFailed(message: UserFacingError.sync(error))) }
    }
    func drainGuestOperation(id: UUID) async {
        var attemptedDispatch = false
        do {
            guard let row = try guestOperationRecord(id: id), let operation = row.operation,
                  row.phase == .queued || row.phase == .checking else { return }
            guard row.endpointIdentity == api.endpointIdentity,
                  try currentSharedState()?.spreadsheetId == row.spreadsheetId else {
                row.lastError = "Return to the original sheet to check this saved change."; try modelContext.save(); return
            }
            let response: GuestJSON
            if row.phase == .checking {
                guard let receipt = try await api.operationStatus(id: id) else {
                    row.lastError = UserFacingError.checkingSavedChanges; try modelContext.save(); return
                }
                guard receipt.requestDigest == operation.digest else { throw SheetAPIError.badPayload(message: "The saved receipt does not match this request.") }
                if receipt.status == "pending" { return }
                guard receipt.status == "completed", let saved = receipt.response else {
                    row.phase = .rejected; row.lastError = "This change was not applied. Review it before submitting a new change."
                    try modelContext.save(); return
                }
                response = saved
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
                let cached = try modelContext.fetch(FetchDescriptor<CachedGuest>()).first { $0.spreadsheetId == row.spreadsheetId && $0.guestId == guest.guestId }
                if let cached {
                    // Mutation responses need not contain a total. Preserve the
                    // confirmed snapshot until an authoritative state refresh.
                    var merged = guest; merged.confirmedRuns = guest.confirmedRuns ?? cached.guest?.confirmedRuns
                    merged.lastAttendance = guest.lastAttendance ?? cached.guest?.lastAttendance
                    cached.valueData = try JSONEncoder().encode(merged)
                } else { modelContext.insert(try CachedGuest(spreadsheetId: row.spreadsheetId, guest: guest)) }
                for provisional in try modelContext.fetch(FetchDescriptor<ProvisionalGuest>()) where provisional.operationId == id {
                    provisional.resolvedGuestId = guest.guestId
                }
            }
            for candidate in try modelContext.fetch(FetchDescriptor<GuestRecoveryCandidate>()) where candidate.operationId == id {
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
            // A transport failure is not evidence that the request was rejected.
            // Typed validation/authentication errors occur before any mutation.
            if attemptedDispatch, let error = error as? SheetAPIError,
               error.code == "bad_secret" || error.code == "busy" {
                row.phase = .queued; row.lastError = UserFacingError.sync(error)
            } else if attemptedDispatch, let error = error as? SheetAPIError,
                      !error.isRetryable, error.code != "decoding", error.code != "internal_error" {
                row.phase = .rejected; row.lastError = UserFacingError.sync(error)
            } else { row.lastError = UserFacingError.checkingSavedChanges }
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
        await drainGuestOperation(id: operation.id)
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
        await drainGuestOperation(id: operation.id)
        let result: AddRunResult = try completedGuestResponse(id: operation.id).decoded()
        _ = try await refreshState(seasonSheetId: season)
        return result
    }
}
