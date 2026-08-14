//
//  NameMatcher.swift
//  FCTCAttendanceKit
//
//  STUB (U1) — real normalization, fuzzy scoring and the nickname table land in U5.
//
//  Contract that U5 must honour (from the plan):
//   • The SHEET's short names are the canonical keys. The nickname table maps
//     long-forms and OCR/ASR variants ONTO them ("Colin" → `Col`,
//     "Alex Kravchenko" → `Alex Kr`), never the reverse.
//   • Confidence tiers: ≥ autoCheck → check it; suggest…autoCheck → "did you mean…";
//     below suggest → unmatched (offer add-as-new).
//   • AMBIGUITY RULE (load-bearing): the 2026 roster has near-collisions
//     (`Alex 👑` / `Alex B` / `Alex Kr`, `Dan` / `Dan B`, `Laura E` / `Laura K`).
//     A first-name-only hit must return ALL candidates and auto-pick NONE.
//

import Foundation

public enum NameMatch: Hashable, Sendable {
    /// Confident single hit — safe to pre-check.
    case matched(name: String, score: Double)
    /// Several roster names are plausible; the human picks. Never auto-checked.
    case ambiguous(candidates: [String])
    /// Nothing close enough; `suggestions` may still be shown as weak hints.
    case unmatched(suggestions: [String])
}

public struct NameMatcher: Sendable {

    /// Score at or above which a hit is pre-checked automatically.
    public static let autoCheckThreshold = 0.85
    /// Score at or above which a hit is offered as "did you mean…".
    public static let suggestThreshold = 0.60

    /// Canonical sheet names, exactly as they appear in the header row.
    public let roster: [String]

    public init(roster: [String]) {
        self.roster = roster
    }

    /// Resolve one raw extracted name against the roster.
    ///
    /// TODO(U5): implement normalization (case/diacritics/emoji/punctuation),
    /// Jaro-Winkler + Levenshtein scoring, the nickname table, and the ambiguity rule.
    /// The stub resolves nothing, which is the safe default: nothing gets pre-checked.
    public func match(_ raw: String) -> NameMatch {
        .unmatched(suggestions: [])
    }

    /// Resolve a batch, preserving input order. Convenience for the parsers.
    public func match(all raws: [String]) -> [(raw: String, match: NameMatch)] {
        raws.map { ($0, match($0)) }
    }
}
