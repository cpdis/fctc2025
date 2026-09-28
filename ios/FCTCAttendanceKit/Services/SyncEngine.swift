//
//  SyncEngine.swift
//  FCTCAttendanceKit
//
//  SwiftData cache and durable outbox. The sheet remains canonical; this actor only
//  stores a reconstructible cache plus irreplaceable submissions and recovery evidence.
//


import Foundation
import SwiftData

// MARK: - Engine

public actor SyncEngine: ModelActor, SyncEngineClient {
    public nonisolated let modelExecutor: any ModelExecutor
    public nonisolated let modelContainer: ModelContainer
    public nonisolated var events: AsyncStream<SyncEvent> { eventBroadcaster.stream() }

    nonisolated let eventBroadcaster: SyncEventBroadcaster
    let api: any SheetAPIClient
    let clock: any SyncClock
    let retryPolicy: RetryPolicy
    let automaticallyDrains: Bool
    let runReminderScheduler: any RunReminderScheduling
    let dateFormatter: DateFormatter
    var isDraining = false
    var isDrainScheduled = false
    var drainRequested = false
    var latestState: SheetState?

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
        try await refreshState(seasonSheetId: nil)
    }

    public func refreshState(seasonSheetId: Int?) async throws -> SheetState {
        let state = try await api.getState(seasonSheetId: seasonSheetId)
        latestState = state
        let seenAt = await clock.now()
        try reconcile(state, seenAt: seenAt)
        try modelContext.save()
        eventBroadcaster.yield(.rosterRefreshed(state))
        _ = await runReminderScheduler.reconcile(state: state, now: seenAt)
        startAutomaticDrainIfNeeded()
        return state
    }

    /// Last season's state for the Dashboard's "Vs last year" card. Nil means
    /// unavailable: a legacy endpoint, or no earlier season in `supportedSeasons`.
    ///
    /// A read-only snapshot. It upserts only that season's `SharedSheetCache` row.
    /// It never calls `reconcile`, never sets `latestState` and never reschedules
    /// reminders, so members, cached runs and the live season stay exactly as the
    /// last live refresh left them. A finished season does not change, so the row
    /// is fetched once and read from the cache after that.
    public func previousSeasonSnapshot() async throws -> SheetState? {
        // Anchor on the newest cached season, not `latestState`: historic
        // navigation points `latestState` at an older season.
        guard let endpoint = api.endpointIdentity, let live = try newestSharedState(),
              live.supportsSharedGuests, let book = live.spreadsheetId else { return nil }
        // The newest listed season older than the live one. Gaps are allowed.
        guard let previous = (live.supportedSeasons ?? [])
            .filter({ $0.seasonYear < live.seasonYear })
            .max(by: { $0.seasonYear < $1.seasonYear }) else { return nil }
        if let cached = try sharedSheetCache(
            endpoint: endpoint, spreadsheetId: book, seasonSheetId: previous.seasonSheetId
        )?.state {
            return cached
        }
        let state = try await api.getState(seasonSheetId: previous.seasonSheetId)
        // Never cache another season or workbook under last season's key.
        guard state.spreadsheetId == book, state.seasonSheetId == previous.seasonSheetId else {
            throw SheetAPIError.badPayload(message: "The sheet did not return last season.")
        }
        try upsertSharedSheetCache(state, endpoint: endpoint, seenAt: await clock.now())
        try modelContext.save()
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
        pending.endpointIdentity = api.endpointIdentity
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
        if pending.endpointIdentity == nil { pending.endpointIdentity = api.endpointIdentity }
        if let identity = pending.runIdentity {
            try prepareGuestDependencies(draft.guests, identity: identity)
        }
        return try persistAndStart(pending)
    }

    public func drain() async {
        guard !isDraining else {
            drainRequested = true
            return
        }
        isDraining = true
        eventBroadcaster.setActivity(true)
        defer {
            isDraining = false
            eventBroadcaster.setActivity(false)
            if drainRequested {
                drainRequested = false
                scheduleDrain(force: true)
            }
        }

        do {
            try prepareLegacyRecovery()
            await drainGuestOperations()
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
            // Legacy absolute writes retain their old retry protocol. Shared writes
            // keep their dispatch state so restart checks the receipt first.
            let ids = rows.compactMap { row -> UUID? in
                if row.status == .inFlight && row.runIdentity == nil { row.status = .queued }
                return row.id
            }
            try modelContext.save()

            for id in ids {
                guard let row = try pending(id: id) else { continue }
                guard row.endpointIdentity == api.endpointIdentity, row.endpointIdentity != nil else {
                    try parkForReview(row, message: "Review this saved submission before sending it to the current sheet.")
                    continue
                }
                if row.runIdentity != nil { await drainSharedAttendance(id: id) }
                else if try currentSharedState()?.supportsSharedGuests == true {
                    try parkForReview(row, message: "Choose the original season and run before recovering this submission.")
                } else { await drain(id: id) }
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
        if let state = try currentSharedState(), state.supportsSharedGuests {
            return try await addSharedMember(name: name, state: state)
        }
        let inserted = try optimisticInsertMember(name: name)
        do {
            let result = try await api.addMember(name: name)
            // addMember answers with the roster only. No totals means "leave the
            // cached numbers alone", and the new member starts at zero.
            try reconcileRoster(result.roster, totals: [], seenAt: await clock.now())
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
        if let state = try currentSharedState(), state.supportsSharedGuests {
            return try await addSharedRun(request, state: state)
        }
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
            conflicted.outcomeRaw = SubmissionDisposition.discarded.rawValue
            conflicted.lastError = nil
            conflicted.clearConflict()
            try modelContext.save()
            return nil
        }

        guard let state = conflicted.conflictState else {
            throw SyncEngineError.missingConflictState
        }
        if conflicted.runIdentity != nil {
            return try await resolveSharedConflict(conflicted, action: action, state: state)
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
        replacement.endpointIdentity = conflicted.endpointIdentity
        conflicted.status = .done
        conflicted.outcomeRaw = SubmissionDisposition.superseded.rawValue
        conflicted.lastError = nil
        conflicted.clearConflict()
        modelContext.insert(replacement)
        try modelContext.save()
        eventBroadcaster.yield(.queued(id: replacement.id))
        startAutomaticDrainIfNeeded()
        return replacement.id
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
