//
//  NameMatcherTests.swift
//  FCTCAttendanceKitTests
//
//  U5 — the matcher, rule by rule, against the REAL 2026 roster (the collisions are
//  the point: `Alex 👑`/`Alex B`/`Alex Kr`, `Dan`/`Dan B`, `Laura E`/`Laura K`).
//
//  The load-bearing assertion in this file is negative: certain inputs must NEVER
//  produce an auto-check. Every table below that expects `.ambiguous` is a case where
//  a plausible-looking implementation would happily pick the wrong club member.
//

import Foundation
import Testing

@testable import FCTCAttendanceKit

@Suite("NameMatcher — normalization")
struct NormalizationTests {

    @Test("Case, diacritics, punctuation and whitespace all fold away", arguments: [
        ("Céleste", "celeste"),
        ("CELESTE", "celeste"),
        ("  Dan   B  ", "dan b"),
        ("O'Brien-Smith", "o brien smith"),
        ("Alex 👑", "alex"),
        ("Yes ✓ 13 votes", "yes 13 votes"),
        ("", ""),
    ])
    func core(input: String, expected: String) {
        #expect(NormalizedName(input).core == expected)
    }

    @Test("Symbols are stripped from the core but kept as a signature")
    func symbolSignature() {
        let crowned = NormalizedName("Alex 👑")
        #expect(crowned.core == "alex")
        #expect(crowned.symbols == "👑")
        #expect(crowned.identity != NormalizedName("Alex").identity)
        #expect(NormalizedName("Alex").symbols.isEmpty)
    }

    @Test("Compact form recovers OCR word splits")
    func compactForm() {
        #expect(NormalizedName("Scot t").compact == "scott")
        #expect(NormalizedName("Gra nt").compact == "grant")
        #expect(NormalizedName("Cel este").compact == "celeste")
    }

    @Test("Tokens, first and qualifier split the way the sheet keys do")
    func tokens() {
        let name = NormalizedName("Alex Kr")
        #expect(name.tokens == ["alex", "kr"])
        #expect(name.first == "alex")
        #expect(name.qualifier == "kr")
        #expect(NormalizedName("Col").qualifier.isEmpty)
        #expect(NormalizedName("   ").isEmpty)
    }
}

@Suite("NameMatcher — distances")
struct StringDistanceTests {

    @Test("Identical strings score 1 and empty strings score 0")
    func bounds() {
        #expect(StringDistance.similarity("scott", "scott") == 1.0)
        #expect(StringDistance.similarity("", "scott") == 0.0)
        #expect(StringDistance.similarity("scott", "") == 0.0)
        #expect(StringDistance.normalizedLevenshtein("", "") == 1.0)
    }

    @Test("Jaro-Winkler rewards shared prefixes")
    func prefixBonus() {
        let withPrefix = StringDistance.jaroWinkler("tarquln", "tarquin")
        let withoutPrefix = StringDistance.jaroWinkler("xarquln", "yarquin")
        #expect(withPrefix > withoutPrefix)
        #expect(withPrefix > 0.9)
    }

    @Test("Every score stays inside [0, 1]", arguments: [
        ("col", "colin"), ("dan", "dan b"), ("priya", "rhys"), ("a", "wes"),
        ("laura e", "laura k"), ("scott", "chartt"),
    ])
    func range(lhs: String, rhs: String) {
        let score = StringDistance.similarity(lhs, rhs)
        #expect(score >= 0.0)
        #expect(score <= 1.0)
    }

    @Test("Levenshtein counts real edits")
    func levenshtein() {
        #expect(StringDistance.levenshtein(Array("tarquln"), Array("tarquin")) == 1)
        #expect(StringDistance.levenshtein(Array("col"), Array("colin")) == 2)
        #expect(StringDistance.levenshtein(Array(""), Array("dan")) == 3)
    }
}

@Suite("NameMatcher — tiers and the ambiguity rule")
struct NameMatcherRuleTests {

    static let matcher = NameMatcher(roster: Roster.season2026)

    // MARK: Auto-check

    @Test("Unambiguous names auto-check", arguments: [
        ("Aaron", "Aaron"),
        ("Col", "Col"),
        ("Cam", "Cam"),
        ("Kate B", "Kate B"),
        ("Laura E", "Laura E"),
        ("Laura K", "Laura K"),
        ("Dan B", "Dan B"),
        ("Alex B", "Alex B"),
        ("Alex Kr", "Alex Kr"),
        ("Toby", "Toby"),
        ("Wes", "Wes"),
    ])
    func exactKeys(raw: String, expected: String) {
        #expect(Self.matcher.match(raw).autoCheckName == expected)
    }

    @Test("The crowned Alex is an exact key, not a bare first name")
    func decoratedKey() {
        #expect(Self.matcher.match("Alex 👑").autoCheckName == "Alex 👑")
        #expect(Self.matcher.match("alex 👑").autoCheckName == "Alex 👑")
        #expect(Self.matcher.match("ALEX👑").autoCheckName == "Alex 👑")
    }

    @Test("OCR damage still auto-checks", arguments: [
        ("Scot t", "Scott"),
        ("Gra nt", "Grant"),
        ("Cel este", "Celeste"),
        ("Céleste", "Celeste"),
        ("Tarquln", "Tarquin"),
    ])
    func ocrDamage(raw: String, expected: String) {
        #expect(Self.matcher.match(raw).autoCheckName == expected)
    }

    @Test("The nickname table maps long forms onto sheet keys", arguments: [
        ("Colin", "Col"),
        ("Colm", "Col"),
        ("Cameron", "Cam"),
        ("Camm", "Cam"),
        ("Timothy", "Tim"),
        ("Samuel", "Sam"),
        ("Wesley", "Wes"),
        ("Scotty", "Scott"),
        ("Reece", "Rhys"),
        ("Alex Kravchenko", "Alex Kr"),
    ])
    func nicknames(raw: String, expected: String) {
        #expect(Self.matcher.match(raw).autoCheckName == expected)
    }

    @Test("A qualified display name resolves through its initial", arguments: [
        ("Dan Brown", "Dan B"),
        ("Alex K", "Alex Kr"),
        ("Colin Reid", "Col"),
    ])
    func qualifiers(raw: String, expected: String) {
        #expect(Self.matcher.match(raw).autoCheckName == expected)
    }

    // MARK: Never auto-pick

    @Test("Bare shared first names are ambiguous — including exact roster keys", arguments: [
        ("Alex", ["Alex 👑", "Alex B", "Alex Kr"]),
        ("alex", ["Alex 👑", "Alex B", "Alex Kr"]),
        ("Alexander", ["Alex 👑", "Alex B", "Alex Kr"]),
        ("Dan", ["Dan", "Dan B"]),
        ("Daniel", ["Dan", "Dan B"]),
        ("Danny", ["Dan", "Dan B"]),
        ("Da n", ["Dan", "Dan B"]),
        ("Laura", ["Laura E", "Laura K"]),
    ])
    func ambiguity(raw: String, candidates: [String]) {
        let match = Self.matcher.match(raw)
        #expect(match.autoCheckName == nil)
        #expect(match.needsHuman)
        guard case .ambiguous(let found) = match else {
            Issue.record("\(raw) must be ambiguous, got \(match)")
            return
        }
        #expect(found == candidates)
    }

    @Test("`Dan` is ambiguous even though it is itself a roster key (post-U1 ruling)")
    func exactKeyThatIsAlsoAFirstName() {
        guard case .ambiguous(let candidates) = Self.matcher.match("Dan") else {
            Issue.record("bare Dan must never auto-pick")
            return
        }
        #expect(candidates == ["Dan", "Dan B"])
    }

    @Test("Nothing outside the roster is ever pre-checked", arguments: [
        "Priya B", "Priya", "Zeb", "Bartholomew", "",
    ])
    func strangers(raw: String) {
        #expect(Self.matcher.match(raw).autoCheckName == nil)
    }

    @Test("A guest with a roster-ish name lands in the unmatched tier")
    func unmatchedTier() {
        guard case .unmatched(let suggestions) = Self.matcher.match("Priya B") else {
            Issue.record("Priya B must not resolve to a roster member")
            return
        }
        #expect(!suggestions.contains("Priya B"))
        #expect(suggestions.count <= 5)
    }

    // MARK: Tier mechanics

    @Test("Tiers are ordered and the thresholds are the ones the plan fixed")
    func thresholds() {
        #expect(NameMatcher.suggestThreshold == 0.60)
        #expect(NameMatcher.autoCheckThreshold == 0.85)
        #expect(NameMatcher.ambiguityBand == 0.10)
    }

    @Test("A match's score never sits below the auto-check bar")
    func scoreFloor() {
        guard case .matched(_, let score) = Self.matcher.match("Tarquln") else {
            Issue.record("Tarquln should match Tarquin")
            return
        }
        #expect(score >= NameMatcher.autoCheckThreshold)
        #expect(score <= 1.0)
    }

    @Test("An empty roster can never produce a match or a suggestion")
    func emptyRoster() {
        let empty = NameMatcher(roster: [])
        for raw in ["Aaron", "Alex 👑", "", "Colin"] {
            #expect(empty.match(raw).autoCheckName == nil)
            #expect(empty.match(raw).offeredNames.isEmpty)
        }
    }

    @Test("Batch helpers preserve order and only pre-check safe hits")
    func batches() {
        let raws = ["Aaron", "Dan", "Scot t", "Priya B", "Colin"]
        let results = Self.matcher.match(all: raws)
        #expect(results.map(\.raw) == raws)
        #expect(Self.matcher.autoCheckNames(for: raws) == ["Aaron", "Col", "Scott"])
    }

    @Test("A one-person roster still refuses a stranger")
    func tinyRoster() {
        let solo = NameMatcher(roster: ["Col"])
        #expect(solo.match("Colin").autoCheckName == "Col")
        #expect(solo.match("Bartholomew").autoCheckName == nil)
    }

    @Test("The nickname table can be swapped out")
    func customNicknames() {
        let matcher = NameMatcher(roster: Roster.season2026, nicknames: ["chartreuse": "Chartt"])
        #expect(matcher.match("Chartreuse").autoCheckName == "Chartt")
        // …and the built-in mappings are gone when you replace the table.
        #expect(matcher.match("Colin").autoCheckName == "Col")
    }
}
