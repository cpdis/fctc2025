//
//  VoiceTranscriptScanner.swift
//  FCTCAttendanceKit
//
//  U5 — the deterministic half of voice parsing: one spoken sentence in,
//  `ExtractedEntities` out. No `Speech` import (that stays in the view layer), so
//  every rule is testable against `fixtures/attendance/voice-*.transcript.txt`.
//
//  Three passes, in this order, because each one removes noise for the next:
//
//   1. DISTANCE. "8.7k", "12 kays", "eight point seven k", "ten point four two
//      kilometres". A spelled-out number only counts as a distance when it either
//      carries a unit word or has a spoken decimal ("point"), which is what keeps the
//      "two" in "plus two guests" from being read as 2 km.
//   2. GUESTS. "plus two guests" → 2, "no guests" → 0 (explicitly none, not unknown),
//      "a plus one" → 1. When the speaker names them ("plus one guest, Priya") the
//      names are captured and the tokens consumed, so a guest never lands in the
//      roster proposal set (resolved Q2).
//   3. NAMES. Whatever is left: runs of capitalized, non-stop-word tokens, broken by
//      commas, conjunctions and lowercase filler. "Laura E" and "Kate B" survive as
//      one name each; "So today we had" and "turned up at the last minute" do not.
//
//  Nothing here knows the roster — matching is `NameMatcher`'s job downstream.
//

import Foundation

public struct VoiceTranscriptScanner: Sendable {

    public init() {}

    /// Parse a transcript into entities. Never throws; "found nothing" is `.empty`.
    public func scan(transcript: String) -> ExtractedEntities {
        let tokens = Self.tokenize(transcript)
        guard !tokens.isEmpty else { return .empty }

        var spans: [(start: Int, end: Int)] = []

        var distanceKm: Double?
        var distanceSpan: (start: Int, end: Int)?
        if let distance = Self.findDistance(tokens) {
            distanceKm = distance.value
            distanceSpan = (distance.start, distance.end)
            spans.append((distance.start, distance.end))
        }

        var plusOnes: Int?
        var guestNames: [String] = []
        if let guests = Self.findGuests(tokens, skipping: distanceSpan) {
            plusOnes = guests.count
            spans.append((guests.start, guests.end))
            if guests.count > 0 {
                let named = Self.collectGuestNames(
                    tokens,
                    from: guests.end,
                    limit: guests.count,
                    skipping: distanceSpan
                )
                if !named.names.isEmpty {
                    guestNames = named.names
                    spans.append((guests.end, named.end))
                }
            }
        }

        let names = Self.collectNames(tokens, masking: spans)
        return ExtractedEntities(
            names: names,
            plusOnes: plusOnes,
            distanceKm: distanceKm,
            guestNames: guestNames
        )
    }

    // MARK: - Vocabulary

    static let units: [String: Int] = [
        "zero": 0, "oh": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11,
        "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
        "seventeen": 17, "eighteen": 18, "nineteen": 19,
    ]

    static let tens: [String: Int] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fourty": 40, "fifty": 50,
        "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
    ]

    static let distanceUnits: Set<String> = [
        "k", "ks", "km", "kms", "kay", "kays", "kilometre", "kilometres",
        "kilometer", "kilometers",
    ]

    static let guestWords: Set<String> = [
        "guest", "guests", "plusone", "plusones", "ones", "one", "visitor",
        "visitors", "mate", "mates", "friend", "friends", "ringin", "ringins",
    ]

    static let connectors: Set<String> = [
        "and", "plus", "also", "with", "then", "n",
    ]

    /// Words that are never a name, even when speech recognition capitalizes them
    /// (sentence starts, "Came", proper-noun guesses).
    static let stopWords: Set<String> = [
        "so", "today", "tonight", "yesterday", "we", "i", "he", "she", "they",
        "them", "had", "has", "have", "was", "were", "is", "are", "am", "be",
        "been", "came", "come", "comes", "coming", "there", "here", "said",
        "says", "say", "turned", "turns", "turn", "showed", "shows", "show",
        "joined", "joins", "join", "made", "make", "did", "do", "done", "went",
        "go", "gone", "got", "ran", "run", "running", "runs", "jog", "jogged",
        "the", "a", "an", "at", "up", "on", "in", "out", "of", "for", "to",
        "too", "this", "that", "these", "those", "last", "first", "minute",
        "minutes", "morning", "evening", "afternoon", "night", "session",
        "soft", "sand", "beach", "track", "hills", "loop", "lap", "laps",
        "everyone", "everybody", "all", "both", "just", "only", "about",
        "around", "roughly", "approx", "approximately", "total", "point",
        "guest", "guests", "no", "none", "zero", "nobody", "plus", "and",
        "also", "with", "without", "but", "then", "ok", "okay", "um", "uh",
        "yeah", "yep", "well", "actually", "think", "reckon", "it", "its",
        "my", "our", "us", "who", "which", "when", "where", "km", "kms", "k",
        "kay", "kays", "kilometre", "kilometres", "kilometer", "kilometers",
    ]

    // MARK: - Tokens

    struct VoiceToken: Hashable, Sendable {
        let index: Int
        /// Original text including punctuation ("guests," / "8.7km" / "Laura").
        let text: String
        /// Letters only, lowercased ("guests" / "km" / "laura").
        let core: String
        /// Digits and decimal points only ("" / "8.7" / "").
        let numeric: String
        /// Ends a name run: the speaker paused here.
        let breaksRun: Bool

        var hasDigits: Bool {
            numeric.contains(where: { $0.isNumber })
        }

        var numericValue: Double? {
            var body = numeric
            while body.hasSuffix(".") { body = String(body.dropLast()) }
            guard !body.isEmpty else { return nil }
            return Double(body)
        }
    }

    static func tokenize(_ text: String) -> [VoiceToken] {
        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var tokens: [VoiceToken] = []
        tokens.reserveCapacity(words.count)
        for (index, word) in words.enumerated() {
            var core = ""
            var numeric = ""
            for character in word {
                if character.isLetter {
                    core.append(contentsOf: character.lowercased())
                } else if character.isNumber || character == "." {
                    numeric.append(character)
                }
            }
            let breaksRun = word.last.map { ",;:.!?".contains($0) } ?? false
            tokens.append(
                VoiceToken(
                    index: index,
                    text: word,
                    core: core,
                    numeric: numeric,
                    breaksRun: breaksRun
                )
            )
        }
        return tokens
    }

    // MARK: - Numbers

    struct ParsedNumber {
        let value: Double
        /// One past the last token consumed.
        let end: Int
        /// True when the speaker said "point" (a spoken decimal).
        let hadPoint: Bool
    }

    /// "twenty one" → 21, "eight" → 8. Integers only, no decimals.
    static func wordNumber(_ tokens: [VoiceToken], at index: Int) -> (value: Int, end: Int)? {
        guard index >= 0, index < tokens.count else { return nil }
        let core = tokens[index].core
        if let tensValue = tens[core] {
            var value = tensValue
            var end = index + 1
            if end < tokens.count, let unit = units[tokens[end].core], (1...9).contains(unit) {
                value += unit
                end += 1
            }
            return (value, end)
        }
        if let unit = units[core] { return (unit, index + 1) }
        return nil
    }

    /// A number starting at `index`, spoken or written, with optional "point x y".
    static func parseNumber(_ tokens: [VoiceToken], at index: Int) -> ParsedNumber? {
        guard index >= 0, index < tokens.count else { return nil }
        let token = tokens[index]
        if token.hasDigits {
            guard let value = token.numericValue else { return nil }
            return ParsedNumber(
                value: value,
                end: index + 1,
                hadPoint: token.numeric.contains(".")
            )
        }
        guard let whole = wordNumber(tokens, at: index) else { return nil }
        var value = Double(whole.value)
        var end = whole.end
        var hadPoint = false
        if end < tokens.count, tokens[end].core == "point" {
            var digits = ""
            var cursor = end + 1
            while cursor < tokens.count,
                  let digit = units[tokens[cursor].core],
                  digit <= 9 {
                digits.append(String(digit))
                cursor += 1
            }
            if !digits.isEmpty {
                value = Double("\(whole.value).\(digits)") ?? value
                hadPoint = true
                end = cursor
            }
        }
        return ParsedNumber(value: value, end: end, hadPoint: hadPoint)
    }

    // MARK: - Pass 1: distance

    static func findDistance(_ tokens: [VoiceToken]) -> (value: Double, start: Int, end: Int)? {
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            if token.hasDigits {
                if let value = token.numericValue {
                    // "8.7km" — number and unit in one token.
                    if distanceUnits.contains(token.core) {
                        return (value, index, index + 1)
                    }
                    if token.core.isEmpty {
                        // "12 kays" — unit in the next token.
                        if index + 1 < tokens.count,
                           distanceUnits.contains(tokens[index + 1].core) {
                            return (value, index, index + 2)
                        }
                        // "8.7" — a decimal on its own is a distance, a bare integer
                        // is not (it is far more likely a guest count).
                        if token.numeric.contains(".") {
                            return (value, index, index + 1)
                        }
                    }
                }
                index += 1
                continue
            }
            if let parsed = parseNumber(tokens, at: index) {
                let unitFollows = parsed.end < tokens.count
                    && distanceUnits.contains(tokens[parsed.end].core)
                if unitFollows {
                    return (parsed.value, index, parsed.end + 1)
                }
                if parsed.hadPoint {
                    return (parsed.value, index, parsed.end)
                }
            }
            index += 1
        }
        return nil
    }

    // MARK: - Pass 2: guests

    static func findGuests(
        _ tokens: [VoiceToken],
        skipping skip: (start: Int, end: Int)?
    ) -> (count: Int, start: Int, end: Int)? {
        var index = 0
        while index < tokens.count {
            if let skip, index >= skip.start, index < skip.end {
                index += 1
                continue
            }
            let core = tokens[index].core

            // "no guests" / "no plus ones" / "zero guests"
            if core == "no" || core == "zero" || core == "none" || core == "nil" {
                var cursor = index + 1
                if cursor < tokens.count, tokens[cursor].core == "plus" { cursor += 1 }
                if cursor < tokens.count, guestWords.contains(tokens[cursor].core) {
                    return (0, index, cursor + 1)
                }
                index += 1
                continue
            }

            // "plus two guests" / "plus one" / "plus a guest"
            if core == "plus" {
                var cursor = index + 1
                if cursor < tokens.count,
                   tokens[cursor].core == "a" || tokens[cursor].core == "an" {
                    cursor += 1
                }
                if cursor < tokens.count, let parsed = parseNumber(tokens, at: cursor) {
                    var end = parsed.end
                    if end < tokens.count, guestWords.contains(tokens[end].core) { end += 1 }
                    return (Int(parsed.value), index, end)
                }
                if cursor < tokens.count, guestWords.contains(tokens[cursor].core) {
                    return (1, index, cursor + 1)
                }
                index += 1
                continue
            }

            // "a guest"
            if core == "a" || core == "an" {
                let cursor = index + 1
                if cursor < tokens.count, guestWords.contains(tokens[cursor].core) {
                    return (1, index, cursor + 1)
                }
                index += 1
                continue
            }

            // "two guests"
            if let parsed = parseNumber(tokens, at: index),
               parsed.end < tokens.count,
               guestWords.contains(tokens[parsed.end].core) {
                return (Int(parsed.value), index, parsed.end + 1)
            }
            index += 1
        }
        return nil
    }

    /// Names spoken right after a guest clause ("plus one guest, Priya").
    static func collectGuestNames(
        _ tokens: [VoiceToken],
        from start: Int,
        limit: Int,
        skipping skip: (start: Int, end: Int)?
    ) -> (names: [String], end: Int) {
        var names: [String] = []
        var index = start
        var end = start
        while index < tokens.count, names.count < max(limit, 0) {
            if let skip, index >= skip.start, index < skip.end { break }
            let token = tokens[index]
            if token.core.isEmpty || connectors.contains(token.core) {
                index += 1
                continue
            }
            guard isNameToken(token) else { break }
            var run: [String] = []
            while index < tokens.count, isNameToken(tokens[index]) {
                run.append(strip(tokens[index].text))
                let stop = tokens[index].breaksRun
                index += 1
                if stop { break }
            }
            names.append(run.joined(separator: " "))
            end = index
        }
        return (names, end)
    }

    // MARK: - Pass 3: names

    static func collectNames(
        _ tokens: [VoiceToken],
        masking spans: [(start: Int, end: Int)]
    ) -> [String] {
        func isMasked(_ index: Int) -> Bool {
            spans.contains { index >= $0.start && index < $0.end }
        }

        var found: [String] = []
        var run: [String] = []

        func closeRun() {
            if !run.isEmpty {
                found.append(run.joined(separator: " "))
                run = []
            }
        }

        for token in tokens {
            if isMasked(token.index) {
                closeRun()
                continue
            }
            if isNameToken(token) {
                run.append(strip(token.text))
                if token.breaksRun { closeRun() }
            } else {
                closeRun()
            }
        }
        closeRun()

        var deduped: [String] = []
        var seen: Set<String> = []
        for name in found where !name.isEmpty {
            if seen.insert(name).inserted { deduped.append(name) }
        }
        return deduped
    }

    static func isNameToken(_ token: VoiceToken) -> Bool {
        guard let head = token.text.first, head.isLetter, head.isUppercase else { return false }
        guard !token.core.isEmpty else { return false }
        if stopWords.contains(token.core) || connectors.contains(token.core) { return false }
        if units[token.core] != nil || tens[token.core] != nil { return false }
        return true
    }

    static func strip(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet(charactersIn: ",;:.!?\"“”"))
    }
}
