import Foundation
import SwiftData

/// Server snapshots are disposable, but operation and recovery evidence are not.
@Model
public final class SharedSheetCache {
    @Attribute(.unique) public var key: String
    public var endpointIdentity: String
    public var spreadsheetId: String
    public var seasonSheetId: Int
    public var stateData: Data
    public var refreshedAt: Date
    public init(endpointIdentity: String, state: SheetState, refreshedAt: Date = .now) throws {
        guard let book = state.spreadsheetId, let season = state.seasonSheetId else { throw SheetAPIError.badPayload(message: "Missing workbook identity.") }
        key = "\(endpointIdentity):\(book):\(season)"; self.endpointIdentity = endpointIdentity
        spreadsheetId = book; seasonSheetId = season
        stateData = try JSONEncoder().encode(state); self.refreshedAt = refreshedAt
    }
    public var state: SheetState? { try? JSONDecoder().decode(SheetState.self, from: stateData) }
}

@Model
public final class CachedGuest {
    @Attribute(.unique) public var key: String
    public var spreadsheetId: String
    public var guestId: String
    public var valueData: Data
    public var historyData: Data?
    public init(spreadsheetId: String, guest: SharedGuest) throws {
        key = "\(spreadsheetId):\(guest.guestId)"; self.spreadsheetId = spreadsheetId; guestId = guest.guestId
        valueData = try JSONEncoder().encode(guest)
    }
    public var guest: SharedGuest? { try? JSONDecoder().decode(SharedGuest.self, from: valueData) }
    public var history: GuestHistory? { historyData.flatMap { try? JSONDecoder().decode(GuestHistory.self, from: $0) } }
}

public enum GuestOperationPhase: String, Codable, Hashable, Sendable { case queued, checking, completed, conflict, rejected, superseded }

/// Persist before dispatch. A process restart checks the receipt before any replay.
@Model
public final class PendingGuestOperation {
    @Attribute(.unique) public var id: UUID
    public var endpointIdentity: String
    public var spreadsheetId: String
    public var operationData: Data
    public var phaseRaw: String
    public var responseData: Data?
    public var conflictData: Data?
    public var lastError: String?
    public var createdAt: Date
    public init(operation: SharedGuestOperation, endpointIdentity: String, spreadsheetId: String) throws {
        id = operation.id; self.endpointIdentity = endpointIdentity; self.spreadsheetId = spreadsheetId
        operationData = try JSONEncoder().encode(operation); phaseRaw = GuestOperationPhase.queued.rawValue
        createdAt = .now
    }
    public var operation: SharedGuestOperation? { try? JSONDecoder().decode(SharedGuestOperation.self, from: operationData) }
    public var phase: GuestOperationPhase {
        get { GuestOperationPhase(rawValue: phaseRaw) ?? .checking }
        set { phaseRaw = newValue.rawValue }
    }
    public var conflict: SharedGuestConflict? { conflictData.flatMap { try? JSONDecoder().decode(SharedGuestConflict.self, from: $0) } }
}

@Model
public final class ProvisionalGuest {
    @Attribute(.unique) public var guestId: String
    public var displayName: String
    public var endpointIdentity: String
    public var spreadsheetId: String
    public var operationId: UUID
    /// Only an explicit selection can replace a provisional UUID with another ID.
    public var resolvedGuestId: String?
    public init(guest: Guest, endpointIdentity: String, spreadsheetId: String, operationId: UUID) {
        guestId = guest.id.uuidString.lowercased(); displayName = guest.name
        self.endpointIdentity = endpointIdentity; self.spreadsheetId = spreadsheetId; self.operationId = operationId
    }
}

public enum GuestRecoveryStatus: String, Codable, Hashable, Sendable { case pending, imported, dismissed }

@Model
public final class GuestRecoveryCandidate {
    @Attribute(.unique) public var id: String
    public var submissionId: UUID
    public var displayName: String
    public var expectedDate: String
    public var expectedRun: String
    public var originalRowIndex: Int
    public var evidenceStatus: String
    public var statusRaw: String
    public var selectedGuestId: String?
    public var selectedRunData: Data?
    public var operationId: UUID?
    public init(submission: PendingSubmission, name: String, index: Int) {
        id = "\(submission.id.uuidString.lowercased()):\(index)"; submissionId = submission.id
        displayName = name; expectedDate = submission.expectedDate; expectedRun = submission.expectedRun
        originalRowIndex = submission.rowIndex
        evidenceStatus = submission.outcomeRaw ?? (submission.state == .done ? "legacy_ambiguous" : "local_unconfirmed")
        statusRaw = GuestRecoveryStatus.pending.rawValue
    }
    public var status: GuestRecoveryStatus {
        get { GuestRecoveryStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }
    public var selectedRun: GuestImportEntry? { selectedRunData.flatMap { try? JSONDecoder().decode(GuestImportEntry.self, from: $0) } }
}
