//
//  AttendanceDraft.swift
//  FCTCAttendanceKit
//
//  The one thing the Review & Confirm screen renders (plan decision #4). Checklist,
//  screenshot OCR and voice are all just PRE-FILL STRATEGIES over this value: they
//  propose checks, the human disposes, and only a confirmed draft becomes a
//  `PendingSubmission`.
//
//  Deliberately a value type: pure, diffable, trivially testable, and never a
//  half-written row in the sheet. Persistence of in-flight drafts, if it turns out to
//  be wanted, is U4's call.
//

import Foundation

/// Where a proposed check came from — surfaced as the trailing provenance badge on
/// the checklist row.
public enum CheckProvenance: String, Codable, Sendable, CaseIterable {
    /// Tapped by the human (or already recorded in the sheet).
    case manual
    /// Proposed by the screenshot/OCR pipeline (U6).
    case ocr
    /// Proposed by the voice pipeline (U7).
    case voice
}

/// A non-member who ran with the club. The sheet's `+1's` column only ever receives
/// the COUNT (no sheet-structure change); the names live on-device so a regular guest
/// can later be promoted via `addMember` (resolved Q2).
public struct Guest: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String

    public init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

/// A name the extractors produced that the roster could not resolve — offered on the
/// review screen as "map to an existing member" or "add as new" (R4).
public struct UnmatchedName: Codable, Hashable, Sendable {
    public var raw: String
    public var provenance: CheckProvenance
    /// Roster candidates in the "did you mean…" confidence band, best first.
    public var suggestions: [String]

    public init(raw: String, provenance: CheckProvenance, suggestions: [String] = []) {
        self.raw = raw
        self.provenance = provenance
        self.suggestions = suggestions
    }
}

public struct AttendanceDraft: Codable, Hashable, Sendable {

    /// Sheet row being filled.
    public var rowIndex: Int
    /// Row-identity guards echoed back to `submitAttendance`.
    public var expectedDate: String
    public var expectedRun: String

    /// Checked members, keyed by canonical sheet name, with how each check arrived.
    public var checks: [String: CheckProvenance]

    /// Guests by name; `plusOnes` (what the sheet gets) is derived from this.
    public var guests: [Guest]

    /// `Actual kms`. Nil means "leave the sheet cell as it is".
    public var actualKm: Double?

    /// A manual guest-count edit wins over the count derived from guest names.
    public var plusOnesOverride: Int?

    /// Names the extractors could not resolve to the roster.
    public var unmatched: [UnmatchedName]

    /// Sheet revision this draft was built against (optimistic concurrency).
    public var baseRevision: String?

    public init(
        rowIndex: Int,
        expectedDate: String,
        expectedRun: String,
        checks: [String: CheckProvenance] = [:],
        guests: [Guest] = [],
        actualKm: Double? = nil,
        plusOnesOverride: Int? = nil,
        unmatched: [UnmatchedName] = [],
        baseRevision: String? = nil
    ) {
        self.rowIndex = rowIndex
        self.expectedDate = expectedDate
        self.expectedRun = expectedRun
        self.checks = checks
        self.guests = guests
        self.actualKm = actualKm
        self.plusOnesOverride = plusOnesOverride
        self.unmatched = unmatched
        self.baseRevision = baseRevision
    }
}

extension AttendanceDraft {

    /// Local-only guest names, without the UI identity wrapper.
    public var guestNames: [String] {
        get { guests.map(\.name) }
        set { guests = newValue.map { Guest(name: $0) } }
    }

    /// What the sheet's `+1's` cell receives.
    public var plusOnes: Int { plusOnesOverride ?? guests.count }

    /// Checked members in sheet order — exactly the set that becomes `x` cells.
    public var attendees: [String] {
        checks.keys.sorted(by: Member.sheetOrder)
    }

    public func isChecked(_ name: String) -> Bool {
        checks[name] != nil
    }

    /// Check a member, recording where the check came from. An existing manual check
    /// is never downgraded to a proposal.
    public mutating func check(_ name: String, provenance: CheckProvenance = .manual) {
        if checks[name] == .manual && provenance != .manual { return }
        checks[name] = provenance
    }

    public mutating func uncheck(_ name: String) {
        checks[name] = nil
    }

    public mutating func toggle(_ name: String) {
        if isChecked(name) { uncheck(name) } else { check(name) }
    }
}
