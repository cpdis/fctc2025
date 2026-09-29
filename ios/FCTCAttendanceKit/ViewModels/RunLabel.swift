//
//  RunLabel.swift
//  FCTCAttendanceKit
//
//  Run label rules, the Swift mirror of `src/utils/runLabels.js` (KTD1, R3, R7).
//
//  Organisers type the sheet's "Run" and "Meet" cells by hand, so one kind of run
//  shows up under several spellings across seasons. This is the one place the app
//  turns those spellings into a normalized type, event and location:
//
//    raw "Run" cell         type            event
//    ---------------------  --------------  ------------
//    "Half- Invasion Day"   Half Marathon   Invasion Day   (2025 spacing)
//    "Half - Xmas"          Half Marathon   Xmas           (2026 spacing)
//    "Mara - Anzac Day"     Marathon        Anzac Day
//    "10k - Xmas"           10K             Xmas
//    "**Cruise"             Cruise          -              (sheet footnote)
//    "N/hood Loop"          N'hood Loop     -
//    "FILAMENT CUP 🏆"      Filament Cup    -
//    "Good Fri Pancake"     Pancake Run     Good Friday
//    "Pub Run", "Intervals" (as typed)      -              (pass through)
//
//  The tables must stay identical to the JS ones. The golden parity fixtures
//  (`fixtures/attendance/parity/*.json`, `ParityFixtureTests`) fail when they drift.
//

import Foundation

/// A parsed "Run" cell: its clean label, normalized type and holiday or race event.
public struct RunLabel: Hashable, Sendable {

    /// The cell without footnote markers or outer whitespace, as typed otherwise.
    public let label: String

    /// The normalized run type every card, filter and colour keys off (R7).
    public let type: String

    /// The holiday or race name ("Xmas", "Invasion Day"). Non-nil marks a special.
    public let event: String?

    /// Race distance prefix (lowercased) to its normalized type.
    private static let raceTypes = ["mara": "Marathon", "half": "Half Marathon", "10k": "10K"]

    /// Whole labels that need a new name. Keys are lowercased so a change of case
    /// in the sheet ("Filament Cup 🏆") still lands on the same type.
    private static let aliases: [String: (type: String, event: String?)] = [
        "n/hood loop": ("N'hood Loop", nil),
        "filament cup 🏆": ("Filament Cup", nil),
        "good fri pancake": ("Pancake Run", "Good Friday"),
    ]

    /// Meet spellings that name the same place. Exact match, like the JS table.
    private static let locationAliases = ["Some-day": "Someday"]

    /// Type for a run row whose "Run" cell is blank.
    public static let unlabelledType = "Other"

    /// Parse a raw "Run" cell. Nil and blank cells give the `Other` type.
    public init(_ raw: String?) {
        let label = Self.stripFootnoteMarkers(raw)
        self.label = label

        // "Mara", "Half" or "10k", an optional-space hyphen, then the event name.
        // Built per call: `Regex` is not Sendable, so it cannot be a static.
        if let race = label.wholeMatch(of: /(mara|half|10k)\s*-\s*(.+)/.ignoresCase()),
           let type = Self.raceTypes[race.1.lowercased()] {
            self.type = type
            self.event = race.2.trimmingCharacters(in: .whitespacesAndNewlines)
            return
        }

        if let alias = Self.aliases[label.lowercased()] {
            self.type = alias.type
            self.event = alias.event
            return
        }

        self.type = label.isEmpty ? Self.unlabelledType : label
        self.event = nil
    }

    /// Normalize a raw "Meet" cell into a location. Known aliases map to one
    /// spelling; anything else passes through trimmed.
    public static func location(_ raw: String?) -> String {
        let location = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return locationAliases[location] ?? location
    }

    /// Drop sheet footnote markers ("**Cruise" on 5 Jan 2026) and outer whitespace.
    /// The marker flags a note on the sheet; it is never part of the run's name.
    private static func stripFootnoteMarkers(_ raw: String?) -> String {
        (raw ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "*"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
