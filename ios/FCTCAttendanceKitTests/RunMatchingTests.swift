//
//  RunMatchingTests.swift
//  FCTCAttendanceKitTests
//
//  CA-32: the Outbox diff and the engine pick the same server run.
//

import Foundation
import SwiftData
import Testing

@testable import FCTCAttendanceKit

@Suite("Run matching")
@MainActor
struct RunMatchingTests {
    private static let wanted = RunIdentity(spreadsheetId: "book", seasonSheetId: 7, runId: "run-b")
    private static let other = RunIdentity(spreadsheetId: "book", seasonSheetId: 7, runId: "run-a")

    /// Two runs on one date with one name; only the identity tells them apart.
    /// The decoy comes first, so a date-and-name match would pick it.
    private static let twins = SheetState(runs: [
        RunRecord(rowIndex: 10, date: "Sat, 3-Oct", meet: "Il Lido", run: "Long Run",
                  attendees: ["Aaron"], plusOnes: 0, identity: other),
        RunRecord(rowIndex: 11, date: "Sat, 3-Oct", meet: "Il Lido", run: "Long Run",
                  attendees: ["Col", "Toby"], plusOnes: 2, identity: wanted),
    ])

    private func snapshot(identity: RunIdentity?, rowIndex: Int = 99) -> PendingSubmissionSnapshot {
        PendingSubmissionSnapshot(
            id: UUID(), rowIndex: rowIndex, expectedDate: "Sat, 3-Oct", expectedRun: "Long Run",
            attendees: ["Col"], plusOnes: 0, actualKm: nil, mode: .merge, status: .conflict,
            createdAt: Date(timeIntervalSince1970: 0), conflictState: Self.twins, runIdentity: identity
        )
    }

    @Test("A shared row matches its run by identity, not by date and name")
    func identityDisambiguates() {
        let submission = snapshot(identity: Self.wanted)
        #expect(Self.twins.run(matching: submission)?.rowIndex == 11)

        // The Outbox diff reads the same run: Toby is on the server, not local.
        let diff = OutboxViewModel(engine: ViewModelSyncClient()).conflictDiff(for: submission)
        #expect(diff.attendance == AttendanceDiff(added: 0, removed: 1))
        #expect(diff.serverPlusOnes == 2)
    }

    @Test("A shared row whose run is gone matches nothing, as the engine refuses it")
    func missingIdentityMatchesNothing() {
        let gone = RunIdentity(spreadsheetId: "book", seasonSheetId: 7, runId: "run-z")
        #expect(Self.twins.run(matching: snapshot(identity: gone)) == nil)
    }

    @Test("A legacy row falls back to date and name, then the row index")
    func legacyFallback() throws {
        // The store row the engine passes, inserted so SwiftData backs it.
        let container = try ModelContainer(
            for: AttendanceSchema.schema,
            configurations: ModelConfiguration(schema: AttendanceSchema.schema, isStoredInMemoryOnly: true)
        )
        let row = PendingSubmission(rowIndex: 11, expectedDate: "Sat, 3-Oct", expectedRun: "Long Run", attendees: ["Col"])
        container.mainContext.insert(row)
        #expect(Self.twins.run(matching: row)?.rowIndex == 10)

        row.expectedRun = "Renamed"
        #expect(Self.twins.run(matching: row)?.rowIndex == 11)
        #expect(Self.twins.run(matching: snapshot(identity: nil, rowIndex: 11))?.rowIndex == 11)
    }
}
