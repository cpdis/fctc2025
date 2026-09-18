import Foundation

/// A stale offline guest selection becomes member attendance only after this
/// explicit before/after review. A label match never creates the mapping.
public struct PromotedGuestReview: Sendable {
    public var draft: AttendanceDraft
    public var convertedNames: [String]
    public var membersBefore: [String]
    public var guestNamesBefore: [String]
    public var guestNamesAfter: [String]
    public var unnamedBefore: Int
    public var peopleBefore: Int
    public var actualKmBefore: Double?
    public var removedMembers: [String]
    public var removedGuests: [String]

    public init(submission: PendingSubmissionSnapshot, state: SheetState, endpointIdentity: String?) throws {
        guard let identity = submission.runIdentity, identity.spreadsheetId == state.spreadsheetId,
              let run = state.runs.first(where: { $0.identity == identity }),
              let named = submission.namedGuestIds, let unnamed = submission.unnamedGuests else {
            throw SheetAPIError.badPayload(message: "Refresh and select the original season and run before reviewing this attendance.")
        }
        let currentIDs = Set(run.namedGuestIds ?? [])
        let queuedIDs = Set(named)
        let selectedIDs = submission.mode == .merge ? currentIDs.union(queuedIDs) : queuedIDs
        let members = submission.mode == .merge ? Set(run.attendees).union(submission.attendees) : Set(submission.attendees)
        var checks = Dictionary(uniqueKeysWithValues: members.map { ($0, CheckProvenance.manual) })
        var selected: [Guest] = []
        convertedNames = []
        membersBefore = run.attendees.sorted(by: Member.sheetOrder)
        unnamedBefore = run.unnamedGuests ?? max(0, run.plusOnes - currentIDs.count)
        peopleBefore = Set(run.attendees).count + run.plusOnes
        actualKmBefore = run.actualKm
        guestNamesBefore = try currentIDs.sorted().map { id in
            guard let guest = state.guests?.first(where: { $0.guestId == id }) else {
                throw SheetAPIError.badPayload(message: "A saved guest identity is missing. Review the sheet before continuing.")
            }
            return guest.displayName
        }
        // Preserve additive intent against the refreshed row before replacing
        // promoted IDs. The replacement is bound to this exact sheet revision.
        for id in selectedIDs.sorted() {
            guard let guest = state.guests?.first(where: { $0.guestId == id }) else {
                throw SheetAPIError.badPayload(message: "A saved guest identity is missing. Review the sheet before continuing.")
            }
            if !guest.isActive, let member = guest.memberName, state.roster.contains(where: { $0.name == member }) {
                checks[member] = .manual; convertedNames.append(member)
            } else if guest.isActive, let value = guest.draftGuest { selected.append(value) }
            else { throw SheetAPIError.badPayload(message: "This guest has no verified member mapping.") }
        }
        guard !convertedNames.isEmpty else { throw SheetAPIError.badPayload(message: "No promoted guest needs conversion. Review this conflict again.") }
        guestNamesAfter = selected.map(\.name)
        removedMembers = Set(run.attendees).subtracting(checks.keys).sorted(by: Member.sheetOrder)
        let remainingIDs = Set(selected.map { $0.id.uuidString.lowercased() })
        removedGuests = currentIDs.subtracting(remainingIDs).sorted().compactMap { id in state.guests?.first { $0.guestId == id }?.displayName }
        draft = AttendanceDraft(rowIndex: run.rowIndex, expectedDate: run.date, expectedRun: run.run,
            checks: checks, guests: selected, actualKm: submission.actualKm ?? run.actualKm,
            baseRevision: state.sheetRevision, runIdentity: identity, endpointIdentity: endpointIdentity,
            unnamedGuests: submission.mode == .merge ? max(unnamedBefore, unnamed) : unnamed)
    }
}
