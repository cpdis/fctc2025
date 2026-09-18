import FCTCAttendanceKit
import Foundation

/// Synthetic shared server used only by explicit UI-test launches.
actor UITestSharedGuestAPI: SheetAPIClient {
    nonisolated let endpointIdentity: String? = "https://ui-test.invalid/exec"
    static let rene = "11111111-1111-4111-8111-111111111111"
    static let toby = "22222222-2222-4222-8222-222222222222"
    static let wes = "33333333-3333-4333-8333-333333333333"
    private var seasons: [Int: SheetState]
    private var guests: [SharedGuest]
    private var receipts: [UUID: GuestOperationReceipt] = [:]
    private var histories: [String: [GuestAttendanceEntry]] = [:]
    private var revision = 1

    init() {
        guests = [SharedGuest(guestId: Self.rene, displayName: "Rene", confirmedRuns: 11),
                  SharedGuest(guestId: Self.toby, displayName: "Toby", confirmedRuns: 10),
                  SharedGuest(guestId: Self.wes, displayName: "Wes", confirmedRuns: 9)]
        let roster = ["Aaron", "Col", "Dan", "Dan B"].enumerated().map { RosterEntry(name: $0.element, colIndex: $0.offset + 6) }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "EEE, d-MMM"
        let today = Calendar.current.startOfDay(for: .now)
        let currentYear = Calendar.current.component(.year, from: today)
        var currentRuns = [RunRecord(rowIndex: 42, date: formatter.string(from: today), meet: "Il Lido", run: "Soft Sand", approxKm: 7.1, actualKm: 7.1,
            attendees: ["Col"], plusOnes: 2, identity: RunIdentity(spreadsheetId: "ui-book", seasonSheetId: 26, runId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"),
            namedGuestIds: [Self.rene], unnamedGuests: 1, seasonYear: currentYear),
            RunRecord(rowIndex: 43, date: formatter.string(from: today.addingTimeInterval(-86400)), meet: "Tompkins Park", run: "River Loop", approxKm: 8.2,
                identity: RunIdentity(spreadsheetId: "ui-book", seasonSheetId: 26, runId: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"), namedGuestIds: [], unnamedGuests: 0, seasonYear: currentYear)]
        let oldRuns = (0..<3).map { index in
            RunRecord(rowIndex: 20 + index, date: "Fri, \(5 + index * 7)-Dec", meet: "Beach", run: "Summer run", approxKm: 7.2, actualKm: 7.2,
                attendees: ["Col"], plusOnes: 3, identity: RunIdentity(spreadsheetId: "ui-book", seasonSheetId: 25,
                    runId: String(format: "cccccccc-cccc-4ccc-8ccc-%012d", index)), namedGuestIds: [Self.rene, Self.toby, Self.wes], unnamedGuests: 0, seasonYear: currentYear - 1)
        }
        for index in 0..<7 {
            currentRuns.append(RunRecord(rowIndex: 20 + index, date: "Fri, \(1 + index * 3)-Aug", meet: "Beach", run: "Coastal run", approxKm: 7.2, actualKm: 7.2,
                attendees: ["Col"], plusOnes: 3, identity: RunIdentity(spreadsheetId: "ui-book", seasonSheetId: 26,
                    runId: String(format: "dddddddd-dddd-4ddd-8ddd-%012d", index)), namedGuestIds: index < 6 ? [Self.rene, Self.toby, Self.wes] : [Self.rene, Self.toby], unnamedGuests: index < 6 ? 0 : 1, seasonYear: currentYear))
        }
        seasons = [25: SheetState(roster: roster, runs: oldRuns, seasonYear: currentYear - 1, sheetRevision: "ui-1", apiVersion: 2,
                        capabilities: GuestCapabilities(), spreadsheetId: "ui-book", seasonSheetId: 25),
                   26: SheetState(roster: roster, runs: currentRuns, seasonYear: currentYear, sheetRevision: "ui-1", apiVersion: 2,
                        capabilities: GuestCapabilities(), spreadsheetId: "ui-book", seasonSheetId: 26)]
        if ProcessInfo.processInfo.arguments.contains("-ui-birthdays") {
            let calendar = BirthdayBoard.calendar
            seasons[26]!.birthdays = [("Aaron", 0), ("Col", 7), ("Dan", 31)].map { name, days in
                let date = calendar.date(byAdding: .day, value: days, to: .now)!
                return MemberBirthday(name: name, month: calendar.component(.month, from: date), day: calendar.component(.day, from: date))
            }
            seasons[26]!.lifetimeTotals = [MemberTotal(name: "Aaron", runs: 147), MemberTotal(name: "Col", runs: 45), MemberTotal(name: "Dan", runs: 45)]
        }
        if ProcessInfo.processInfo.arguments.contains("-ui-no-birthdays") { seasons[26]!.birthdays = [] }
        for guest in guests {
            histories[guest.guestId] = (oldRuns + currentRuns).filter { $0.namedGuestIds?.contains(guest.guestId) == true }.map { run in
                GuestAttendanceEntry(guestId: guest.guestId, spreadsheetId: "ui-book", seasonSheetId: run.seasonSheetId!, runId: run.runId!,
                    state: "active", classification: "guest", revision: 1, seasonYear: run.seasonYear!, date: run.date, run: run.run, rowIndex: run.rowIndex)
            }
        }
        guests[0].lastAttendance = GuestLastAttendance(spreadsheetId: "ui-book", seasonSheetId: 26, runId: currentRuns[0].runId!, date: currentRuns[0].date, seasonYear: currentYear)
        if ProcessInfo.processInfo.arguments.contains("-ui-promoted-conflict") {
            guests[0].status = "promoted"; guests[0].memberName = "Rene"
            for season in Array(seasons.keys) {
                seasons[season]!.roster.append(RosterEntry(name: "Rene", colIndex: 10))
                for row in seasons[season]!.runs.indices where seasons[season]!.runs[row].namedGuestIds?.contains(Self.rene) == true {
                    seasons[season]!.runs[row].namedGuestIds?.removeAll { $0 == Self.rene }
                    seasons[season]!.runs[row].plusOnes -= 1
                    seasons[season]!.runs[row].attendees.append("Rene")
                }
            }
            // Another organiser saved these choices after the queued draft.
            seasons[26]!.runs[0].attendees.append("Dan")
            seasons[26]!.runs[0].namedGuestIds?.append(Self.toby)
            seasons[26]!.runs[0].plusOnes += 1
            seasons[26]!.runs[0].actualKm = 8.1
        }
    }
    func getState() async throws -> SheetState { try await getState(seasonSheetId: nil) }
    func getState(seasonSheetId: Int?) async throws -> SheetState {
        if ProcessInfo.processInfo.arguments.contains("-ui-state-offline") { throw URLError(.notConnectedToInternet) }
        return state(seasonSheetId ?? 26)
    }
    private func state(_ season: Int) -> SheetState {
        var value = seasons[season]!
        value.guests = guests
        value.supportedSeasons = seasons.values.map { SupportedSeason(seasonSheetId: $0.seasonSheetId!, seasonYear: $0.seasonYear) }
        value.sheetRevision = "ui-\(revision)"
        return value
    }
    func sharedRead(action: String, fields: [String: GuestJSON]) async throws -> GuestJSON {
        let guestID = fields["guestId"]?.string ?? ""
        guard let guest = guests.first(where: { $0.guestId == guestID }) else { throw SheetAPIError.badPayload(message: "Choose a guest.") }
        switch action {
        case "getGuestHistory": return try .value(GuestHistory(guest: guest, guestRevision: "ui-\(revision)", attendance: histories[guestID] ?? []))
        case "previewPromotion":
            if ProcessInfo.processInfo.arguments.contains("-ui-promotion-fails") { throw SheetAPIError.server(code: "allocation_missing", message: "Correct the guest allocation before promotion.") }
            let entries = histories[guestID] ?? []
            let changes = entries.compactMap { entry -> PromotionPreview.Change? in
                guard let run = seasons[entry.seasonSheetId]?.runs.first(where: { $0.runId == entry.runId }) else { return nil }
                return PromotionPreview.Change(spreadsheetId: "ui-book", seasonSheetId: entry.seasonSheetId, runId: entry.runId,
                    rowIndex: run.rowIndex, date: run.date, run: run.run, plusOnesBefore: run.plusOnes, plusOnesAfter: run.plusOnes - 1,
                    totalBefore: run.attendees.count + run.plusOnes, totalAfter: run.attendees.count + run.plusOnes,
                    actualKmBefore: run.actualKm, actualKmAfter: run.actualKm)
            }
            return try .value(PromotionPreview(guestId: guestID, memberName: fields["memberName"]?.string ?? guest.displayName,
                confirmedRuns: guest.confirmedRuns ?? entries.count, previewToken: "ui-preview-\(revision)",
                targetMode: PromotionTargetMode(rawValue: fields["targetMode"]?.string ?? "create") ?? .create,
                seasons: seasons.values.map { s in PromotionPreview.Season(seasonYear: s.seasonYear, seasonSheetId: s.seasonSheetId!, runs: entries.filter { $0.seasonSheetId == s.seasonSheetId }.count) }, changes: changes))
        case "previewGuestImport":
            let entries: [GuestImportEntry] = try fields["entries"]!.decoded()
            let changes = try entries.map { entry in
                guard let run = seasons[entry.seasonSheetId]?.runs.first(where: { $0.runId == entry.runId }) else { throw SheetAPIError.badPayload(message: "Select the original run.") }
                let already = run.namedGuestIds?.contains(guestID) == true
                guard already || (run.unnamedGuests ?? 0) > 0 else { throw SheetAPIError.badPayload(message: "This run has no unnamed guest to assign.") }
                return GuestImportPreview.Change(spreadsheetId: entry.spreadsheetId, seasonSheetId: entry.seasonSheetId, runId: entry.runId,
                    expectedDate: entry.expectedDate, expectedRun: entry.expectedRun, assignment: entry.assignment, alreadyAssigned: already,
                    unnamedBefore: run.unnamedGuests ?? 0, unnamedAfter: (run.unnamedGuests ?? 0) - (already ? 0 : 1))
            }
            return try .value(GuestImportPreview(guestId: guestID, baseGuestRevision: guest.revision, baseRevision: "ui-review", entries: entries, changes: changes, confirmedRuns: guest.confirmedRuns ?? 0))
        default: throw SheetAPIError.notImplemented
        }
    }
    func perform(_ operation: SharedGuestOperation) async throws -> GuestJSON {
        if let receipt = receipts[operation.id], let response = receipt.response { return response }
        // Authentication refusal proves this rename was not applied; reads stay available.
        if operation.action == "renameGuest", ProcessInfo.processInfo.arguments.contains("-ui-rename-auth-failure") {
            throw SheetAPIError.badSecret(message: "The setup code was rejected.")
        }
        if ProcessInfo.processInfo.arguments.contains("-ui-shared-offline") { throw SheetAPIError.network("Offline") }
        let request = operation.request
        var response: [String: GuestJSON] = ["ok": .bool(true)]
        switch operation.action {
        case "createGuest":
            let name = request["displayName"]?.string ?? ""
            let matches = guests.filter { GuestNames.canonical($0.displayName) == GuestNames.canonical(name) }
            if !matches.isEmpty && request["confirmDistinct"] != .bool(true) {
                throw SharedGuestConflict(reason: "identity_ambiguous", message: "Choose the saved person or confirm a different person.", guestIds: matches.map(\.guestId))
            }
            let guest = SharedGuest(guestId: request["guestId"]!.string!, displayName: name)
            guests.append(guest); response["guest"] = try .value(guest)
        case "renameGuest":
            let index = guests.firstIndex { $0.guestId == request["guestId"]?.string }!
            let base: Int = try request["baseGuestRevision"]!.decoded()
            guard base == guests[index].revision else {
                throw SharedGuestConflict(reason: "guest_changed", message: "The saved guest name changed. Review your correction.")
            }
            guests[index].displayName = request["displayName"]!.string!; guests[index].revision += 1
            response["guest"] = try .value(guests[index])
        case "submitAttendance":
            let season: Int = try request["seasonSheetId"]!.decoded()
            let index = seasons[season]!.runs.firstIndex { $0.runId == request["runId"]?.string }!
            let ids: [String] = try request["namedGuestIds"]!.decoded()
            let unnamed: Int = try request["unnamedGuests"]!.decoded()
            let attendees: [String] = try request["attendees"]!.decoded()
            var run = seasons[season]!.runs[index]
            let oldIDs = Set(run.namedGuestIds ?? [])
            let isMerge = request["mode"]?.string == "merge"
            run.namedGuestIds = isMerge ? Array(oldIDs.union(ids)) : ids
            run.unnamedGuests = isMerge ? max(run.unnamedGuests ?? 0, unnamed) : unnamed
            run.plusOnes = run.namedGuestIds!.count + run.unnamedGuests!
            run.attendees = isMerge ? Array(Set(run.attendees).union(attendees)) : attendees
            run.actualKm = try? request["actualKm"]?.decoded(Double.self)
            seasons[season]!.runs[index] = run
            for id in Set(run.namedGuestIds ?? []).subtracting(oldIDs) {
                if let guestIndex = guests.firstIndex(where: { $0.guestId == id }) { guests[guestIndex].confirmedRuns = (guests[guestIndex].confirmedRuns ?? 0) + 1 }
                histories[id, default: []].append(GuestAttendanceEntry(guestId: id, spreadsheetId: "ui-book", seasonSheetId: season, runId: run.runId!, state: "active", classification: "guest", revision: 1, seasonYear: run.seasonYear!, date: run.date, run: run.run, rowIndex: run.rowIndex))
            }
        case "commitPromotion":
            let id = request["guestId"]!.string!, name = request["memberName"]!.string!
            let index = guests.firstIndex { $0.guestId == id }!
            guests[index].status = "promoted"; guests[index].memberName = name
            for season in Array(seasons.keys) {
                seasons[season]!.roster.append(RosterEntry(name: name, colIndex: seasons[season]!.roster.count + 6))
                for row in seasons[season]!.runs.indices where seasons[season]!.runs[row].namedGuestIds?.contains(id) == true {
                    seasons[season]!.runs[row].namedGuestIds?.removeAll { $0 == id }
                    seasons[season]!.runs[row].plusOnes -= 1; seasons[season]!.runs[row].attendees.append(name)
                }
            }
        case "importGuestHistory":
            let id = request["guestId"]!.string!
            let entries: [GuestImportEntry] = try request["entries"]!.decoded()
            for entry in Set(entries) {
                let index = seasons[entry.seasonSheetId]!.runs.firstIndex { $0.runId == entry.runId }!
                if seasons[entry.seasonSheetId]!.runs[index].namedGuestIds?.contains(id) == true { continue }
                seasons[entry.seasonSheetId]!.runs[index].namedGuestIds?.append(id)
                seasons[entry.seasonSheetId]!.runs[index].unnamedGuests! -= 1
                if let guestIndex = guests.firstIndex(where: { $0.guestId == id }) { guests[guestIndex].confirmedRuns = (guests[guestIndex].confirmedRuns ?? 0) + 1 }
            }
        default: throw SheetAPIError.notImplemented
        }
        revision += 1; response["sheetRevision"] = .string("ui-\(revision)")
        let result = GuestJSON.object(response)
        receipts[operation.id] = GuestOperationReceipt(operationId: operation.id.uuidString.lowercased(), requestDigest: operation.digest, status: "completed", response: result)
        return result
    }
    func operationStatus(id: UUID) async throws -> GuestOperationReceipt? { receipts[id] }
    func submitAttendance(_ submission: AttendanceSubmission) async throws -> SubmissionOutcome { throw SheetAPIError.notImplemented }
    func addMember(name: String) async throws -> AddMemberResult { throw SheetAPIError.notImplemented }
    func addRun(_ request: AddRunRequest) async throws -> AddRunResult { throw SheetAPIError.notImplemented }
}
