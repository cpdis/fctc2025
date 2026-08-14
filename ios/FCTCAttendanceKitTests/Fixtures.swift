//
//  Fixtures.swift
//  FCTCAttendanceKitTests
//
//  U5 — loading `fixtures/attendance/` from the TEST BUNDLE.
//
//  `ios/project.yml` copies the fixture directory into the test bundle as a folder
//  reference (orchestrator grant, U5). Reading them through `Bundle(for:)` instead of
//  `#filePath` keeps the tests working when they run from a build product, from a
//  clean checkout, or on CI where the source tree is not where the compiler saw it.
//
//  The loader tries the folder-reference layout ("attendance/poll-1.ocr.txt") first
//  and a flat layout second, so it survives either XcodeGen resource style.
//

import Foundation

@testable import FCTCAttendanceKit

/// Anchor for `Bundle(for:)`: Swift Testing suites are structs, and `Bundle.module`
/// only exists for SwiftPM targets.
final class FixtureBundleToken {}

enum FixtureError: Error, CustomStringConvertible {
    case missing(String)

    var description: String {
        switch self {
        case .missing(let name):
            return """
            Fixture "\(name)" is not in the test bundle. Check that project.yml still \
            lists ../fixtures/attendance as a resource of FCTCAttendanceKitTests, then \
            re-run `xcodegen generate`.
            """
        }
    }
}

enum Fixtures {

    static let ocrFixtures = ["poll-1", "poll-2", "poll-card-nameless"]
    static let voiceFixtures = ["voice-1", "voice-2", "voice-3"]

    static var bundle: Bundle {
        Bundle(for: FixtureBundleToken.self)
    }

    static func url(_ fileName: String) throws -> URL {
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        if let found = bundle.url(forResource: base, withExtension: ext, subdirectory: "attendance") {
            return found
        }
        if let found = bundle.url(forResource: base, withExtension: ext) {
            return found
        }
        if let resources = bundle.resourceURL {
            let direct = resources
                .appendingPathComponent("attendance", isDirectory: true)
                .appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: direct.path) { return direct }
        }
        throw FixtureError.missing(fileName)
    }

    static func text(_ fileName: String) throws -> String {
        try String(contentsOf: url(fileName), encoding: .utf8)
    }

    /// OCR dumps are line-oriented; blank lines carry no meaning and are dropped.
    static func lines(_ fileName: String) throws -> [String] {
        try text(fileName)
            .split(whereSeparator: { $0.isNewline })
            .map(String.init)
    }

    static func expected(_ stem: String) throws -> ExpectedFixture {
        let data = try Data(contentsOf: url("\(stem).expected.json"))
        return try JSONDecoder().decode(ExpectedFixture.self, from: data)
    }
}

/// The `*.expected.json` schema documented in `fixtures/attendance/README.md`.
struct ExpectedFixture: Codable {

    struct Option: Codable {
        let label: String
        let voteCount: Int?
        let isAffirmative: Bool
        let rawNames: [String]
    }

    struct Ambiguity: Codable {
        let raw: String
        let candidates: [String]
    }

    let fixture: String
    let kind: String
    let season: Int
    let notes: [String]?

    // poll-ocr
    let isVoteDetailScreen: Bool?
    let needsVotesView: Bool?
    let reason: String?
    let options: [Option]?
    let candidateNames: [String]?

    // voice-transcript
    let plusOnes: Int?
    let distanceKm: Double?
    let guestNames: [String]?

    // both
    let names: [String]
    let ambiguous: [Ambiguity]
    let unmatchedRaw: [String]
}

/// The real 2026 sheet header names (verified against `fixtures/attendance/2026.csv`
/// by `apps-script/test/fixtures.checks.js`).
enum Roster {
    static let season2026 = [
        "Aaron", "Adam", "Alex 👑", "Alex B", "Alex Kr", "Anna", "Cam", "Celeste",
        "Chartt", "Claire", "Col", "Dan", "Dan B", "Darren", "Deano", "Fraser",
        "Grant", "Jack", "Joe", "Kate B", "Laura E", "Laura K", "Liam", "Ming",
        "Rhys", "Rohan", "Sam", "Scott", "Shane", "Tarquin", "Tim", "Toby", "Wes",
    ]

    static var matcher: NameMatcher {
        NameMatcher(roster: season2026)
    }
}

/// What a batch of raw names resolved to, bucketed the way the fixtures describe it.
struct MatchOutcome {
    var matched: [String] = []
    var ambiguousRaws: [String] = []
    var ambiguousCandidates: [[String]] = []
    /// Raw strings that produced no pre-check: `.unmatched` and `.suggestion` alike.
    var notMatched: [String] = []
    var suggestions: [String] = []
}

extension NameMatcher {

    func outcome(for raws: [String]) -> MatchOutcome {
        var outcome = MatchOutcome()
        for raw in raws {
            switch match(raw) {
            case .matched(let name, _):
                outcome.matched.append(name)
            case .ambiguous(let candidates):
                outcome.ambiguousRaws.append(raw)
                outcome.ambiguousCandidates.append(candidates)
            case .suggestion(let name, _):
                outcome.notMatched.append(raw)
                outcome.suggestions.append(name)
            case .unmatched:
                outcome.notMatched.append(raw)
            }
        }
        return outcome
    }
}
