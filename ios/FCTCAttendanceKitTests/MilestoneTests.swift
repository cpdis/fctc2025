//
//  MilestoneTests.swift
//  FCTCAttendanceKitTests
//

import Foundation
import Testing

@testable import FCTCAttendanceKit

/// A deterministic generator (SplitMix64), so a "random" draw repeats exactly for a
/// given seed.
///
/// It must produce a DIFFERENT value on each call. `Int.random(in:using:)` rejects
/// values that would bias the result and draws again, so a generator returning one
/// constant spins forever whenever that constant lands in the rejected region.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@Suite("Milestone board")
struct MilestoneBoardTests {

    @Test("The next landmark is the following multiple of 50")
    func nextMilestone() {
        #expect(MilestoneBoard.nextMilestone(after: 0) == 50)
        #expect(MilestoneBoard.nextMilestone(after: 1) == 50)
        #expect(MilestoneBoard.nextMilestone(after: 49) == 50)
        #expect(MilestoneBoard.nextMilestone(after: 147) == 150)
        // Sitting exactly on a landmark means the next one is 50 away, never 0.
        #expect(MilestoneBoard.nextMilestone(after: 50) == 100)
        #expect(MilestoneBoard.nextMilestone(after: 150) == 200)
    }

    @Test("Today's real sheet yields Alex, Celeste and Claire")
    func realShape() {
        // Lifetime totals measured from both season CSVs on 2026-08-16.
        let shortlist = MilestoneBoard.shortlist(from: [
            ("Alex 👑", 147), ("Celeste", 45), ("Claire", 45), ("Col", 140),
            ("Alex B", 36), ("Rhys", 36), ("Adam", 134), ("Liam", 31),
        ])

        #expect(shortlist.map(\.name) == ["Alex 👑", "Celeste", "Claire"])
        #expect(shortlist[0].runsNeeded == 3)
        #expect(shortlist[0].milestone == 150)
        #expect(shortlist[1].runsNeeded == 5)
        #expect(shortlist[1].milestone == 50)
        // Col is inside the ceiling at exactly 10 but loses the third place to a
        // pair who are closer.
        #expect(!shortlist.contains { $0.name == "Col" })
    }

    @Test("The ceiling admits exactly ten runs and no more")
    func ceilingBoundary() {
        let shortlist = MilestoneBoard.shortlist(from: [
            ("OnTheLine", 40), ("JustOver", 39),
        ])

        #expect(shortlist.map(\.name) == ["OnTheLine"])
        #expect(shortlist[0].runsNeeded == 10)
    }

    @Test("A tie at the last place extends the list rather than cutting someone")
    func tieAtLastPlaceExtends() {
        let shortlist = MilestoneBoard.shortlist(from: [
            ("A", 49), ("B", 47), ("C", 47), ("D", 47), ("E", 44),
        ])

        // B, C and D all need 3. Showing two of the three would be arbitrary.
        #expect(shortlist.map(\.name) == ["A", "B", "C", "D"])
        #expect(shortlist.filter { $0.runsNeeded == 3 }.count == 3)
        #expect(!shortlist.contains { $0.name == "E" })
    }

    @Test("A tie spanning the first three places returns exactly those three")
    func tieWithinPlaces() {
        let shortlist = MilestoneBoard.shortlist(from: [
            ("A", 47), ("B", 47), ("C", 47), ("D", 44),
        ])

        #expect(shortlist.map(\.name) == ["A", "B", "C"])
    }

    @Test("Nobody who has never run appears")
    func zeroRunMembersExcluded() {
        let shortlist = MilestoneBoard.shortlist(from: [
            ("Newcomer", 0), ("Runner", 45),
        ])

        #expect(shortlist.map(\.name) == ["Runner"])
    }

    @Test("Nobody within the ceiling means an empty list")
    func emptyWhenNobodyIsClose() {
        #expect(MilestoneBoard.shortlist(from: [("Far", 20), ("Further", 5)]).isEmpty)
        #expect(MilestoneBoard.shortlist(from: []).isEmpty)
    }

    @Test("Equal distances order by name, so the list does not reshuffle")
    func stableOrdering() {
        let input: [(name: String, runs: Int)] = [("Zoe", 45), ("Adam", 45), ("Mia", 45)]

        #expect(MilestoneBoard.shortlist(from: input).map(\.name) == ["Adam", "Mia", "Zoe"])
        #expect(
            MilestoneBoard.shortlist(from: input.reversed()).map(\.name)
                == MilestoneBoard.shortlist(from: input).map(\.name)
        )
    }

    @Test("Fewer than three eligible people returns just them")
    func fewerThanThree() {
        let shortlist = MilestoneBoard.shortlist(from: [("Only", 48), ("Far", 10)])

        #expect(shortlist.map(\.name) == ["Only"])
        #expect(shortlist[0].runsNeeded == 2)
    }
}

@Suite("Milestone phrases")
struct MilestonePhraseTests {

    @Test("There are ten lines and none is empty")
    func phraseInventory() {
        #expect(MilestonePhrases.all.count == 10)
        #expect(MilestonePhrases.all.allSatisfy { !$0.isEmpty })
        #expect(Set(MilestonePhrases.all).count == 10, "no duplicates")
    }

    @Test("A seeded draw is deterministic")
    func deterministicDraw() {
        var generator = SeededGenerator(seed: 99)
        var second = SeededGenerator(seed: 99)

        #expect(
            MilestonePhrases.nextIndex(avoiding: nil, using: &generator)
                == MilestonePhrases.nextIndex(avoiding: nil, using: &second)
        )
    }

    @Test("The previous line never comes back immediately")
    func neverRepeatsImmediately() {
        // Sweep every previous index against a spread of generator states; the
        // excluded line must never be drawn.
        for previous in MilestonePhrases.all.indices {
            for seed in UInt64(0)..<64 {
                var generator = SeededGenerator(seed: seed)
                let drawn = MilestonePhrases.nextIndex(avoiding: previous, using: &generator)
                #expect(drawn != previous)
                #expect(MilestonePhrases.all.indices.contains(drawn))
            }
        }
    }

    @Test("Every line is reachable from a given previous")
    func drawCoversTheRest() {
        var seen: Set<Int> = []
        for seed in UInt64(0)..<512 {
            var generator = SeededGenerator(seed: seed)
            seen.insert(MilestonePhrases.nextIndex(avoiding: 4, using: &generator))
        }

        #expect(seen == Set(MilestonePhrases.all.indices).subtracting([4]))
    }

    @Test("A first run with no stored index can draw anything")
    func firstRunAllowsAny() {
        var seen: Set<Int> = []
        for seed in UInt64(0)..<512 {
            var generator = SeededGenerator(seed: seed)
            seen.insert(MilestonePhrases.nextIndex(avoiding: nil, using: &generator))
        }

        #expect(seen == Set(MilestonePhrases.all.indices))
    }

    @Test("An out-of-range stored index is tolerated, not trapped")
    func toleratesStaleIndex() {
        var generator = SeededGenerator(seed: 7)

        let drawn = MilestonePhrases.nextIndex(avoiding: 99, using: &generator)
        #expect(MilestonePhrases.all.indices.contains(drawn))
        #expect(MilestonePhrases.phrase(at: 99) == MilestonePhrases.all[0])
        #expect(MilestonePhrases.phrase(at: -1) == MilestonePhrases.all[0])
    }
}
