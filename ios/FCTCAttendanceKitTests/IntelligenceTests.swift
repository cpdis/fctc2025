//
//  IntelligenceTests.swift
//  FCTCAttendanceKitTests
//
//  U1: the intelligence seams compile and their safe defaults hold. These assertions
//  are written to stay true after U5/U6/U7 replace the stubs — they check the
//  SAFE-DEFAULT contract (nothing is ever auto-checked without evidence), not the
//  stub bodies.
//

import Foundation
import Testing

@testable import FCTCAttendanceKit

@Suite("Intelligence")
struct IntelligenceTests {

    /// The real 2026 header names, including the near-collisions U5 must never
    /// auto-resolve.
    static let roster2026 = [
        "Aaron", "Adam", "Alex 👑", "Alex B", "Alex Kr", "Anna", "Cam", "Celeste",
        "Chartt", "Claire", "Col", "Dan", "Dan B", "Darren", "Deano", "Fraser",
        "Grant", "Jack", "Joe", "Kate B", "Laura E", "Laura K", "Liam", "Ming",
        "Rhys", "Rohan", "Sam", "Scott", "Shane", "Tarquin", "Tim", "Toby", "Wes",
    ]

    @Test("Confidence tiers are ordered and within (0, 1]")
    func confidenceTiers() {
        #expect(NameMatcher.suggestThreshold < NameMatcher.autoCheckThreshold)
        #expect(NameMatcher.suggestThreshold > 0)
        #expect(NameMatcher.autoCheckThreshold <= 1)
    }

    @Test("An empty roster can never produce a match")
    func emptyRosterNeverMatches() {
        let matcher = NameMatcher(roster: [])
        if case .unmatched = matcher.match("Aaron") {
            // expected
        } else {
            Issue.record("empty roster must not resolve any name")
        }
    }

    @Test("Batch matching preserves input order and arity")
    func batchMatching() {
        let matcher = NameMatcher(roster: Self.roster2026)
        let raws = ["Aaron", "Scot t", "Priya"]
        let results = matcher.match(all: raws)
        let echoed = results.map { $0.raw }
        #expect(echoed == raws)
    }

    @Test("Empty extraction is empty")
    func emptyEntities() {
        #expect(ExtractedEntities.empty.isEmpty)
        #expect(!ExtractedEntities(names: ["Col"]).isEmpty)
        #expect(ExtractedEntities(plusOnes: 2).plusOnes == 2)
    }

    @Test("The placeholder extractor is available and finds nothing")
    func placeholderExtractor() async throws {
        let extractor = UnimplementedNameExtractor()
        #expect(await extractor.isAvailable)
        let entities = try await extractor.extract(from: "Aaron and Col came")
        #expect(entities.isEmpty)
    }

    @Test("A poll parse with no lines proposes nothing and is not a votes screen")
    func pollParserSafeDefault() {
        let result = PollScreenshotParser().parse(lines: [])
        #expect(!result.isVoteDetailScreen)
        #expect(result.candidateNames.isEmpty)
        #expect(result.affirmativeNames.isEmpty)
    }

    @Test("Multi-screenshot parsing dedupes candidates")
    func pollParserUnionDedupes() {
        let result = PollScreenshotParser().parse(screenshots: [[], []])
        #expect(result.candidateNames.count == Set(result.candidateNames).count)
    }

    @Test("Only affirmative options seed pre-checks")
    func affirmativeNamesFilter() {
        let result = PollParseResult(
            isVoteDetailScreen: true,
            options: [
                PollOption(label: "Yes", voteCount: 2, rawNames: ["Aaron", "Col"]),
                PollOption(label: "No", voteCount: 1, rawNames: ["Anna"], isAffirmative: false),
            ],
            candidateNames: ["Aaron", "Col", "Anna"]
        )
        #expect(result.affirmativeNames == ["Aaron", "Col"])
    }

    @Test("An empty transcript yields no entities")
    func voiceParserSafeDefault() async throws {
        #expect(VoiceEntryParser().parse(transcript: "").isEmpty)

        let extractor = VoiceEntryExtractor()
        #expect(await extractor.isAvailable)
        let entities = try await extractor.extract(from: "")
        #expect(entities.isEmpty)
    }
}
