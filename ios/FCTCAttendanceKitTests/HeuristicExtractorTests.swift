//
//  HeuristicExtractorTests.swift
//  FCTCAttendanceKitTests
//
//  U5 — the deterministic extractor: the voice phrase matrix, the OCR chrome filter
//  and the nameless-poll-card detector. Everything here is fixture-free on purpose
//  (the fixtures are covered in `FixtureParityTests`); these are the edges around them.
//

import Foundation
import Testing

@testable import FCTCAttendanceKit

@Suite("HeuristicExtractor — voice: distance")
struct VoiceDistanceTests {

    static func distance(_ transcript: String) -> Double? {
        VoiceTranscriptScanner().scan(transcript: transcript).distanceKm
    }

    @Test("Distances in every phrasing the club actually uses", arguments: [
        ("we did 8.7k", 8.7),
        ("we did 8.7km", 8.7),
        ("we did 12 kays", 12.0),
        ("we did 12 km", 12.0),
        ("eight point seven k", 8.7),
        ("ten point four two kilometres", 10.42),
        ("seven point one", 7.1),
        ("twelve point five kilometres", 12.5),
        ("twenty one point three k", 21.3),
        ("ten k", 10.0),
        ("we did 5.5", 5.5),
    ])
    func parsesDistance(transcript: String, expected: Double) throws {
        let parsed = try #require(Self.distance(transcript))
        #expect(abs(parsed - expected) < 0.0001)
    }

    @Test("Numbers that are not distances stay out of the distance field", arguments: [
        "Col and Cam came",
        "plus two guests",
        "no guests",
        "Aaron came plus one",
        "",
    ])
    func ignoresNonDistances(transcript: String) {
        #expect(Self.distance(transcript) == nil)
    }

    @Test("A guest count is never mistaken for a distance")
    func guestsAreNotDistance() {
        let entities = VoiceTranscriptScanner()
            .scan(transcript: "Col came, plus two guests, we did eight point seven k")
        #expect(entities.plusOnes == 2)
        #expect(entities.distanceKm == 8.7)
    }
}

@Suite("HeuristicExtractor — voice: guests")
struct VoiceGuestTests {

    static func scan(_ transcript: String) -> ExtractedEntities {
        VoiceTranscriptScanner().scan(transcript: transcript)
    }

    @Test("Guest phrasings map to a count", arguments: [
        ("Col came, plus two guests", 2),
        ("Col came, plus one guest", 1),
        ("Col came plus one", 1),
        ("Col came, a plus one", 1),
        ("Col and Cam, two guests", 2),
        ("Col came, no guests", 0),
        ("Col came, zero guests", 0),
        ("Col came, plus three guests", 3),
    ])
    func guestCounts(transcript: String, expected: Int) {
        #expect(Self.scan(transcript).plusOnes == expected)
    }

    @Test("Unstated guests stay nil — nil and 0 are different facts")
    func unstatedGuests() {
        #expect(Self.scan("Col and Cam came, we did 8.7k").plusOnes == nil)
        #expect(Self.scan("Col came, no guests").plusOnes == 0)
    }

    @Test("Named guests are captured and never proposed as members")
    func namedGuests() {
        let entities = Self.scan("Grant came, plus one guest, Priya, and we did seven point one")
        #expect(entities.plusOnes == 1)
        #expect(entities.guestNames == ["Priya"])
        #expect(entities.names == ["Grant"])
        #expect(entities.distanceKm == 7.1)
    }

    @Test("Several named guests are captured up to the stated count")
    func severalNamedGuests() {
        let entities = Self.scan(
            "Toby turned up, plus three guests, Priya, Sam Smith and Zed, we did nine point five kilometres"
        )
        #expect(entities.plusOnes == 3)
        #expect(entities.guestNames == ["Priya", "Sam Smith", "Zed"])
        #expect(entities.names == ["Toby"])
        #expect(entities.distanceKm == 9.5)
    }
}

@Suite("HeuristicExtractor — voice: names")
struct VoiceNameTests {

    static func names(_ transcript: String) -> [String] {
        VoiceTranscriptScanner().scan(transcript: transcript).names
    }

    @Test("Stop phrases and filler never become names", arguments: [
        ("So today we had Col and Cam", ["Col", "Cam"]),
        ("Col came", ["Col"]),
        ("Col was there", ["Col"]),
        ("Col said they were there", ["Col"]),
        ("Col turned up at the last minute", ["Col"]),
        ("Col and Cam ran the soft sand this morning", ["Col", "Cam"]),
        ("we did the loop", []),
        ("", []),
    ])
    func stopPhrases(transcript: String, expected: [String]) {
        #expect(Self.names(transcript) == expected)
    }

    @Test("Qualified names survive as one name each")
    func qualifiedNames() {
        #expect(Self.names("Laura E and Kate B and Dan B came") == ["Laura E", "Kate B", "Dan B"])
    }

    @Test("Conjunction-heavy phrasing splits cleanly")
    func conjunctions() {
        let transcript = "Aaron, Adam and Anna came, and also Cam and Col turned up"
        #expect(Self.names(transcript) == ["Aaron", "Adam", "Anna", "Cam", "Col"])
    }

    @Test("Repeats are deduped, order is kept")
    func dedupe() {
        #expect(Self.names("Col came, Col came again") == ["Col"])
    }
}

@Suite("HeuristicExtractor — OCR chrome")
struct PollLineScannerTests {

    static let votesScreen = [
        "9:41",
        "Poll",
        "Filament Coffee Track Club",
        "Wednesday 6am — Filament, intervals?",
        "Select one or more",
        "Yes ✓ 3 votes",
        "Aaron",
        "Col",
        "Scot t",
        "No 1 vote",
        "Anna",
    ]

    @Test("Chrome above the first option header never becomes a name")
    func chromeAboveOptions() {
        let result = PollLineScanner().scan(lines: Self.votesScreen)
        #expect(result.isVoteDetailScreen)
        #expect(result.candidateNames == ["Aaron", "Col", "Scot t", "Anna"])
        #expect(result.affirmativeNames == ["Aaron", "Col", "Scot t"])
    }

    @Test("Option headers carry their label, count and polarity")
    func optionHeaders() {
        let result = PollLineScanner().scan(lines: Self.votesScreen)
        #expect(result.options.map(\.label) == ["Yes", "No"])
        #expect(result.options.compactMap(\.voteCount) == [3, 1])
        #expect(result.options.map(\.isAffirmative) == [true, false])
    }

    @Test("Day-name options count as coming, No and Maybe do not")
    func polarity() {
        #expect(PollLineScanner.isAffirmative("Friday"))
        #expect(PollLineScanner.isAffirmative("Yes"))
        #expect(!PollLineScanner.isAffirmative("No"))
        #expect(!PollLineScanner.isAffirmative("Maybe"))
    }

    @Test("Timestamps, percentages and counts are dropped", arguments: [
        "9:41", "19:42", "9:41 AM", "62%", "100%",
    ])
    func chromeLines(line: String) {
        let result = PollLineScanner().scan(lines: ["Yes ✓ 1 vote", "Aaron", line])
        #expect(result.candidateNames == ["Aaron"])
    }

    @Test("A bare count line fills the option it follows")
    func bareCounts() {
        let result = PollLineScanner().scan(lines: ["Yes", "13", "No", "4"])
        #expect(result.options.count == 2)
        #expect(result.options.compactMap(\.voteCount) == [13, 4])
    }

    @Test("An empty screenshot proposes nothing")
    func empty() {
        let result = PollLineScanner().scan(lines: [])
        #expect(!result.isVoteDetailScreen)
        #expect(result.options.isEmpty)
        #expect(result.candidateNames.isEmpty)
    }

    @Test("A poll CARD is detected instead of guessed at")
    func namelessCard() {
        let card = [
            "Filament Coffee Track Club",
            "Colin",
            "POLL",
            "Friday 6am — Il Lido, Soft Sand?",
            "Select one or more",
            "Yes", "13", "No", "4", "Maybe", "2",
            "View votes",
            "19:42",
        ]
        let result = PollLineScanner().scan(lines: card)
        #expect(!result.isVoteDetailScreen)
        #expect(result.candidateNames.isEmpty)
        #expect(result.options.map(\.label) == ["Yes", "No", "Maybe"])
        #expect(result.options.compactMap(\.voteCount) == [13, 4, 2])

        // "Colin" is the poll's author line, not a voter.
        #expect(!result.candidateNames.contains("Colin"))
    }

    @Test("Multi-screenshot union dedupes candidates")
    func union() {
        let first = ["Yes ✓ 2 votes", "Aaron", "Col"]
        let second = ["Yes ✓ 2 votes", "Col", "Cam"]
        let result = PollScreenshotParser().parse(screenshots: [first, second])
        #expect(result.candidateNames == ["Aaron", "Col", "Cam"])
        #expect(result.isVoteDetailScreen)
    }
}

@Suite("HeuristicExtractor — the seam")
struct HeuristicExtractorSeamTests {

    @Test("Heuristics are always available")
    func alwaysAvailable() async {
        let available = await HeuristicExtractor().isAvailable
        #expect(available)
    }

    @Test("Voice mode is the default for the plain protocol call")
    func voiceIsDefault() async throws {
        let entities = try await HeuristicExtractor()
            .extract(from: "Col and Cam came, plus two guests, we did 8.7k")
        #expect(entities.names == ["Col", "Cam"])
        #expect(entities.plusOnes == 2)
        #expect(entities.distanceKm == 8.7)
    }

    @Test("Poll mode returns the poll structure and only affirmative proposals")
    func pollMode() async throws {
        let lines = ["Yes ✓ 1 vote", "Aaron", "No 1 vote", "Anna"]
        let result = try await HeuristicExtractor()
            .extract(from: lines.joined(separator: "\n"), context: .pollScreenshot(lines: lines))
        #expect(result.entities.names == ["Aaron"])
        #expect(result.poll?.candidateNames == ["Aaron", "Anna"])
        #expect(!result.usedModel)
        #expect(result.warnings.isEmpty)
    }

    @Test("Poll mode can take the lines from the text blob")
    func pollModeFromText() {
        let text = "Yes ✓ 1 vote\nAaron\nNo 1 vote\nAnna"
        let result = HeuristicExtractor().extract(text: text, context: .pollScreenshot)
        #expect(result.entities.names == ["Aaron"])
    }

    @Test("A nameless card warns instead of proposing")
    func cardWarning() {
        let result = HeuristicExtractor().extract(lines: ["Yes", "13", "No", "4", "View votes"])
        #expect(result.warnings.contains(.namelessPollCard))
        #expect(result.entities.names.isEmpty)
    }

    @Test("Finding nothing at all is reported, not silently empty")
    func nothingFound() {
        let result = HeuristicExtractor().extract(text: "", context: .voice)
        #expect(result.entities.isEmpty)
        #expect(result.warnings == [.nothingFound])
    }

    @Test("U1's parser types now delegate to the U5 scanners")
    func u1Delegation() {
        #expect(VoiceEntryParser().parse(transcript: "Col came").names == ["Col"])
        #expect(PollScreenshotParser().parse(lines: ["Yes ✓ 1 vote", "Col"]).candidateNames == ["Col"])
        #expect(VoiceEntryParser().parse(transcript: "").isEmpty)
    }
}
