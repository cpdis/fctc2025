//
//  AddRunDraft.swift
//  FCTCAttendanceKit
//
//  The Add Run form's state and rules, kept out of the view so a unit test can
//  reach `canAdd` and `request` without a simulator.
//

import Foundation

public struct AddRunDraft: Equatable, Sendable {
    public var date: Date
    public var meet = ""
    public var run = ""
    /// Bound as text, like the checklist's distance field (see `DistanceText`):
    /// a formatted value binding commits only when focus ends, and the decimal
    /// pad has no Return key, so Add used to read nil with the keyboard up.
    public var approxKmText = ""

    public init(date: Date = .now) {
        self.date = date
    }

    public var distanceIsMalformed: Bool { DistanceText.isMalformed(approxKmText) }

    /// Add needs a meeting place and a run name, and no half-typed distance.
    /// A blank distance is fine: the sheet row simply has no approx kms.
    public var canAdd: Bool {
        !cleanMeet.isEmpty && !cleanRun.isEmpty && !distanceIsMalformed
    }

    /// The new sheet row. The date is the sheet's own "Fri, 25-Sep" cell text,
    /// which `ClubDate(sheetDate:season:)` reads back.
    public var request: AddRunRequest {
        AddRunRequest(
            date: ClubDate.sheetString(from: date),
            meet: cleanMeet,
            run: cleanRun,
            approxKm: DistanceText.parse(approxKmText)
        )
    }

    private var cleanMeet: String { meet.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var cleanRun: String { run.trimmingCharacters(in: .whitespacesAndNewlines) }
}
