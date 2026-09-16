import Foundation

/// A run's identity survives row insertion and is scoped to one season and workbook.
public struct RunIdentity: Codable, Hashable, Sendable {
    public var spreadsheetId: String
    public var seasonSheetId: Int
    public var runId: String
    public init(spreadsheetId: String, seasonSheetId: Int, runId: String) {
        self.spreadsheetId = spreadsheetId
        self.seasonSheetId = seasonSheetId
        self.runId = runId.lowercased()
    }
    public var cacheKey: String { "\(spreadsheetId):\(seasonSheetId):\(runId)" }
}

public struct GuestCapabilities: Codable, Hashable, Sendable {
    public var apiVersion: Int
    public var sharedGuests: Bool
    public var stableRunIdentity: Bool
    public var guestHistory: Bool
    public var guestPromotion: Bool
    public var operationReceipts: Bool
    public init(apiVersion: Int = 2, sharedGuests: Bool = true, stableRunIdentity: Bool = true,
                guestHistory: Bool = true, guestPromotion: Bool = true, operationReceipts: Bool = true) {
        self.apiVersion = apiVersion; self.sharedGuests = sharedGuests
        self.stableRunIdentity = stableRunIdentity; self.guestHistory = guestHistory
        self.guestPromotion = guestPromotion; self.operationReceipts = operationReceipts
    }
    public var canWrite: Bool { apiVersion == 2 && sharedGuests && stableRunIdentity && operationReceipts }
}

public struct GuestLastAttendance: Codable, Hashable, Sendable {
    public var spreadsheetId: String
    public var seasonSheetId: Int
    public var runId: String
    public var date: String
    public var seasonYear: Int
    public var identity: RunIdentity { RunIdentity(spreadsheetId: spreadsheetId, seasonSheetId: seasonSheetId, runId: runId) }

    public init(spreadsheetId: String, seasonSheetId: Int, runId: String, date: String, seasonYear: Int) {
        self.spreadsheetId = spreadsheetId
        self.seasonSheetId = seasonSheetId
        self.runId = runId
        self.date = date
        self.seasonYear = seasonYear
    }
}

/// Only the server supplies confirmedRuns. Local drafts remain pending attendance.
public struct SharedGuest: Codable, Hashable, Sendable, Identifiable {
    public var guestId: String
    public var displayName: String
    public var status: String
    public var memberName: String?
    public var revision: Int
    public var confirmedRuns: Int?
    public var lastAttendance: GuestLastAttendance?
    public var id: String { guestId }
    public var isActive: Bool { status == "active" }
    public var canSuggestPromotion: Bool { isActive && (confirmedRuns ?? 0) >= 10 }
    public var draftGuest: Guest? { UUID(uuidString: guestId).map { Guest(id: $0, name: displayName) } }
    public init(guestId: String, displayName: String, status: String = "active", memberName: String? = nil,
                revision: Int = 1, confirmedRuns: Int? = 0, lastAttendance: GuestLastAttendance? = nil) {
        self.guestId = guestId.lowercased(); self.displayName = displayName; self.status = status
        self.memberName = memberName; self.revision = revision; self.confirmedRuns = confirmedRuns
        self.lastAttendance = lastAttendance
    }
}

public struct GuestAttendanceEntry: Codable, Hashable, Sendable, Identifiable {
    public var guestId: String
    public var spreadsheetId: String
    public var seasonSheetId: Int
    public var runId: String
    public var state: String
    public var classification: String
    public var revision: Int
    public var seasonYear: Int
    public var date: String
    public var run: String
    public var rowIndex: Int
    public var identity: RunIdentity { RunIdentity(spreadsheetId: spreadsheetId, seasonSheetId: seasonSheetId, runId: runId) }
    public var id: String { "\(identity.cacheKey):\(guestId)" }

    public init(guestId: String, spreadsheetId: String, seasonSheetId: Int, runId: String, state: String, classification: String, revision: Int, seasonYear: Int, date: String, run: String, rowIndex: Int) {
        self.guestId = guestId
        self.spreadsheetId = spreadsheetId
        self.seasonSheetId = seasonSheetId
        self.runId = runId
        self.state = state
        self.classification = classification
        self.revision = revision
        self.seasonYear = seasonYear
        self.date = date
        self.run = run
        self.rowIndex = rowIndex
    }
}

public struct GuestHistory: Codable, Hashable, Sendable {
    public var guest: SharedGuest
    public var guestRevision: String
    public var attendance: [GuestAttendanceEntry]

    public init(guest: SharedGuest, guestRevision: String, attendance: [GuestAttendanceEntry]) {
        self.guest = guest
        self.guestRevision = guestRevision
        self.attendance = attendance
    }
}

public enum PromotionTargetMode: String, Codable, Hashable, Sendable { case create, link }
public struct PromotionPreview: Codable, Hashable, Sendable {
    public struct Season: Codable, Hashable, Sendable {
        public var seasonYear: Int
        public var seasonSheetId: Int
        public var runs: Int
    
        public init(seasonYear: Int, seasonSheetId: Int, runs: Int) {
            self.seasonYear = seasonYear
            self.seasonSheetId = seasonSheetId
            self.runs = runs
        }
    }
    public struct Change: Codable, Hashable, Sendable {
        public var spreadsheetId: String
        public var seasonSheetId: Int
        public var runId: String
        public var rowIndex: Int
        public var date: String
        public var run: String
        public var plusOnesBefore: Int
        public var plusOnesAfter: Int
        public var totalBefore: Int
        public var totalAfter: Int
        public var actualKmBefore: Double?
        public var actualKmAfter: Double?
    
        public init(spreadsheetId: String, seasonSheetId: Int, runId: String, rowIndex: Int, date: String, run: String, plusOnesBefore: Int, plusOnesAfter: Int, totalBefore: Int, totalAfter: Int, actualKmBefore: Double? = nil, actualKmAfter: Double? = nil) {
            self.spreadsheetId = spreadsheetId
            self.seasonSheetId = seasonSheetId
            self.runId = runId
            self.rowIndex = rowIndex
            self.date = date
            self.run = run
            self.plusOnesBefore = plusOnesBefore
            self.plusOnesAfter = plusOnesAfter
            self.totalBefore = totalBefore
            self.totalAfter = totalAfter
            self.actualKmBefore = actualKmBefore
            self.actualKmAfter = actualKmAfter
        }
    }
    public var guestId: String
    public var memberName: String
    public var confirmedRuns: Int
    public var previewToken: String
    public var targetMode: PromotionTargetMode
    public var seasons: [Season]
    public var changes: [Change]

    public init(guestId: String, memberName: String, confirmedRuns: Int, previewToken: String, targetMode: PromotionTargetMode, seasons: [Season], changes: [Change]) {
        self.guestId = guestId
        self.memberName = memberName
        self.confirmedRuns = confirmedRuns
        self.previewToken = previewToken
        self.targetMode = targetMode
        self.seasons = seasons
        self.changes = changes
    }
}

public struct GuestImportEntry: Codable, Hashable, Sendable {
    public var spreadsheetId: String
    public var seasonSheetId: Int
    public var runId: String
    public var expectedDate: String
    public var expectedRun: String
    public var assignment = "existing_unnamed_slot"
    public init(identity: RunIdentity, expectedDate: String, expectedRun: String) {
        spreadsheetId = identity.spreadsheetId; seasonSheetId = identity.seasonSheetId; runId = identity.runId
        self.expectedDate = expectedDate; self.expectedRun = expectedRun
    }
}

public struct SharedGuestConflict: Codable, Hashable, Sendable, Error, LocalizedError {
    public var reason: String
    public var message: String
    public var state: SheetState?
    public var guestIds: [String]?
    public var memberName: String?
    public var operationId: String?
    public var errorDescription: String? { message }

    public init(reason: String, message: String, state: SheetState? = nil, guestIds: [String]? = nil, memberName: String? = nil, operationId: String? = nil) {
        self.reason = reason
        self.message = message
        self.state = state
        self.guestIds = guestIds
        self.memberName = memberName
        self.operationId = operationId
    }
}

public struct GuestImportPreview: Codable, Hashable, Sendable {
    public struct Change: Codable, Hashable, Sendable {
        public var spreadsheetId: String
        public var seasonSheetId: Int
        public var runId: String
        public var expectedDate: String
        public var expectedRun: String
        public var assignment: String
        public var alreadyAssigned: Bool
        public var unnamedBefore: Int
        public var unnamedAfter: Int
    
        public init(spreadsheetId: String, seasonSheetId: Int, runId: String, expectedDate: String, expectedRun: String, assignment: String, alreadyAssigned: Bool, unnamedBefore: Int, unnamedAfter: Int) {
            self.spreadsheetId = spreadsheetId
            self.seasonSheetId = seasonSheetId
            self.runId = runId
            self.expectedDate = expectedDate
            self.expectedRun = expectedRun
            self.assignment = assignment
            self.alreadyAssigned = alreadyAssigned
            self.unnamedBefore = unnamedBefore
            self.unnamedAfter = unnamedAfter
        }
    }
    public var guestId: String
    public var baseGuestRevision: Int
    public var baseRevision: String
    public var entries: [GuestImportEntry]
    public var changes: [Change]
    public var confirmedRuns: Int

    public init(guestId: String, baseGuestRevision: Int, baseRevision: String, entries: [GuestImportEntry], changes: [Change], confirmedRuns: Int) {
        self.guestId = guestId
        self.baseGuestRevision = baseGuestRevision
        self.baseRevision = baseRevision
        self.entries = entries
        self.changes = changes
        self.confirmedRuns = confirmedRuns
    }
}
