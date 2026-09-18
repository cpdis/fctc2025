import Foundation
import SwiftData

extension SyncEngine {
    // MARK: Cache reconciliation

    func reconcile(_ state: SheetState, seenAt: Date) throws {
        if state.supportsSharedGuests { try reconcileSharedState(state, seenAt: seenAt) }
        try reconcileRoster(state.roster, totals: state.lifetimeTotals, birthdays: state.birthdays,
                            seasonYear: state.seasonYear, seenAt: seenAt)
        try reconcileRuns(
            state.runs,
            revision: state.sheetRevision,
            seasonYear: state.seasonYear,
            spreadsheetId: state.spreadsheetId,
            seasonSheetId: state.seasonSheetId
        )
    }

    func reconcileRoster(
        _ roster: [RosterEntry],
        totals: [MemberTotal],
        birthdays: [MemberBirthday]? = nil,
        seasonYear: Int? = nil,
        seenAt: Date
    ) throws {
        let local = try modelContext.fetch(FetchDescriptor<Member>())
        let remoteKeys = Set(roster.map { canonicalName($0.name) })
        var localByKey: [String: Member] = [:]
        for member in local {
            let key = canonicalName(member.name)
            if localByKey[key] == nil { localByKey[key] = member }
        }

        // Totals are keyed the same way names are matched everywhere else, so a
        // rename between seasons still lands on the right member.
        var runsByKey: [String: Int] = [:]
        for total in totals { runsByKey[canonicalName(total.name)] = total.runs }
        var birthdaysByKey: [String: MemberBirthday] = [:]
        for birthday in birthdays ?? [] where birthday.isValid {
            birthdaysByKey[canonicalName(birthday.name)] = birthday
        }

        for entry in roster {
            let key = canonicalName(entry.name)
            let member: Member
            if let existing = localByKey[key] {
                member = existing
                member.name = entry.name
                member.colIndex = entry.colIndex
                member.isNew = false
                member.lastSeenAt = seenAt
                // A script without the field reports no totals at all. Keep the
                // cached number rather than blanking it.
                if let runs = runsByKey[key] { member.lifetimeRuns = runs }
            } else {
                member = Member(
                    name: entry.name,
                    colIndex: entry.colIndex,
                    lastSeenAt: seenAt,
                    lifetimeRuns: runsByKey[key] ?? 0
                )
                modelContext.insert(member)
            }
            // Older scripts preserve dates from this endpoint, but never borrow
            // dates from another workbook's endpoint after Settings changes.
            if birthdays != nil || member.birthdayEndpointIdentity != api.endpointIdentity {
                let birthday = birthdaysByKey[key]
                member.birthdayMonth = birthday?.month
                member.birthdayDay = birthday?.day
                // A scope also records that an empty list was confirmed. An
                // older endpoint has not confirmed any birthday data yet.
                member.birthdayEndpointIdentity = birthdays == nil ? nil : api.endpointIdentity
                member.birthdaySeasonYear = birthdays == nil ? nil : seasonYear
            }
        }
        for member in local where !member.isNew && !remoteKeys.contains(canonicalName(member.name)) {
            modelContext.delete(member)
        }
    }

    func reconcileRuns(
        _ records: [RunRecord],
        revision: String,
        seasonYear: Int,
        spreadsheetId: String? = nil,
        seasonSheetId: Int? = nil
    ) throws {
        let allLocal = try modelContext.fetch(FetchDescriptor<ScheduledRun>())
        let identities = Set(records.compactMap { $0.identity?.cacheKey })
        // Explicit state scope matters even when a season now has no run rows.
        let book = spreadsheetId ?? records.first?.spreadsheetId
        let season = seasonSheetId ?? records.first?.seasonSheetId
        let local = allLocal.filter {
            if let book, let season { return $0.spreadsheetId == book && $0.seasonSheetId == season }
            return $0.identity == nil
        }
        let remoteRows = Set(records.map(\.rowIndex))
        for record in records {
            let existing = local.first { record.identity != nil ? $0.identity == record.identity : $0.rowIndex == record.rowIndex }
            let run = existing ?? ScheduledRun(rowIndex: record.rowIndex, date: record.date, meet: record.meet, run: record.run)
            apply(record, revision: revision, seasonYear: seasonYear, to: run)
            if existing == nil { modelContext.insert(run) }
        }
        for run in local where run.identity != nil ? !identities.contains(run.cacheKey) : !remoteRows.contains(run.rowIndex) {
            modelContext.delete(run)
        }
    }

    func apply(_ record: RunRecord, revision: String, seasonYear: Int, to run: ScheduledRun) {
        run.rowIndex = record.rowIndex; run.date = record.date
        run.scheduledAt = parseDate(record.date, seasonYear: seasonYear)
        run.meet = record.meet; run.run = record.run
        run.approxKm = record.approxKm; run.actualKm = record.actualKm
        run.attendees = record.attendees; run.plusOnes = record.plusOnes; run.cachedRevision = revision
        run.spreadsheetId = record.spreadsheetId; run.seasonSheetId = record.seasonSheetId
        run.runId = record.runId; run.namedGuestIds = record.namedGuestIds
        run.unnamedGuests = record.unnamedGuests; run.seasonYear = seasonYear
        run.endpointIdentity = api.endpointIdentity
    }

    func optimisticInsertMember(name: String) throws -> Bool {
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

    func rollbackOptimisticMember(name: String) throws {
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

    func cachedSeasonYear(fallbackDate: Date) throws -> Int {
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

    func updateCachedRevision(_ revision: String) throws {
        for run in try modelContext.fetch(FetchDescriptor<ScheduledRun>()) {
            run.cachedRevision = revision
        }
    }

    func canonicalName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    func parseDate(_ value: String, seasonYear: Int) -> Date? {
        guard seasonYear > 0 else { return nil }
        return dateFormatter.date(from: "\(value)-\(seasonYear)")
    }
}
