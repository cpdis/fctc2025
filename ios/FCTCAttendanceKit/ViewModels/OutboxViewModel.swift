//
//  OutboxViewModel.swift
//  FCTCAttendanceKit
//

import Foundation
import Observation

@MainActor
@Observable
public final class OutboxViewModel {
    public private(set) var isResolving = false
    public private(set) var errorMessage: String?

    @ObservationIgnored private var engine: any SyncEngineClient
    @ObservationIgnored private let eventMonitor = SyncEventMonitor()

    public init(engine: any SyncEngineClient) {
        self.engine = engine
        observeEvents()
    }

    public func replaceEngine(_ engine: any SyncEngineClient) {
        self.engine = engine
        observeEvents()
    }

    /// Done rows remain useful history in SwiftData. The screen intentionally shows
    /// only work that still needs attention.
    public func outstanding(
        from submissions: [PendingSubmissionSnapshot]
    ) -> [PendingSubmissionSnapshot] {
        submissions.filter(\.isOutstanding).sorted { $0.createdAt < $1.createdAt }
    }

    public func conflictDiff(for submission: PendingSubmissionSnapshot) -> ConflictDiff {
        let serverRun = matchingServerRun(for: submission)
        let server = Set(serverRun?.attendees ?? [])
        let local = Set(submission.attendees)
        return ConflictDiff(
            attendance: AttendanceDiff(
                added: local.subtracting(server).count,
                removed: server.subtracting(local).count
            ),
            localPlusOnes: submission.plusOnes,
            serverPlusOnes: serverRun?.plusOnes ?? 0,
            localActualKm: submission.actualKm,
            serverActualKm: serverRun?.actualKm
        )
    }

    public func canRetry(_ submissions: [PendingSubmissionSnapshot]) -> Bool {
        submissions.contains { $0.status == .queued || $0.status == .inFlight }
    }

    @discardableResult
    public func resolve(
        id: UUID,
        action: ConflictResolutionAction
    ) async throws -> UUID? {
        isResolving = true
        errorMessage = nil
        defer { isResolving = false }
        do {
            return try await engine.resolveConflict(id: id, action: action)
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    public func retry() async {
        await engine.drain()
    }

    private func matchingServerRun(
        for submission: PendingSubmissionSnapshot
    ) -> RunRecord? {
        guard let state = submission.conflictState else { return nil }
        return state.runs.first {
            $0.date == submission.expectedDate && $0.run == submission.expectedRun
        } ?? state.runs.first { $0.rowIndex == submission.rowIndex }
    }

    private func observeEvents() {
        eventMonitor.start(engine: engine) { [weak self] event in
            switch event {
            case .failed(_, let message), .parked(_, let message),
                 .conflict(_, _, let message, _):
                self?.errorMessage = message
            case .written:
                self?.errorMessage = nil
            case .queued, .rosterRefreshed:
                break
            }
        }
    }
}
