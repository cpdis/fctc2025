import Foundation
import SwiftData

extension SyncEngine {
    // MARK: Queue loop

    func persistAndStart(_ pending: PendingSubmission) throws -> UUID {
        modelContext.insert(pending)
        try modelContext.save()
        eventBroadcaster.yield(.queued(id: pending.id))
        startAutomaticDrainIfNeeded()
        return pending.id
    }

    func startAutomaticDrainIfNeeded() {
        scheduleDrain(force: false)
    }

    func scheduleDrain(force: Bool) {
        guard force || automaticallyDrains else { return }
        if isDraining {
            drainRequested = true
            return
        }
        guard !isDrainScheduled else { return }
        isDrainScheduled = true
        Task { await self.runScheduledDrain() }
    }

    func runScheduledDrain() async {
        isDrainScheduled = false
        await drain()
    }

    func drain(id: UUID) async {
        var transportAttempt = 1
        var shouldDelay = false
        var didAutoRetryMergeConflict = false

        while transportAttempt <= retryPolicy.maxAttempts {
            if shouldDelay {
                do {
                    try await clock.sleep(for: retryPolicy.delay(forAttempt: transportAttempt))
                } catch {
                    try? markQueued(id: id, message: UserFacingError.offline)
                    eventBroadcaster.yield(.parked(id: id, message: UserFacingError.offline))
                    return
                }
            }
            shouldDelay = false

            let submission: AttendanceSubmission
            do {
                guard let snapshot = try prepareAttempt(id: id, at: await clock.now()) else {
                    return
                }
                submission = snapshot
            } catch {
                eventBroadcaster.yield(.serviceFailed(message: UserFacingError.sync(error)))
                return
            }

            do {
                let outcome = try await api.submitAttendance(submission)
                switch outcome {
                case .written(_, let revision):
                    try finish(id: id, submission: submission, revision: revision)
                    eventBroadcaster.yield(.written(id: id))
                case .conflict(let reason, let message, let state):
                    let seenAt = await clock.now()
                    if reason == "stale_revision", !state.supportsSharedGuests, state.satisfies(submission) {
                        // The server can commit a write before its response is lost.
                        // Its retry then conflicts on the old revision even though the
                        // absolute payload is already present. Treat that as success.
                        try finishSatisfiedConflict(
                            id: id,
                            submission: submission,
                            state: state,
                            seenAt: seenAt
                        )
                        eventBroadcaster.yield(.written(id: id))
                    } else if reason == "stale_revision", !state.supportsSharedGuests,
                              submission.mode == .merge,
                              state.canSafelyRebaseMerge(submission),
                              !didAutoRetryMergeConflict {
                        // Attendance and guest merge fields are monotone. Distance
                        // is an absolute value, so retry only when it has no newer
                        // server value to overwrite.
                        try rebaseMergeConflict(
                            id: id,
                            state: state,
                            seenAt: seenAt
                        )
                        didAutoRetryMergeConflict = true
                        continue
                    } else {
                        try recordConflict(
                            id: id,
                            reason: reason,
                            message: message,
                            state: state,
                            seenAt: seenAt
                        )
                        eventBroadcaster.yield(
                            .conflict(id: id, reason: reason, message: message, state: state)
                        )
                    }
                }
                return
            } catch let error as SheetAPIError {
                let message = UserFacingError.sync(error)
                try? markQueued(id: id, message: message)
                if case .badSecret = error {
                    eventBroadcaster.yield(.authenticationRequired(id: id))
                    return
                }
                if !error.isRetryable {
                    eventBroadcaster.yield(.failed(id: id, message: message))
                    return
                }
                if transportAttempt == retryPolicy.maxAttempts {
                    eventBroadcaster.yield(.parked(id: id, message: message))
                    return
                }
                transportAttempt += 1
                shouldDelay = true
            } catch {
                // A custom test client can throw an untyped transport error. Treat it
                // like a network failure; the concrete SheetAPI already normalizes it.
                try? markQueued(id: id, message: UserFacingError.offline)
                if transportAttempt == retryPolicy.maxAttempts {
                    eventBroadcaster.yield(.parked(id: id, message: UserFacingError.offline))
                    return
                }
                transportAttempt += 1
                shouldDelay = true
            }
        }
    }

    func prepareAttempt(id: UUID, at date: Date) throws -> AttendanceSubmission? {
        guard let pending = try pending(id: id), pending.status == .queued else { return nil }
        pending.status = .inFlight
        pending.lastAttemptAt = date
        pending.attemptCount += 1
        pending.lastError = nil
        pending.clearConflict()
        let snapshot = AttendanceSubmission(pending)
        try modelContext.save()
        return snapshot
    }

    func markQueued(id: UUID, message: String) throws {
        guard let pending = try pending(id: id) else { return }
        pending.status = .queued
        pending.lastError = message
        try modelContext.save()
    }

    func finish(
        id: UUID,
        submission: AttendanceSubmission,
        revision: String
    ) throws {
        guard let pending = try pending(id: id) else { return }
        pending.status = .done
        pending.outcomeRaw = SubmissionDisposition.committed.rawValue
        pending.lastError = nil
        pending.baseRevision = revision
        pending.clearConflict()
        try rebaseQueuedSubmissions(from: submission.baseRevision, to: revision)

        let runs = try modelContext.fetch(FetchDescriptor<ScheduledRun>())
        if let run = runs.first(where: { $0.rowIndex == submission.rowIndex }) {
            switch submission.mode {
            case .merge:
                run.attendees = Array(Set(run.attendees).union(submission.attendees))
                    .sorted(by: Member.sheetOrder)
                if let plusOnes = submission.plusOnes {
                    run.plusOnes = max(run.plusOnes, plusOnes)
                }
            case .overwrite:
                run.attendees = submission.attendees.sorted(by: Member.sheetOrder)
                if let plusOnes = submission.plusOnes { run.plusOnes = plusOnes }
            }
            if let actualKm = submission.actualKm { run.actualKm = actualKm }
        }
        for run in runs { run.cachedRevision = revision }
        try modelContext.save()
    }

    func finishSatisfiedConflict(
        id: UUID,
        submission: AttendanceSubmission,
        state: SheetState,
        seenAt: Date
    ) throws {
        try reconcile(state, seenAt: seenAt)
        guard let pending = try pending(id: id) else { return }
        pending.status = .done
        pending.outcomeRaw = SubmissionDisposition.committed.rawValue
        pending.lastError = nil
        pending.baseRevision = state.sheetRevision
        pending.clearConflict()
        try rebaseQueuedSubmissions(
            from: submission.baseRevision,
            to: state.sheetRevision
        )
        try modelContext.save()
    }

    func recordConflict(
        id: UUID,
        reason: String,
        message: String,
        state: SheetState,
        seenAt: Date
    ) throws {
        try reconcile(state, seenAt: seenAt)
        guard let pending = try pending(id: id) else { return }
        pending.status = .conflict
        pending.lastError = message
        pending.attachConflict(reason: reason, message: message, state: state)
        try modelContext.save()
    }

    func rebaseMergeConflict(
        id: UUID,
        state: SheetState,
        seenAt: Date
    ) throws {
        try reconcile(state, seenAt: seenAt)
        guard let pending = try pending(id: id) else { return }
        pending.status = .queued
        pending.baseRevision = state.sheetRevision
        pending.lastError = nil
        pending.clearConflict()
        try modelContext.save()
    }

    func pending(id: UUID) throws -> PendingSubmission? {
        var descriptor = FetchDescriptor<PendingSubmission>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    /// An accepted local write is the only change between these two revisions.
    /// Advance sibling snapshots built from the same revision so the ordered queue
    /// does not conflict with its own preceding write.
    func rebaseQueuedSubmissions(
        from oldRevision: String?,
        to newRevision: String
    ) throws {
        let queued = SubmissionStatus.queued.rawValue
        let descriptor = FetchDescriptor<PendingSubmission>(
            predicate: #Predicate {
                $0.stateRaw == queued && $0.baseRevision == oldRevision
            }
        )
        for pending in try modelContext.fetch(descriptor) where pending.runIdentity == nil {
            pending.baseRevision = newRevision
        }
    }

}

extension SheetState {
    func canSafelyRebaseMerge(_ submission: AttendanceSubmission) -> Bool {
        guard let submittedDistance = submission.actualKm else { return true }
        let run = runs.first {
            $0.rowIndex == submission.rowIndex
                && $0.date == submission.expectedDate
                && $0.run == submission.expectedRun
        }
        guard let serverDistance = run?.actualKm else { return true }
        return serverDistance == submittedDistance
    }

    func satisfies(_ submission: AttendanceSubmission) -> Bool {
        guard let run = runs.first(where: {
            $0.rowIndex == submission.rowIndex
                && $0.date == submission.expectedDate
                && $0.run == submission.expectedRun
        }) else {
            return false
        }

        let submittedAttendees = Set(submission.attendees)
        let storedAttendees = Set(run.attendees)
        let attendeesMatch: Bool
        switch submission.mode {
        case .merge:
            attendeesMatch = submittedAttendees.isSubset(of: storedAttendees)
        case .overwrite:
            attendeesMatch = submittedAttendees == storedAttendees
        }
        guard attendeesMatch else { return false }

        if let plusOnes = submission.plusOnes {
            switch submission.mode {
            case .merge:
                guard run.plusOnes >= plusOnes else { return false }
            case .overwrite:
                guard run.plusOnes == plusOnes else { return false }
            }
        }
        if let actualKm = submission.actualKm, run.actualKm != actualKm {
            return false
        }
        return true
    }
}
