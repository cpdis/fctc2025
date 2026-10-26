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
    public private(set) var syncBanner: SyncBanner?
    /// True while the engine is draining, whether a Retry or an automatic drain
    /// started it. The only honest source for a "working" indicator.
    public private(set) var isSyncing = false

    @ObservationIgnored private var engine: any SyncEngineClient
    @ObservationIgnored private let eventMonitor = SyncEventMonitor()

    public init(engine: any SyncEngineClient) {
        self.engine = engine
        observeEvents()
    }

    public func replaceEngine(_ engine: any SyncEngineClient) {
        self.engine = engine
        // The old engine's drain no longer matters; the new one replays its own.
        isSyncing = false
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
        let serverRun = submission.conflictState?.run(matching: submission)
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
        // Checked before the first await: a double tap starts two tasks, and
        // only the first may resolve. The view ignores the cancellation.
        guard !isResolving else { throw CancellationError() }
        isResolving = true
        errorMessage = nil
        defer { isResolving = false }
        do {
            return try await engine.resolveConflict(id: id, action: action)
        } catch {
            errorMessage = UserFacingError.sync(error)
            throw error
        }
    }

    public func retry() async {
        syncBanner = nil
        await engine.drain()
    }

    private func observeEvents() {
        eventMonitor.start(engine: engine) { [weak self] event in
            guard let self else { return }
            if case .syncActivity(let isActive) = event {
                isSyncing = isActive
            } else if let banner = SyncBanner(event: event) {
                switch banner.kind {
                case .success:
                    // A write clears the Outbox instead of announcing itself:
                    // the row leaving the list is the confirmation here.
                    syncBanner = nil
                    errorMessage = nil
                case .error:
                    // Only a hard failure also sets the inline error.
                    syncBanner = banner
                    errorMessage = banner.message
                case .offline, .parked, .conflict, .authentication:
                    syncBanner = banner
                }
            }
        }
    }
}
