//
//  SyncEngine.swift
//  FCTCAttendanceKit
//
//  SwiftData cache and durable outbox. The sheet remains canonical; this actor only
//  stores a reconstructible cache plus submissions still owed to the sheet.
//


import Foundation
import SwiftData

// MARK: - Engine

public actor SyncEngine: ModelActor, SyncEngineClient {
    public nonisolated let modelExecutor: any ModelExecutor
    public nonisolated let modelContainer: ModelContainer
    public nonisolated var events: AsyncStream<SyncEvent> { eventBroadcaster.stream() }

    private nonisolated let eventBroadcaster: SyncEventBroadcaster
    private let api: any SheetAPIClient
    private let clock: any SyncClock
    private let retryPolicy: RetryPolicy
    private let automaticallyDrains: Bool
    private let runReminderScheduler: any RunReminderScheduling
    private let dateFormatter: DateFormatter
    private var isDraining = false
    private var isDrainScheduled = false
    private var drainRequested = false

    public init(
        modelContainer: ModelContainer,
        api: any SheetAPIClient,
        clock: any SyncClock = SystemSyncClock(),
        retryPolicy: RetryPolicy = .default,
        automaticallyDrains: Bool = true,
        runReminderScheduler: any RunReminderScheduling = NoopRunReminderScheduler()
    ) {
        self.eventBroadcaster = SyncEventBroadcaster()
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.dateFormat = "EEE, d-MMM-yyyy"
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: context)
        self.modelContainer = modelContainer
        self.api = api
        self.clock = clock
        self.retryPolicy = retryPolicy
        self.automaticallyDrains = automaticallyDrains
        self.runReminderScheduler = runReminderScheduler
        self.dateFormatter = dateFormatter
    }

    deinit {
        eventBroadcaster.finish()
    }

    public func refreshState() async throws -> SheetState {
        let state = try await api.getState()
        let seenAt = await clock.now()
        try reconcile(state, seenAt: seenAt)
        try modelContext.save()
        eventBroadcaster.yield(.rosterRefreshed(state))
        _ = await runReminderScheduler.reconcile(state: state, now: seenAt)
        startAutomaticDrainIfNeeded()
        return state
    }

    /// Compatibility spelling from the U1 seam.
    public func refresh() async throws -> SheetState {
        try await refreshState()
    }

    public func enqueue(_ submission: AttendanceSubmission) async throws -> UUID {
        let pending = PendingSubmission(
            rowIndex: submission.rowIndex,
            expectedDate: submission.expectedDate,
            expectedRun: submission.expectedRun,
            attendees: submission.attendees,
            plusOnes: submission.plusOnes,
            actualKm: submission.actualKm,
            mode: submission.mode,
            baseRevision: submission.baseRevision,
            createdAt: await clock.now()
        )
        // Preserve a nil wire value as "no opinion" instead of deriving zero guests.
        pending.plusOnesValue = submission.plusOnes
        return try persistAndStart(pending)
    }

    public func enqueue(
        draft: AttendanceDraft,
        mode: SubmissionMode = .merge,
        deviceName: String? = nil
    ) async throws -> UUID {
        let pending = PendingSubmission.from(
            draft: draft,
            mode: mode,
            deviceName: deviceName,
            createdAt: await clock.now()
        )
        return try persistAndStart(pending)
    }

    public func drain() async {
        guard !isDraining else {
            drainRequested = true
            return
        }
        isDraining = true
        defer {
            isDraining = false
            if drainRequested {
                drainRequested = false
                scheduleDrain(force: true)
            }
        }

        do {
            let queued = SubmissionStatus.queued.rawValue
            let inFlight = SubmissionStatus.inFlight.rawValue
            let rows = try modelContext.fetch(
                FetchDescriptor<PendingSubmission>(
                    predicate: #Predicate {
                        $0.stateRaw == queued || $0.stateRaw == inFlight
                    },
                    sortBy: [SortDescriptor(\.createdAt)]
                )
            )
            // An app termination can leave a row marked in-flight. Requeue it because
            // the payload is absolute and safe to send again.
            let ids = rows.compactMap { row -> UUID? in
                if row.status == .inFlight { row.status = .queued }
                return row.status == .queued ? row.id : nil
            }
            try modelContext.save()

            for id in ids {
                await drain(id: id)
            }
        } catch {
            // A cache error cannot safely identify one row. The next foreground or
            // explicit refresh gets another chance to open and drain the store.
            eventBroadcaster.yield(.serviceFailed(message: UserFacingError.sync(error)))
        }
    }

    /// Insert immediately for responsive UI, then replace coordinates with the
    /// authoritative roster returned by the sheet.
    public func addMember(name: String) async throws -> AddMemberResult {
        let inserted = try optimisticInsertMember(name: name)
        do {
            let result = try await api.addMember(name: name)
            try reconcileRoster(result.roster, seenAt: await clock.now())
            try updateCachedRevision(result.sheetRevision)
            try modelContext.save()
            return result
        } catch {
            // A failed sheet write must not leave a local-only person that the UI
            // mistakes for a canonical member on the next attempt.
            if inserted { try? rollbackOptimisticMember(name: name) }
            throw error
        }
    }

    public func addRun(_ request: AddRunRequest) async throws -> AddRunResult {
        let result = try await api.addRun(request)
        let fallbackDate = await clock.now()
        let seasonYear = try cachedSeasonYear(fallbackDate: fallbackDate)
        try reconcileRuns(
            result.runs,
            revision: result.sheetRevision,
            seasonYear: seasonYear
        )
        try modelContext.save()
        return result
    }

    /// Close a conflict and, for merge or overwrite, queue the same local opinion
    /// against the fresh server revision. The old row remains retained history.
    public func resolveConflict(
        id: UUID,
        action: ConflictResolutionAction
    ) async throws -> UUID? {
        guard let conflicted = try pending(id: id), conflicted.status == .conflict else {
            throw SyncEngineError.conflictNotFound
        }

        if action == .discard {
            conflicted.status = .done
            conflicted.lastError = nil
            conflicted.clearConflict()
            try modelContext.save()
            return nil
        }

        guard let state = conflicted.conflictState else {
            throw SyncEngineError.missingConflictState
        }
        let serverRun = state.runs.first {
            $0.date == conflicted.expectedDate && $0.run == conflicted.expectedRun
        } ?? state.runs.first { $0.rowIndex == conflicted.rowIndex }

        let replacement = PendingSubmission(
            rowIndex: serverRun?.rowIndex ?? conflicted.rowIndex,
            expectedDate: serverRun?.date ?? conflicted.expectedDate,
            expectedRun: serverRun?.run ?? conflicted.expectedRun,
            attendees: conflicted.attendees,
            guestNames: conflicted.guestNames,
            plusOnes: conflicted.plusOnes,
            actualKm: conflicted.actualKm,
            mode: action == .overwrite ? .overwrite : .merge,
            status: .queued,
            baseRevision: state.sheetRevision,
            createdAt: await clock.now(),
            deviceName: conflicted.deviceName
        )
        // Preserve a nil wire value as "no opinion".
        replacement.plusOnesValue = conflicted.plusOnes
        conflicted.status = .done
        conflicted.lastError = nil
        conflicted.clearConflict()
        modelContext.insert(replacement)
        try modelContext.save()
        eventBroadcaster.yield(.queued(id: replacement.id))
        startAutomaticDrainIfNeeded()
        return replacement.id
    }

    // MARK: Queue loop

    private func persistAndStart(_ pending: PendingSubmission) throws -> UUID {
        modelContext.insert(pending)
        try modelContext.save()
        eventBroadcaster.yield(.queued(id: pending.id))
        startAutomaticDrainIfNeeded()
        return pending.id
    }

    private func startAutomaticDrainIfNeeded() {
        scheduleDrain(force: false)
    }

    private func scheduleDrain(force: Bool) {
        guard force || automaticallyDrains else { return }
        if isDraining {
            drainRequested = true
            return
        }
        guard !isDrainScheduled else { return }
        isDrainScheduled = true
        Task { await self.runScheduledDrain() }
    }

    private func runScheduledDrain() async {
        isDrainScheduled = false
        await drain()
    }

    private func drain(id: UUID) async {
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
                    if reason == "stale_revision", state.satisfies(submission) {
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
                    } else if reason == "stale_revision",
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

    private func prepareAttempt(id: UUID, at date: Date) throws -> AttendanceSubmission? {
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

    private func markQueued(id: UUID, message: String) throws {
        guard let pending = try pending(id: id) else { return }
        pending.status = .queued
        pending.lastError = message
        try modelContext.save()
    }

    private func finish(
        id: UUID,
        submission: AttendanceSubmission,
        revision: String
    ) throws {
        guard let pending = try pending(id: id) else { return }
        pending.status = .done
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

    private func finishSatisfiedConflict(
        id: UUID,
        submission: AttendanceSubmission,
        state: SheetState,
        seenAt: Date
    ) throws {
        try reconcile(state, seenAt: seenAt)
        guard let pending = try pending(id: id) else { return }
        pending.status = .done
        pending.lastError = nil
        pending.baseRevision = state.sheetRevision
        pending.clearConflict()
        try rebaseQueuedSubmissions(
            from: submission.baseRevision,
            to: state.sheetRevision
        )
        try modelContext.save()
    }

    private func recordConflict(
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

    private func rebaseMergeConflict(
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

    private func pending(id: UUID) throws -> PendingSubmission? {
        var descriptor = FetchDescriptor<PendingSubmission>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    /// An accepted local write is the only change between these two revisions.
    /// Advance sibling snapshots built from the same revision so the ordered queue
    /// does not conflict with its own preceding write.
    private func rebaseQueuedSubmissions(
        from oldRevision: String?,
        to newRevision: String
    ) throws {
        let queued = SubmissionStatus.queued.rawValue
        let descriptor = FetchDescriptor<PendingSubmission>(
            predicate: #Predicate {
                $0.stateRaw == queued && $0.baseRevision == oldRevision
            }
        )
        for pending in try modelContext.fetch(descriptor) {
            pending.baseRevision = newRevision
        }
    }

    // MARK: Cache reconciliation

    private func reconcile(_ state: SheetState, seenAt: Date) throws {
        try reconcileRoster(state.roster, seenAt: seenAt)
        try reconcileRuns(
            state.runs,
            revision: state.sheetRevision,
            seasonYear: state.seasonYear
        )
    }

    private func reconcileRoster(_ roster: [RosterEntry], seenAt: Date) throws {
        let local = try modelContext.fetch(FetchDescriptor<Member>())
        let remoteKeys = Set(roster.map { canonicalName($0.name) })
        var localByKey: [String: Member] = [:]
        for member in local {
            let key = canonicalName(member.name)
            if localByKey[key] == nil { localByKey[key] = member }
        }

        for entry in roster {
            let key = canonicalName(entry.name)
            if let member = localByKey[key] {
                member.name = entry.name
                member.colIndex = entry.colIndex
                member.isNew = false
                member.lastSeenAt = seenAt
            } else {
                modelContext.insert(
                    Member(name: entry.name, colIndex: entry.colIndex, lastSeenAt: seenAt)
                )
            }
        }
        for member in local where !member.isNew && !remoteKeys.contains(canonicalName(member.name)) {
            modelContext.delete(member)
        }
    }

    private func reconcileRuns(
        _ records: [RunRecord],
        revision: String,
        seasonYear: Int
    ) throws {
        let local = try modelContext.fetch(FetchDescriptor<ScheduledRun>())
        let remoteRows = Set(records.map(\.rowIndex))
        let localByRow = Dictionary(uniqueKeysWithValues: local.map { ($0.rowIndex, $0) })

        for record in records {
            if let run = localByRow[record.rowIndex] {
                apply(record, revision: revision, seasonYear: seasonYear, to: run)
            } else {
                let run = ScheduledRun(
                    rowIndex: record.rowIndex,
                    date: record.date,
                    meet: record.meet,
                    run: record.run
                )
                apply(record, revision: revision, seasonYear: seasonYear, to: run)
                modelContext.insert(run)
            }
        }
        for run in local where !remoteRows.contains(run.rowIndex) {
            modelContext.delete(run)
        }
    }

    private func apply(
        _ record: RunRecord,
        revision: String,
        seasonYear: Int,
        to run: ScheduledRun
    ) {
        run.date = record.date
        if seasonYear > 0 {
            run.scheduledAt = parseDate(record.date, seasonYear: seasonYear)
        }
        run.meet = record.meet
        run.run = record.run
        run.approxKm = record.approxKm
        run.actualKm = record.actualKm
        run.attendees = record.attendees
        run.plusOnes = record.plusOnes
        run.cachedRevision = revision
    }

    private func optimisticInsertMember(name: String) throws -> Bool {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let members = try modelContext.fetch(FetchDescriptor<Member>())
        guard !members.contains(where: { canonicalName($0.name) == canonicalName(cleanName) }) else {
            return false
        }

        let sorted = (members.map(\.name) + [cleanName]).sorted(by: Member.sheetOrder)
        let position = sorted.firstIndex(of: cleanName) ?? members.count
        let firstColumn = members.map(\.colIndex).min() ?? 1
        let newColumn = firstColumn + position
        for member in members where member.colIndex >= newColumn { member.colIndex += 1 }
        modelContext.insert(Member(name: cleanName, colIndex: newColumn, isNew: true))
        try modelContext.save()
        return true
    }

    private func rollbackOptimisticMember(name: String) throws {
        let key = canonicalName(name)
        let members = try modelContext.fetch(FetchDescriptor<Member>())
        guard let inserted = members.first(where: {
            $0.isNew && canonicalName($0.name) == key
        }) else {
            return
        }

        let removedColumn = inserted.colIndex
        modelContext.delete(inserted)
        for member in members where member !== inserted && member.colIndex > removedColumn {
            member.colIndex -= 1
        }
        try modelContext.save()
    }

    private func cachedSeasonYear(fallbackDate: Date) throws -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let runs = try modelContext.fetch(
            FetchDescriptor<ScheduledRun>(sortBy: [SortDescriptor(\.rowIndex)])
        )
        if let scheduledAt = runs.compactMap(\.scheduledAt).first {
            return calendar.component(.year, from: scheduledAt)
        }
        return calendar.component(.year, from: fallbackDate)
    }

    private func updateCachedRevision(_ revision: String) throws {
        for run in try modelContext.fetch(FetchDescriptor<ScheduledRun>()) {
            run.cachedRevision = revision
        }
    }

    private func canonicalName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private func parseDate(_ value: String, seasonYear: Int) -> Date? {
        guard seasonYear > 0 else { return nil }
        return dateFormatter.date(from: "\(value)-\(seasonYear)")
    }
}

public enum SyncEngineError: LocalizedError, Sendable, Equatable {
    case conflictNotFound
    case missingConflictState

    public var errorDescription: String? {
        switch self {
        case .conflictNotFound: "This conflict no longer needs resolution."
        case .missingConflictState: "This conflict has no server snapshot. Refresh and try again."
        }
    }
}

private extension SheetState {
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
