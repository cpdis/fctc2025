//
//  RunLabelTests.swift
//  FCTCAttendanceKitTests
//
//  U12 — `RunLabel` against the same cases as `src/utils/runLabels.test.js`.
//

import Foundation
import Testing

@testable import FCTCAttendanceKit

@Suite("Run labels")
struct RunLabelTests {

    @Test("Race labels split into a distance type and an event", arguments: [
        ("Half - Xmas", "Half Marathon", "Xmas"),
        ("Half- Invasion Day", "Half Marathon", "Invasion Day"),
        ("Half - Anzac Day", "Half Marathon", "Anzac Day"),
        ("Half- Beer Run", "Half Marathon", "Beer Run"),
        ("Mara- Anzac Day", "Marathon", "Anzac Day"),
        ("Mara - Xmas", "Marathon", "Xmas"),
        ("10k - Xmas", "10K", "Xmas"),
        ("10k- Invasion Day", "10K", "Invasion Day"),
        ("10K -Xmas", "10K", "Xmas"),
        ("  HALF  -  Xmas  ", "Half Marathon", "Xmas"),
    ])
    func races(raw: String, type: String, event: String) {
        let label = RunLabel(raw)
        #expect(label.type == type)
        #expect(label.event == event)
    }

    @Test("The clean label keeps the sheet's own spelling")
    func cleanLabel() {
        #expect(RunLabel("Half- Invasion Day").label == "Half- Invasion Day")
    }

    @Test("Named runs map through the alias table or pass through", arguments: [
        ("N/hood Loop", "N'hood Loop", nil),
        ("FILAMENT CUP 🏆", "Filament Cup", nil),
        ("Filament Cup 🏆", "Filament Cup", nil),
        ("Good Fri Pancake", "Pancake Run", "Good Friday"),
        ("Intervals", "Intervals", nil),
        ("Pub Run", "Pub Run", nil),
        ("Kings Park", "Kings Park", nil),
        (" Soft Sand ", "Soft Sand", nil),
    ] as [(String, String, String?)])
    func namedRuns(raw: String, type: String, event: String?) {
        let label = RunLabel(raw)
        #expect(label.type == type)
        #expect(label.event == event)
    }

    @Test("A label that only starts with a race word is not a race")
    func notARace() {
        let label = RunLabel("Halfway Hills")
        #expect(label.label == "Halfway Hills")
        #expect(label.type == "Halfway Hills")
        #expect(label.event == nil)
    }

    @Test("A blank label is the Other type", arguments: ["", "   ", "**", nil] as [String?])
    func blank(raw: String?) {
        let label = RunLabel(raw)
        #expect(label.label == "")
        #expect(label.type == "Other")
        #expect(label.event == nil)
    }

    @Test("Footnote markers never make a separate type (R3)")
    func footnotes() {
        let cruise = RunLabel("**Cruise")
        #expect(cruise.label == "Cruise")
        #expect(cruise.type == "Cruise")
        #expect(cruise.event == nil)
        #expect(RunLabel("Cruise").type == cruise.type)
        #expect(RunLabel("Cruise**").type == "Cruise")

        let xmas = RunLabel("**Half - Xmas")
        #expect(xmas.label == "Half - Xmas")
        #expect(xmas.type == "Half Marathon")
        #expect(xmas.event == "Xmas")
    }

    @Test("Some-day and Someday are one location; others pass through trimmed")
    func locations() {
        #expect(RunLabel.location("Some-day") == "Someday")
        #expect(RunLabel.location("Someday") == "Someday")
        #expect(RunLabel.location(" Drift ") == "Drift")
        #expect(RunLabel.location("Alex 👑's") == "Alex 👑's")
        #expect(RunLabel.location("TBC") == "TBC")
        #expect(RunLabel.location(nil) == "")
        #expect(RunLabel.location("  ") == "")
    }
}
