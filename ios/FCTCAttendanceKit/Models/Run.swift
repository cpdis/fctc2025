//
//  Run.swift
//  FCTCAttendanceKit
//
//  One scheduled run row from the season sheet.
//
//  Two runs can share a date (e.g. the 26-Jan "Half - Invasion Day" and
//  "10k - Invasion Day" rows), so a run is identified by `date + run` — and by
//  `rowIndex` once resolved. `date` is kept as the sheet's own display string
//  ("Fri, 2-Jan") because that string is what `submitAttendance` echoes back as
//  `expectedDate` for row-identity verification.
//

import Foundation
import SwiftData

@Model
public final class Run {

    /// 1-based row index in the season sheet.
    @Attribute(.unique) public var rowIndex: Int

    /// Sheet display string, verbatim (e.g. `"Fri, 2-Jan"`).
    public var date: String

    /// Parsed calendar date, for sorting and the "most recent run at or before now"
    /// default-selection rule (R7). Nil when the sheet string cannot be parsed.
    public var scheduledAt: Date?

    /// `Meet` column (e.g. `"Il Lido"`).
    public var meet: String

    /// `Run` column (e.g. `"Soft Sand"`).
    public var run: String

    /// `Approx kms` — pre-fills the `Actual kms` field on the review screen.
    public var approxKm: Double?

    /// `Actual kms` as currently recorded in the sheet.
    public var actualKm: Double?

    /// Member names with an `x` in this row, as of the last `getState`.
    public var attendees: [String]

    /// `+1's` count as currently recorded in the sheet.
    public var plusOnes: Int

    /// Sheet revision this row was cached from; a submission carries it as
    /// `baseRevision` for optimistic concurrency.
    public var cachedRevision: String?

    public init(
        rowIndex: Int,
        date: String,
        scheduledAt: Date? = nil,
        meet: String,
        run: String,
        approxKm: Double? = nil,
        actualKm: Double? = nil,
        attendees: [String] = [],
        plusOnes: Int = 0,
        cachedRevision: String? = nil
    ) {
        self.rowIndex = rowIndex
        self.date = date
        self.scheduledAt = scheduledAt
        self.meet = meet
        self.run = run
        self.approxKm = approxKm
        self.actualKm = actualKm
        self.attendees = attendees
        self.plusOnes = plusOnes
        self.cachedRevision = cachedRevision
    }
}

extension Run {
    /// True when the sheet already has marks in this row — the trigger for the
    /// merge/overwrite dialog (R8).
    public var hasRecordedAttendance: Bool {
        !attendees.isEmpty || plusOnes > 0
    }

    /// Human label used in pickers and the review header: "Fri, 2-Jan · Soft Sand".
    public var displayLabel: String {
        "\(date) · \(run)"
    }
}
