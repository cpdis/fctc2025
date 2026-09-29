//
//  EffectiveRuns.swift
//  FCTCAttendanceKit
//
//  The season as the organiser recorded it (KTD11, R26). Recorded attendance
//  waits in the outbox (`PendingSubmission`) until the sheet confirms it, so
//  streaks, totals and cards read the cached runs with the outbox applied:
//
//    cached runs (one season) ──┐
//    outbox rows ───────────────┼─> EffectiveRuns ─> runs, clubRuns
//    season's last refresh ─────┘                    unsyncedCount
//
//  Rows apply oldest first, the order the engine drains them. Each row replays
//  its own endpoint's write path, so the overlay equals the cache after sync:
//
//    legacy (row index)  `SyncEngine.finish()`: merge unions the attendees and
//                        keeps the larger +1s; overwrite replaces both.
//    shared (run id)     Apps Script `guestAttendancePlan_`: merge unions the
//                        attendees and named guest ids and keeps the larger
//                        unnamed count; overwrite replaces all three.
//                        +1s = named + unnamed.
//    both                A nil +1s or distance leaves the cached value.
//
//  Which rows apply:
//
//    queued, in flight            yes, the engine still sends them
//    conflict                     no, it waits for the organiser (this
//                                 includes rows parked for review)
//    done, legacy                 no, `finish()` already wrote the cache
//    done, shared, committed      yes, until a refresh that started after its
//                                 confirmation lands. The shared drain leaves
//                                 the cache to its follow-up refresh, so a
//                                 failed refresh must not drop the run, and
//                                 neither may a slow one that started before
//                                 the write and landed after it. A merge or
//                                 overwrite replayed on a run that already
//                                 shows it changes nothing, so nothing counts
//                                 twice meanwhile.
//    done, discarded/superseded   no, closed without a write
//

import Foundation

public struct EffectiveRuns: Hashable, Sendable {

    /// The season's cached runs, in the given order, with the outbox applied.
    public let runs: [RunSnapshot]

    /// Queued and in-flight submissions the overlay applied: the cards'
    /// "Includes N unsynced". A confirmed row that waits for its refresh is
    /// synced, so it is not counted.
    public let unsyncedCount: Int

    /// Apply the outbox to one season's cached runs.
    ///
    /// - Parameters:
    ///   - cached: one season's cached runs, as `RunCacheScope` selects them.
    ///   - submissions: outbox rows in any order. Rows for another run, season
    ///     or endpoint match nothing and are not counted.
    ///   - endpoint: the current endpoint. The engine sends a row only to the
    ///     endpoint it was saved for.
    ///   - refreshedAt: when the request behind this season's cached state
    ///     started (`SharedSheetCache.refreshedAt`). Nil for a legacy endpoint.
    public init(
        cached: [RunSnapshot],
        submissions: [PendingSubmissionSnapshot],
        endpoint: String?,
        refreshedAt: Date?
    ) {
        var runs = cached
        var unsynced = 0
        let overlay = submissions
            .filter { Self.applies($0, endpoint: endpoint, refreshedAt: refreshedAt) }
            // The engine drains by creation time; the id only breaks exact ties.
            .sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
        for submission in overlay {
            guard let index = runs.firstIndex(where: { Self.writes(submission, to: $0) }) else { continue }
            if submission.runIdentity == nil {
                Self.replayFinish(submission, on: &runs[index])
            } else {
                Self.replayGuestPlan(submission, on: &runs[index])
            }
            if submission.isOutstanding { unsynced += 1 }
        }
        self.runs = runs
        self.unsyncedCount = unsynced
    }

    /// The same runs as the club-day rules and the Dashboard read them. Rows
    /// with no usable date are dropped.
    public var clubRuns: [ClubRun] {
        runs.compactMap { ClubRun($0) }
    }

    // MARK: Rules

    /// Whether a row changes the sheet and the cache does not show it yet.
    static func applies(
        _ submission: PendingSubmissionSnapshot,
        endpoint: String?,
        refreshedAt: Date?
    ) -> Bool {
        guard let endpoint, submission.endpointIdentity == endpoint else { return false }
        // `attendanceOperation` cannot send a shared row without its guest
        // allocation, so such a row never reaches the sheet.
        if submission.runIdentity != nil,
           submission.namedGuestIds == nil || (submission.unnamedGuests ?? -1) < 0 {
            return false
        }
        switch submission.status {
        case .queued, .inFlight:
            return true
        case .conflict:
            return false
        case .done:
            // `lastAttemptAt` holds a committed shared row's confirmation time.
            guard submission.runIdentity != nil, submission.outcome == .committed,
                  let confirmedAt = submission.lastAttemptAt else { return false }
            guard let refreshedAt else { return true }
            // Only a request started after the confirmation read the write.
            return refreshedAt <= confirmedAt
        }
    }

    /// The run a row writes, matched as its sync path matches it: the stable
    /// run id on a shared endpoint; on a legacy one, the row index plus the
    /// date and run the row was queued against (`SheetState.satisfies`). A row
    /// inserted above a queued run shifts the indexes, and the index alone
    /// would then credit the queued attendance to whichever run moved there.
    static func writes(_ submission: PendingSubmissionSnapshot, to run: RunSnapshot) -> Bool {
        if let identity = submission.runIdentity { return run.runIdentity == identity }
        return run.runIdentity == nil && run.rowIndex == submission.rowIndex
            && run.date == submission.expectedDate && run.run == submission.expectedRun
    }

    /// `SyncEngine.finish()`, on a snapshot.
    static func replayFinish(_ submission: PendingSubmissionSnapshot, on run: inout RunSnapshot) {
        switch submission.mode {
        case .merge:
            run.attendees = Array(Set(run.attendees).union(submission.attendees)).sorted(by: Member.sheetOrder)
            if let plusOnes = submission.plusOnes { run.plusOnes = max(run.plusOnes, plusOnes) }
        case .overwrite:
            run.attendees = submission.attendees.sorted(by: Member.sheetOrder)
            if let plusOnes = submission.plusOnes { run.plusOnes = plusOnes }
        }
        if let actualKm = submission.actualKm { run.actualKm = actualKm }
        // A legacy run has no guest allocation: its snapshot counts every +1
        // as unnamed, as a fresh snapshot of the written run would.
        run.unnamedGuests = run.plusOnes
    }

    /// Apps Script `guestAttendancePlan_`, on a snapshot. The attendees and
    /// distance follow `SheetOps.buildRowWrite`; the +1s follow the guest
    /// allocation (`GuestOps.mergeAllocation` and `validateAllocation`).
    static func replayGuestPlan(_ submission: PendingSubmissionSnapshot, on run: inout RunSnapshot) {
        // `applies` admits only rows that carry an allocation.
        let named = submission.namedGuestIds ?? []
        let unnamed = submission.unnamedGuests ?? 0
        switch submission.mode {
        case .merge:
            run.attendees = Array(Set(run.attendees).union(submission.attendees)).sorted(by: Member.sheetOrder)
            run.namedGuestIds = Array(Set(run.namedGuestIds).union(named)).sorted(by: codeUnitPrecedes)
            run.unnamedGuests = max(run.unnamedGuests, unnamed)
        case .overwrite:
            run.attendees = submission.attendees.sorted(by: Member.sheetOrder)
            run.namedGuestIds = Array(Set(named)).sorted(by: codeUnitPrecedes)
            run.unnamedGuests = unnamed
        }
        run.plusOnes = run.namedGuestIds.count + run.unnamedGuests
        if let actualKm = submission.actualKm { run.actualKm = actualKm }
    }
}
