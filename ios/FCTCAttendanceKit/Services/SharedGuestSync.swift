import Foundation
import SwiftData

extension SyncEngine {
    func currentSharedState() throws -> SheetState? {
        if let latestState { return latestState }
        return try modelContext.fetch(FetchDescriptor<SharedSheetCache>(sortBy: [SortDescriptor(\.refreshedAt, order: .reverse)]))
            .first { $0.endpointIdentity == api.endpointIdentity }?.state
    }
    func requireSharedState() throws -> SheetState {
        guard let state = try currentSharedState(), state.supportsSharedGuests,
              state.spreadsheetId != nil, api.endpointIdentity != nil else {
            throw SheetAPIError.server(code: "update_required", message: "Refresh after shared guests are enabled for this sheet.")
        }
        return state
    }
    func reconcileSharedState(_ state: SheetState, seenAt: Date) throws {
        guard let endpoint = api.endpointIdentity, let book = state.spreadsheetId else { return }
        let newCache = try SharedSheetCache(endpointIdentity: endpoint, state: state, refreshedAt: seenAt)
        let caches = try modelContext.fetch(FetchDescriptor<SharedSheetCache>())
        if let existing = caches.first(where: { $0.key == newCache.key }) {
            existing.stateData = newCache.stateData; existing.refreshedAt = seenAt
        } else { modelContext.insert(newCache) }
        let guests = try modelContext.fetch(FetchDescriptor<CachedGuest>())
        for guest in state.guests ?? [] {
            if let existing = guests.first(where: { $0.spreadsheetId == book && $0.guestId == guest.guestId }) {
                existing.valueData = try JSONEncoder().encode(guest)
            } else { modelContext.insert(try CachedGuest(spreadsheetId: book, guest: guest)) }
        }
    }
    public func sharedGuests() async throws -> [SharedGuest] {
        guard let book = try currentSharedState()?.spreadsheetId else { return [] }
        return try modelContext.fetch(FetchDescriptor<CachedGuest>()).filter { $0.spreadsheetId == book }
            .compactMap(\.guest).sorted {
                if $0.displayName == $1.displayName { return $0.guestId < $1.guestId }
                return Member.sheetOrder($0.displayName, $1.displayName)
            }
    }
    public func guestHistory(id: String) async throws -> GuestHistory {
        let state = try requireSharedState()
        guard state.capabilities?.guestHistory == true else { throw SheetAPIError.notImplemented }
        let result: GuestHistory = try await api.sharedRead(action: "getGuestHistory", fields: ["guestId": .string(id)]).decoded()
        let cached = try modelContext.fetch(FetchDescriptor<CachedGuest>()).first { $0.spreadsheetId == state.spreadsheetId && $0.guestId == id }
        cached?.historyData = try JSONEncoder().encode(result)
        cached?.valueData = try JSONEncoder().encode(result.guest)
        try modelContext.save()
        return result
    }
    public func createGuest(name: String, confirmDistinct: Bool = false) async throws -> Guest {
        let state = try requireSharedState()
        let guest = Guest(name: name.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !guest.name.isEmpty else { throw SheetAPIError.badPayload(message: "Enter a guest name.") }
        try persistProvisionalGuest(guest, state: state, confirmDistinct: confirmDistinct)
        try modelContext.save(); startAutomaticDrainIfNeeded()
        return guest
    }
    func persistProvisionalGuest(_ guest: Guest, state: SheetState, confirmDistinct: Bool) throws {
        let operation = try SharedGuestOperation(action: "createGuest", fields: [
            "guestId": .string(guest.id.uuidString.lowercased()), "displayName": .string(guest.name), "confirmDistinct": .bool(confirmDistinct)
        ])
        let record = try saveGuestOperation(operation, state: state)
        modelContext.insert(ProvisionalGuest(guest: guest, endpointIdentity: record.endpointIdentity,
                                            spreadsheetId: record.spreadsheetId, operationId: record.id))
    }
    func prepareGuestDependencies(_ guests: [Guest], identity: RunIdentity) throws {
        let state = try requireSharedState()
        guard state.spreadsheetId == identity.spreadsheetId else { throw SheetAPIError.badPayload(message: "This draft belongs to another workbook.") }
        let shared = try modelContext.fetch(FetchDescriptor<CachedGuest>())
        let provisional = try modelContext.fetch(FetchDescriptor<ProvisionalGuest>())
        for guest in guests {
            let id = guest.id.uuidString.lowercased()
            if shared.contains(where: { $0.spreadsheetId == identity.spreadsheetId && $0.guestId == id }) { continue }
            if provisional.contains(where: { $0.spreadsheetId == identity.spreadsheetId && $0.guestId == id && $0.endpointIdentity == api.endpointIdentity }) { continue }
            try persistProvisionalGuest(guest, state: state, confirmDistinct: false)
        }
    }
    public func resolveGuestIdentity(provisionalId: String, existingGuestId: String?, confirmDistinct: Bool) async throws {
        let state = try requireSharedState()
        guard let provisional = try modelContext.fetch(FetchDescriptor<ProvisionalGuest>()).first(where: {
            $0.guestId == provisionalId && $0.endpointIdentity == api.endpointIdentity && $0.spreadsheetId == state.spreadsheetId
        }), let old = try guestOperationRecord(id: provisional.operationId), old.phase == .conflict else {
            throw SheetAPIError.badPayload(message: "This identity is not waiting for review.")
        }
        if let existingGuestId {
            guard (try await sharedGuests()).contains(where: { $0.guestId == existingGuestId && $0.isActive }) else {
                throw SheetAPIError.badPayload(message: "Select an active shared guest.")
            }
            provisional.resolvedGuestId = existingGuestId; old.phase = .superseded
        } else {
            guard confirmDistinct else { throw SheetAPIError.badPayload(message: "Confirm that this is a different person.") }
            let operation = try SharedGuestOperation(action: "createGuest", fields: [
                "guestId": .string(provisionalId), "displayName": .string(provisional.displayName), "confirmDistinct": .bool(true)
            ])
            let replacement = try saveGuestOperation(operation, state: state)
            provisional.operationId = replacement.id; old.phase = .superseded
        }
        // No operation bytes exist until identity dependencies are resolved.
        for pending in try modelContext.fetch(FetchDescriptor<PendingSubmission>()) where pending.namedGuestIds?.contains(provisionalId) == true && pending.sharedOperationData == nil {
            pending.status = .queued; pending.lastError = nil; pending.clearConflict()
        }
        try modelContext.save(); startAutomaticDrainIfNeeded()
    }
    public func renameGuest(_ guest: SharedGuest, name: String) async throws -> UUID {
        let state = try requireSharedState()
        let operation = try SharedGuestOperation(action: "renameGuest", fields: [
            "guestId": .string(guest.guestId), "displayName": .string(name), "baseGuestRevision": .number(Double(guest.revision))
        ])
        _ = try saveGuestOperation(operation, state: state); try modelContext.save()
        await drainGuestOperation(id: operation.id)
        return operation.id
    }
    public func previewPromotion(guestId: String, memberName: String, targetMode: PromotionTargetMode) async throws -> PromotionPreview {
        let state = try await refreshState(seasonSheetId: nil)
        guard state.capabilities?.guestPromotion == true else { throw SheetAPIError.server(code: "update_required", message: "Enable guest promotion before continuing.") }
        return try await api.sharedRead(action: "previewPromotion", fields: [
            "guestId": .string(guestId), "memberName": .string(memberName), "targetMode": .string(targetMode.rawValue)
        ]).decoded()
    }
    public func commitPromotion(_ preview: PromotionPreview) async throws -> UUID {
        let state = try requireSharedState()
        guard state.capabilities?.guestPromotion == true else { throw SheetAPIError.notImplemented }
        let operation = try SharedGuestOperation(action: "commitPromotion", fields: [
            "guestId": .string(preview.guestId), "memberName": .string(preview.memberName),
            "targetMode": .string(preview.targetMode.rawValue), "previewToken": .string(preview.previewToken)
        ])
        _ = try saveGuestOperation(operation, state: state); try modelContext.save()
        await drainGuestOperation(id: operation.id)
        return operation.id
    }
    public func guestOperation(id: UUID) async throws -> GuestOperationSnapshot? {
        guard let row = try guestOperationRecord(id: id) else { return nil }
        return GuestOperationSnapshot(id: row.id, action: row.operation?.action ?? "", phase: row.phase,
            message: row.lastError, conflict: row.conflict,
            response: row.responseData.flatMap { try? JSONDecoder().decode(GuestJSON.self, from: $0) })
    }
    func saveGuestOperation(_ operation: SharedGuestOperation, state: SheetState) throws -> PendingGuestOperation {
        guard let endpoint = api.endpointIdentity, let book = state.spreadsheetId, state.supportsSharedGuests else { throw SheetAPIError.notConfigured }
        let row = try PendingGuestOperation(operation: operation, endpointIdentity: endpoint, spreadsheetId: book)
        modelContext.insert(row)
        return row
    }
    func guestOperationRecord(id: UUID) throws -> PendingGuestOperation? {
        var descriptor = FetchDescriptor<PendingGuestOperation>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
