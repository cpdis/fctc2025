//
//  RunCancellationSync.swift
//  FCTCAttendanceKit
//
//  Cancel or restore a shared run (docs/plans/2026-11-23-1050-feat-run-cancelled-plan.md,
//  KTD7). It rides the guest operation queue for its receipt, like `addSharedRun`,
//  but it is never kept for later: a cancel that lands after the organiser saw an
//  error could hide attendance recorded in the meantime.
//
//    drain result      what happens
//    ----------------  ------------------------------------------------------
//    completed         refresh the run's season and return it (or, if that read
//                      fails, the held season with the Run cell as written)
//    checking          delivery unknown: keep it for the receipt check, throw
//    anything else     close it (superseded, so no drain sends it) and throw
//

import Foundation
import SwiftData

/// A cancel or restore the sheet did not apply. Nothing is left queued.
public enum RunCancellationError: LocalizedError, Sendable, Equatable {
    /// It never reached the sheet: offline, or behind another saved change.
    case notSent
    /// The sheet refused it, with this reason: busy, a rejected setup code, or for good.
    case refused(String)

    public var errorDescription: String? {
        switch self {
        case .notSent: "The run was not changed. Try again when the sheet is reachable."
        case .refused(let message): message
        }
    }
}

extension SyncEngine {
    public func setRunCancelled(_ run: RunSnapshot, cancelled: Bool) async throws -> SheetState {
        let state = try requireSharedState()
        guard state.capabilities?.canCancelRuns == true else {
            throw SheetAPIError.server(code: "update_required", message: "Update the sheet connection before you cancel runs.")
        }
        guard let identity = run.runIdentity, identity.spreadsheetId == state.spreadsheetId else {
            throw SheetAPIError.notConfigured
        }
        let operation = try SharedGuestOperation(action: "setRunCancelled", fields: [
            "spreadsheetId": .string(identity.spreadsheetId), "seasonSheetId": .number(Double(identity.seasonSheetId)),
            "runId": .string(identity.runId), "rowIndex": .number(Double(run.rowIndex)),
            "expectedDate": .string(run.date), "expectedRun": .string(run.run), "cancelled": .bool(cancelled),
        ])
        _ = try saveGuestOperation(operation, state: state)
        try modelContext.save()
        // The serial drain keeps older unknown outcomes ahead of this one. A drain
        // that is already running leaves this row queued; the close below stops it.
        await drain()
        guard let row = try guestOperationRecord(id: operation.id) else {
            throw SheetAPIError.badPayload(message: "Missing saved operation.")
        }
        switch row.phase {
        case .completed:
            // The change landed. A failed re-read must not report it as failed, so fall
            // back to the season as this phone holds it, with the Run cell as written.
            if let fresh = try? await refreshState(seasonSheetId: identity.seasonSheetId) { return fresh }
            var saved = state
            if let index = saved.runs.firstIndex(where: { $0.identity == identity }) {
                saved.runs[index].run = cancelled ? "\(run.runName) (cancelled)" : run.runName
            }
            return saved
        case .checking:
            throw SheetAPIError.server(code: "pending_verification", message: row.lastError ?? UserFacingError.checkingSavedChanges)
        default:
            let conflict = row.conflict, message = row.lastError
            row.phase = .superseded
            try modelContext.save()
            if let conflict { throw conflict }
            // Keep a refusal's own reason (busy, a rejected setup code). An offline or
            // fenced row has the outbox's wording, which does not fit a cancel.
            if let message, message != UserFacingError.offline, message != UserFacingError.checkingSavedChanges {
                throw RunCancellationError.refused(message)
            }
            throw RunCancellationError.notSent
        }
    }
}
