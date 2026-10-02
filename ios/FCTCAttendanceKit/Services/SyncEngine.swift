//
//  SyncEngine.swift
//  FCTCAttendanceKit
//
//  SwiftData cache and durable outbox. The sheet remains canonical; this actor only
//  stores a reconstructible cache plus irreplaceable submissions and recovery evidence.
//


import Foundation
import os
import SwiftData

// MARK: - Engine

public actor SyncEngine: ModelActor, SyncEngineClient {
    /// Row failures. Error codes are public; the endpoint is hashed; the secret never logs.
    static let logger = Logger(subsystem: "com.cpdis.fctc-attendance", category: "sync")

    /// Logs one outbox row's failure without the secret or the raw endpoint.
    func logRowFailure(id: UUID, error: any Error) {
        let code = (error as? SheetAPIError)?.code ?? "untyped"
        Self.logger.error(
            "Row \(id.uuidString, privacy: .public) failed: \(code, privacy: .public) at \(self.api.endpointIdentity ?? "none", privacy: .private(mask: .hash))"
        )
    }

    public nonisolated let modelExecutor: any ModelExecutor
    public nonisolated let modelContainer: ModelContainer
    public nonisolated var events: AsyncStream<SyncEvent> { eventBroadcaster.stream() }

    nonisolated let eventBroadcaster: SyncEventBroadcaster
    let api: any SheetAPIClient
    let clock: any SyncClock
    let retryPolicy: RetryPolicy
    /// The live refresh's retry (`readState`). Writes keep `retryPolicy`.
    let readRetryPolicy: RetryPolicy
    let automaticallyDrains: Bool
    let runReminderScheduler: any RunReminderScheduling
    var isDraining = false
    var isDrainScheduled = false
    var drainRequested = false
    /// Set by `quiesce()`: this engine never drains again.
    var isRetired = false
    /// `quiesce()` callers waiting for the running drain to end.
    var quiesceWaiters: [CheckedContinuation<Void, Never>] = []
    /// The engine this one replaced. The first drain waits for it to stop.
    var predecessor: (any SyncEngineClient)?
    var latestState: SheetState?
    /// `SharedSheetCache` keys of the last-season rows this engine fetched, so
    /// `previousSeasonSnapshot` revalidates each at most once per app session.
    var revalidatedSnapshots: Set<String> = []

    public init(
        modelContainer: ModelContainer,
        api: any SheetAPIClient,
        clock: any SyncClock = SystemSyncClock(),
        retryPolicy: RetryPolicy = .default,
        readRetryPolicy: RetryPolicy = .reads,
        automaticallyDrains: Bool = true,
        runReminderScheduler: any RunReminderScheduling = NoopRunReminderScheduler(),
        replacing predecessor: (any SyncEngineClient)? = nil
    ) {
        self.eventBroadcaster = SyncEventBroadcaster()
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: context)
        self.modelContainer = modelContainer
        self.api = api
        self.clock = clock
        self.retryPolicy = retryPolicy
        self.readRetryPolicy = readRetryPolicy
        self.automaticallyDrains = automaticallyDrains
        self.runReminderScheduler = runReminderScheduler
        self.predecessor = predecessor
    }

    deinit {
        eventBroadcaster.finish()
    }

    public func refreshState() async throws -> SheetState {
        try await refreshState(seasonSheetId: nil)
    }

    public func refreshState(seasonSheetId: Int?) async throws -> SheetState {
        // Stamp the cache with the time the request started, not the time it
        // landed. The server read the state after this instant, so the state
        // holds every write confirmed before it. A slow refresh that started
        // before a confirmation and lands after it then cannot retire that
        // write's overlay (`EffectiveRuns.applies`).
        let (state, requestedAt) = try await readState(seasonSheetId: seasonSheetId)
        latestState = state
        try reconcile(state, seenAt: requestedAt)
        // No season named: the server answered with its active season.
        if seasonSheetId == nil { try markLiveSeason(state, requestedAt: requestedAt) }
        try modelContext.save()
        eventBroadcaster.yield(.rosterRefreshed(state))
        // Reminders schedule from the present, so they read the clock again.
        _ = await runReminderScheduler.reconcile(state: state, now: await clock.now())
        startAutomaticDrainIfNeeded()
        return state
    }

    /// `api.getState`, retried on a transient failure (`SheetAPIError.isRetryable`:
    /// a dropped connection, a timeout, an HTTP error from Apps Script, a busy
    /// lock) under `readRetryPolicy`. A read changes nothing, so repeating it is
    /// safe. Returns the state and the start of the attempt that returned it,
    /// which `refreshState` stamps on the cache. A cancelled caller stops at once.
    private func readState(seasonSheetId: Int?) async throws -> (SheetState, Date) {
        var attempt = 1
        while true {
            let requestedAt = await clock.now()
            do {
                return (try await api.getState(seasonSheetId: seasonSheetId), requestedAt)
            } catch let error as SheetAPIError where error.isRetryable
                        && attempt < readRetryPolicy.maxAttempts && !Task.isCancelled {
                attempt += 1
                try await clock.sleep(for: readRetryPolicy.delay(forAttempt: attempt))
            }
        }
    }

    /// The newest listed season older than `year` (the live season when nil),
    /// as a read-only snapshot: the Dashboard's "Vs last year" for the season
    /// it shows. Nil means unavailable: a legacy endpoint, or no earlier season
    /// in `supportedSeasons`. See `snapshot(of:)` for the caching.
    public func previousSeasonSnapshot(before year: Int?) async throws -> SheetState? {
        guard let live = try snapshotAnchor() else { return nil }
        let limit = year ?? live.seasonYear
        // Gaps are allowed: the newest listed season before `limit`.
        guard let previous = (live.supportedSeasons ?? [])
            .filter({ $0.seasonYear < limit })
            .max(by: { $0.seasonYear < $1.seasonYear }) else { return nil }
        return try await snapshot(of: previous, in: live)
    }

    /// A listed season before the live one, as a read-only snapshot, for the
    /// Dashboard's season menu. Nil for the live season (read the live cache),
    /// a year the live state does not list, or a legacy endpoint.
    public func seasonSnapshot(year: Int) async throws -> SheetState? {
        guard let live = try snapshotAnchor(), year < live.seasonYear,
              let season = (live.supportedSeasons ?? []).first(where: { $0.seasonYear == year }) else { return nil }
        return try await snapshot(of: season, in: live)
    }

    /// The cached live season snapshots anchor on, not `latestState`: historic
    /// navigation points `latestState` at an older season. Nil without shared
    /// seasons.
    private func snapshotAnchor() throws -> SheetState? {
        guard api.endpointIdentity != nil, let live = try cachedLiveState(),
              live.supportsSharedGuests, live.spreadsheetId != nil else { return nil }
        return live
    }

    /// One season's state, read-only. It upserts only that season's
    /// `SharedSheetCache` row. It never calls `reconcile`, never sets
    /// `latestState` and never reschedules reminders, so members, cached runs
    /// and the live season stay exactly as the last live refresh left them.
    ///
    /// A cached row can be out of date: it may date from when that season was
    /// live, or from before a guest promotion rewrote its attendance. So the
    /// first call for a season on each engine (once per app session) fetches it
    /// again, and later calls read the row:
    ///
    ///   row cached   fetched on this engine   result
    ///   no           -                        fetch; throws when that fails
    ///   yes          yes                      the row, no request
    ///   yes          no                       fetch; the row when that fails,
    ///                                         and the next call tries again
    private func snapshot(of season: SupportedSeason, in live: SheetState) async throws -> SheetState {
        guard let endpoint = api.endpointIdentity, let book = live.spreadsheetId else {
            throw SheetAPIError.notConfigured
        }
        let key = SharedSheetCache.key(endpoint: endpoint, spreadsheetId: book, seasonSheetId: season.seasonSheetId)
        let cached = try sharedSheetCache(
            endpoint: endpoint, spreadsheetId: book, seasonSheetId: season.seasonSheetId
        )?.state
        if let cached, revalidatedSnapshots.contains(key) { return cached }
        // The request's start, as `refreshState` stamps it.
        let requestedAt = await clock.now()
        let state: SheetState
        do {
            state = try await api.getState(seasonSheetId: season.seasonSheetId)
            // Never cache another season or workbook under this season's key.
            guard state.spreadsheetId == book, state.seasonSheetId == season.seasonSheetId else {
                throw SheetAPIError.badPayload(message: "The sheet did not return the season it was asked for.")
            }
        } catch {
            // Offline or rejected: the cached row still serves the card.
            if let cached { return cached }
            throw error
        }
        try upsertSharedSheetCache(state, endpoint: endpoint, seenAt: requestedAt)
        try modelContext.save()
        revalidatedSnapshots.insert(key)
        return state
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

    /// Drains the outbox. One drain runs at a time per engine; a call that
    /// arrives mid-drain asks the running drain for one more pass and returns.
    /// The extra pass runs inside the running call (CC-1), so a caller that
    /// awaits `drain()`, such as the background task, covers it before it
    /// completes:
    ///
    ///   drain() ── wait for predecessor ── pass ── requested again? ── pass ── done
    ///                                        ▲ drain() / enqueue mid-pass sets the flag
    public func drain() async {
        // No endpoint means no sheet to check rows against: a pass now would
        // park every saved row for review (PLAT-NEW-1). A retired engine has
        // handed the store to its successor.
        guard api.endpointIdentity != nil, !isRetired else { return }
        guard !isDraining else {
            drainRequested = true
            return
        }
        isDraining = true
        eventBroadcaster.setActivity(true)
        defer {
            isDraining = false
            eventBroadcaster.setActivity(false)
            let waiters = quiesceWaiters
            quiesceWaiters = []
            waiters.forEach { $0.resume() }
        }
        // The engine this one replaced finishes first, so two engines never
        // send the same row (CC-2).
        if let predecessor {
            self.predecessor = nil
            await predecessor.quiesce()
        }
        repeat {
            drainRequested = false
            await drainPass()
        } while drainRequested && !Task.isCancelled && !isRetired
    }

    /// Stops this engine draining: a later `drain()` returns at once, and a
    /// running drain stops after its current row. Returns once it has stopped.
    public func quiesce() async {
        isRetired = true
        guard isDraining else { return }
        await withCheckedContinuation { quiesceWaiters.append($0) }
    }

    /// One pass over the outbox: guest operations first, then submissions
    /// oldest first.
    private func drainPass() async {
        let ids: [UUID]
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
            // keep their dispatch state so restart checks the receipt first. This
            // engine is the store's only drain owner, so an in-flight legacy row
            // is never another engine's live request.
            ids = rows.compactMap { row -> UUID? in
                if row.status == .inFlight && row.runIdentity == nil { row.status = .queued }
                return row.id
            }
            try modelContext.save()
        } catch {
            // A cache error cannot safely identify one row. The next foreground or
            // explicit refresh gets another chance to open and drain the store.
            eventBroadcaster.yield(.serviceFailed(message: UserFacingError.sync(error)))
            return
        }

        for id in ids {
            // An expired background task or a Settings swap stops between rows;
            // the rest stay queued for the next drain (CC-8).
            guard !Task.isCancelled, !isRetired else { return }
            do {
                guard let row = try pending(id: id) else { continue }
                guard row.endpointIdentity == api.endpointIdentity, row.endpointIdentity != nil else {
                    try parkForReview(row, message: "Review this saved submission before sending it to the current sheet.")
                    continue
                }
                if row.runIdentity != nil { await drainSharedAttendance(id: id) }
                else if try currentSharedState()?.supportsSharedGuests == true {
                    try parkForReview(row, message: "Choose the original season and run before recovering this submission.")
                } else { await drain(id: id) }
            } catch {
                // One row that cannot be read or parked must not strand the
                // rows after it (CA-15).
                eventBroadcaster.yield(.serviceFailed(message: UserFacingError.sync(error)))
            }
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
        // Read the clock before the guard. An await between the guard and the
        // save lets a second call pass the same guard and queue a duplicate.
        let now = await clock.now()
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

        if conflicted.runIdentity != nil {
            // A parked shared row has no snapshot. The cached live state stands
            // in; `resolveSharedConflict` verifies the run identity against it.
            let state = try conflicted.conflictState ?? requireSharedState()
            return try resolveSharedConflict(conflicted, action: action, state: state, createdAt: now)
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
            createdAt: now,
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
