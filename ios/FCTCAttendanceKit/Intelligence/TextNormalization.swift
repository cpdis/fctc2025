//
//  TextNormalization.swift
//  FCTCAttendanceKit
//
//  U5 — the pure text primitives `NameMatcher` is built on.
//
//  Foundation only (no Vision, no Speech, no FoundationModels) so every rule here is
//  fixture-testable on any platform that can run the kit's tests.
//
//  Normalization is deliberately LOSSY IN TWO CHANNELS, not one:
//   • `core`    — casefolded, diacritics stripped, punctuation/symbols replaced by
//                 spaces, whitespace collapsed ("Céleste" → "celeste", "Alex 👑" → "alex").
//   • `symbols` — the symbol/emoji characters that were stripped, kept as a signature.
//  The sheet uses an emoji as a real disambiguator (`Alex 👑` vs `Alex B` vs `Alex Kr`),
//  so throwing the crown away entirely would make an exact key unresolvable. Keeping it
//  in a side channel lets `NameMatcher` treat "Alex 👑" as an exact key hit while a bare
//  "Alex" stays ambiguous.
//

import Foundation

/// A raw name reduced to comparable parts.
public struct NormalizedName: Hashable, Sendable {

    /// The string this was built from, untouched.
    public let raw: String
    /// Casefolded, diacritic/punctuation/symbol-free, single-spaced ("alex kr").
    public let core: String
    /// `core` split on spaces (["alex", "kr"]).
    public let tokens: [String]
    /// `core` with the spaces removed ("alexkr") — recovers OCR word-splits
    /// ("Scot t" → "scott").
    public let compact: String
    /// The symbol/emoji characters that were stripped, deduped and sorted ("👑").
    public let symbols: String

    public init(_ raw: String) {
        self.raw = raw
        let folded = raw.folding(
            options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        var scrubbed = ""
        scrubbed.reserveCapacity(folded.count)
        var found: Set<Character> = []
        for character in folded {
            if character.isLetter || character.isNumber {
                scrubbed.append(contentsOf: character.lowercased())
            } else {
                if NormalizedName.isSymbolic(character) {
                    found.insert(character)
                }
                scrubbed.append(" ")
            }
        }
        let parts = scrubbed
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
        self.tokens = parts
        self.core = parts.joined(separator: " ")
        self.compact = parts.joined()
        self.symbols = String(found.sorted())
    }

    /// First token ("alex" for "Alex Kr"); "" when the name normalized away.
    public var first: String {
        tokens.first ?? ""
    }

    /// Everything after the first token ("kr" for "Alex Kr"); "" when there is none.
    public var qualifier: String {
        guard tokens.count > 1 else { return "" }
        return tokens.dropFirst().joined(separator: " ")
    }

    /// Core plus symbol signature — two roster keys are the SAME key only if both match.
    public var identity: String {
        core + "|" + symbols
    }

    public var isEmpty: Bool {
        core.isEmpty
    }

    /// True for emoji and other symbol characters (crowns, check marks, arrows…).
    static func isSymbolic(_ character: Character) -> Bool {
        if character.isSymbol { return true }
        return character.unicodeScalars.contains { $0.properties.isEmojiPresentation }
    }
}

/// Edit-distance primitives. Pure functions over `Character` arrays so grapheme
/// clusters (an emoji is one `Character`) count as one unit.
public enum StringDistance {

    /// Jaro similarity in [0, 1].
    public static func jaro(_ lhs: [Character], _ rhs: [Character]) -> Double {
        let leftCount = lhs.count
        let rightCount = rhs.count
        if leftCount == 0 || rightCount == 0 { return 0.0 }
        if lhs == rhs { return 1.0 }

        let window = max(max(leftCount, rightCount) / 2 - 1, 0)
        var leftFlags = [Bool](repeating: false, count: leftCount)
        var rightFlags = [Bool](repeating: false, count: rightCount)
        var matches = 0

        for i in 0..<leftCount {
            let low = max(0, i - window)
            let high = min(i + window, rightCount - 1)
            if low > high { continue }
            for j in low...high where !rightFlags[j] && lhs[i] == rhs[j] {
                leftFlags[i] = true
                rightFlags[j] = true
                matches += 1
                break
            }
        }
        if matches == 0 { return 0.0 }

        var transpositions = 0
        var k = 0
        for i in 0..<leftCount where leftFlags[i] {
            while k < rightCount && !rightFlags[k] { k += 1 }
            if k >= rightCount { break }
            if lhs[i] != rhs[k] { transpositions += 1 }
            k += 1
        }
        transpositions /= 2

        let m = Double(matches)
        return (m / Double(leftCount)
            + m / Double(rightCount)
            + (m - Double(transpositions)) / m) / 3.0
    }

    /// Jaro-Winkler: Jaro with a bonus for a shared prefix (up to 4 characters).
    public static func jaroWinkler(_ lhs: String, _ rhs: String) -> Double {
        let left = Array(lhs)
        let right = Array(rhs)
        let base = jaro(left, right)
        if base <= 0.0 { return 0.0 }
        var prefix = 0
        for (a, b) in zip(left, right) {
            if a != b || prefix == 4 { break }
            prefix += 1
        }
        return base + 0.1 * Double(prefix) * (1.0 - base)
    }

    /// Classic Levenshtein edit distance.
    public static func levenshtein(_ lhs: [Character], _ rhs: [Character]) -> Int {
        if lhs == rhs { return 0 }
        if lhs.isEmpty { return rhs.count }
        if rhs.isEmpty { return lhs.count }

        var previous = Array(0...rhs.count)
        var current = [Int](repeating: 0, count: rhs.count + 1)
        for i in 1...lhs.count {
            current[0] = i
            for j in 1...rhs.count {
                let substitution = previous[j - 1] + (lhs[i - 1] == rhs[j - 1] ? 0 : 1)
                current[j] = min(previous[j] + 1, current[j - 1] + 1, substitution)
            }
            previous = current
        }
        return previous[rhs.count]
    }

    /// Levenshtein scaled into [0, 1], where 1 means identical.
    public static func normalizedLevenshtein(_ lhs: String, _ rhs: String) -> Double {
        let left = Array(lhs)
        let right = Array(rhs)
        let longest = max(left.count, right.count)
        if longest == 0 { return 1.0 }
        return 1.0 - Double(levenshtein(left, right)) / Double(longest)
    }

    /// The score the matcher uses for one pair of strings: the more forgiving of
    /// Jaro-Winkler (good at transpositions/prefixes) and normalized Levenshtein
    /// (good at insertions/deletions). Empty inputs score 0, never 1.
    public static func similarity(_ lhs: String, _ rhs: String) -> Double {
        if lhs.isEmpty || rhs.isEmpty { return 0.0 }
        return max(jaroWinkler(lhs, rhs), normalizedLevenshtein(lhs, rhs))
    }
}
