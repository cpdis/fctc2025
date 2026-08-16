//
//  FixtureParityTests.swift
//  FCTCAttendanceKitTests
//
//  U5 — table-driven over every file in `fixtures/attendance/`. The expectations are
//  U1's and are treated as frozen (`_conventions.md`: never edit another unit's
//  expected file to make your code pass). If one of these fails, the code is wrong.
//
//  Each fixture is checked twice over:
//   • PARSE — the scanner's structural output (options, counts, candidate names,
//     distance, guests) against the expected JSON.
//   • MATCH — those raw strings through `NameMatcher` against `names`, `ambiguous`
//     and `unmatchedRaw`, i.e. what the Review screen would actually pre-check.
//

import Foundation
import Testing

@testable import FCTCAttendanceKit

@Suite("Fixture parity — poll screenshots")
struct PollFixtureParityTests {

    @Test("Every OCR fixture parses exactly as expected", arguments: Fixtures.ocrFixtures)
    func parses(stem: String) throws {
        let expected = try Fixtures.expected(stem)
        let lines = try Fixtures.lines("\(stem).ocr.txt")
        let result = PollLineScanner().scan(lines: lines)

        #expect(expected.kind == "poll-ocr")
        #expect(result.isVoteDetailScreen == expected.isVoteDetailScreen)
        #expect(result.candidateNames == expected.candidateNames)

        let expectedOptions = try #require(expected.options)
        #expect(result.options.count == expectedOptions.count)
        for (parsed, wanted) in zip(result.options, expectedOptions) {
            #expect(parsed.label == wanted.label)
            #expect(parsed.voteCount == wanted.voteCount)
            #expect(parsed.isAffirmative == wanted.isAffirmative)
            #expect(parsed.rawNames == wanted.rawNames)
        }
    }

    @Test("Every OCR fixture resolves to the expected proposals", arguments: Fixtures.ocrFixtures)
    func matches(stem: String) throws {
        let expected = try Fixtures.expected(stem)
        let lines = try Fixtures.lines("\(stem).ocr.txt")
        let result = PollLineScanner().scan(lines: lines)
        let outcome = Roster.matcher.outcome(for: result.affirmativeNames)

        #expect(Set(outcome.matched) == Set(expected.names))
        #expect(outcome.ambiguousRaws == expected.ambiguous.map(\.raw))
        #expect(outcome.ambiguousCandidates == expected.ambiguous.map(\.candidates))
        #expect(Set(outcome.notMatched) == Set(expected.unmatchedRaw))
    }

    @Test("A poll card is detected and warned about, never proposed from", arguments: Fixtures.ocrFixtures)
    func cardDetection(stem: String) throws {
        let expected = try Fixtures.expected(stem)
        let lines = try Fixtures.lines("\(stem).ocr.txt")
        let result = HeuristicExtractor().extract(lines: lines)

        let needsVotesView = expected.needsVotesView ?? false
        #expect(result.warnings.contains(.namelessPollCard) == needsVotesView)
        if needsVotesView {
            #expect(result.entities.names.isEmpty)
            #expect(result.poll?.isVoteDetailScreen == false)
        }
    }
}

@Suite("Fixture parity — voice transcripts")
struct VoiceFixtureParityTests {

    @Test("Every transcript fixture parses exactly as expected", arguments: Fixtures.voiceFixtures)
    func parses(stem: String) throws {
        let expected = try Fixtures.expected(stem)
        let transcript = try Fixtures.text("\(stem).transcript.txt")
        let entities = VoiceTranscriptScanner().scan(transcript: transcript)

        #expect(expected.kind == "voice-transcript")
        #expect(entities.plusOnes == expected.plusOnes)
        #expect(entities.guestNames == (expected.guestNames ?? []))
        if let wanted = expected.distanceKm {
            let parsed = try #require(entities.distanceKm)
            #expect(abs(parsed - wanted) < 0.0001)
        } else {
            #expect(entities.distanceKm == nil)
        }
    }

    @Test("Every transcript fixture resolves to the expected proposals", arguments: Fixtures.voiceFixtures)
    func matches(stem: String) throws {
        let expected = try Fixtures.expected(stem)
        let transcript = try Fixtures.text("\(stem).transcript.txt")
        let entities = VoiceTranscriptScanner().scan(transcript: transcript)
        let outcome = Roster.matcher.outcome(for: entities.names)

        #expect(Set(outcome.matched) == Set(expected.names))
        #expect(outcome.ambiguousRaws == expected.ambiguous.map(\.raw))
        #expect(outcome.ambiguousCandidates == expected.ambiguous.map(\.candidates))
        #expect(Set(outcome.notMatched) == Set(expected.unmatchedRaw))
    }

    @Test("Guests never leak into the roster proposal set", arguments: Fixtures.voiceFixtures)
    func guestsAreNotRosterNames(stem: String) throws {
        let expected = try Fixtures.expected(stem)
        let transcript = try Fixtures.text("\(stem).transcript.txt")
        let entities = VoiceTranscriptScanner().scan(transcript: transcript)

        for guest in expected.guestNames ?? [] {
            #expect(!entities.names.contains(guest))
        }
    }
}

@Suite("Fixture hygiene")
struct FixtureHygieneTests {

    @Test("The fixture bundle is wired up")
    func bundleResolves() throws {
        for stem in Fixtures.ocrFixtures {
            let lines = try Fixtures.lines("\(stem).ocr.txt")
            #expect(!lines.isEmpty)
        }
        for stem in Fixtures.voiceFixtures {
            let transcript = try Fixtures.text("\(stem).transcript.txt")
            #expect(!transcript.isEmpty)
        }
    }

    @Test("Every expected name is a real 2026 roster key", arguments: Fixtures.ocrFixtures + Fixtures.voiceFixtures)
    func expectationsUseRealRosterNames(stem: String) throws {
        let expected = try Fixtures.expected(stem)
        let roster = Set(Roster.season2026)
        for name in expected.names {
            #expect(roster.contains(name), "\(stem): \(name) is not a 2026 roster key")
        }
        for entry in expected.ambiguous {
            for candidate in entry.candidates {
                #expect(roster.contains(candidate), "\(stem): \(candidate) is not a 2026 roster key")
            }
        }
    }

    @Test("The test roster matches the one U1's suite pinned")
    func rosterAgreesWithU1() {
        #expect(Roster.season2026 == IntelligenceTests.roster2026)
    }
}
