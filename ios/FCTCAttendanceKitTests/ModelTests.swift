//
//  ModelTests.swift
//  FCTCAttendanceKitTests
//
//  U1: trivial coverage that the model layer compiles and its pure helpers behave.
//  Real behaviour tests arrive with U3/U4.
//

import Foundation
import Testing

@testable import FCTCAttendanceKit

@Suite("Models")
struct ModelTests {

    @Test("Draft check/uncheck round-trips and never downgrades a manual check")
    func draftChecking() {
        var draft = AttendanceDraft(
            rowIndex: 42,
            expectedDate: "Fri, 2-Jan",
            expectedRun: "Soft Sand"
        )

        draft.check("Col")
        #expect(draft.isChecked("Col"))
        #expect(draft.checks["Col"] == .manual)

        // An OCR proposal must not overwrite a manual check.
        draft.check("Col", provenance: .ocr)
        #expect(draft.checks["Col"] == .manual)

        draft.check("Aaron", provenance: .ocr)
        #expect(draft.checks["Aaron"] == .ocr)

        draft.toggle("Aaron")
        #expect(!draft.isChecked("Aaron"))
    }

    @Test("plusOnes is derived from guest names; attendees come out in sheet order")
    func draftDerivedValues() {
        var draft = AttendanceDraft(
            rowIndex: 42,
            expectedDate: "Fri, 2-Jan",
            expectedRun: "Soft Sand"
        )
        draft.check("Toby")
        draft.check("Aaron")
        draft.guests = [Guest(name: "Priya"), Guest(name: "Sam's mate")]

        #expect(draft.attendees == ["Aaron", "Toby"])
        #expect(draft.plusOnes == 2)

        draft.plusOnesOverride = 4
        #expect(draft.plusOnes == 4)
    }

    @Test("A confirmed draft becomes an outbox row, guest names staying local")
    func submissionFromDraft() {
        var draft = AttendanceDraft(
            rowIndex: 42,
            expectedDate: "Fri, 2-Jan",
            expectedRun: "Soft Sand",
            actualKm: 7.1,
            baseRevision: "rev-1"
        )
        draft.check("Col")
        draft.guests = [Guest(name: "Priya")]

        let pending = PendingSubmission.from(draft: draft, mode: .merge)

        #expect(pending.rowIndex == 42)
        #expect(pending.attendees == ["Col"])
        #expect(pending.guestNames == ["Priya"])
        #expect(pending.plusOnes == 1)
        #expect(pending.actualKm == 7.1)
        #expect(pending.mode == .merge)
        #expect(pending.status == .queued)
        #expect(pending.state == .queued)
        #expect(pending.isOutstanding)
        #expect(pending.baseRevision == "rev-1")
    }

    @Test("A cached run knows whether the sheet row already has marks")
    func runHasRecordedAttendance() {
        let blank = Run(rowIndex: 11, date: "Fri, 2-Jan", meet: "Il Lido", run: "Soft Sand")
        #expect(!blank.hasRecordedAttendance)

        let filled = Run(
            rowIndex: 11,
            date: "Fri, 2-Jan",
            meet: "Il Lido",
            run: "Soft Sand",
            attendees: ["Adam"],
            plusOnes: 0
        )
        #expect(filled.hasRecordedAttendance)
        #expect(filled.displayLabel == "Fri, 2-Jan · Soft Sand")
    }

    @Test("Member ordering matches the sheet's alphabetical member band")
    func memberOrdering() {
        let names = ["Dan B", "Aaron", "Col", "Alex Kr"]
        #expect(names.sorted(by: Member.sheetOrder) == ["Aaron", "Alex Kr", "Col", "Dan B"])
    }

    @Test("A member tracks whether its optimistic insert reached the sheet")
    func memberIsNew() {
        let member = Member(name: "Bilbo", colIndex: 8, isNew: true)
        #expect(member.isNew)
    }

    @Test("Every persistent model is registered in the schema")
    func schemaRegistration() {
        #expect(AttendanceSchema.models.count == 3)
    }
}
