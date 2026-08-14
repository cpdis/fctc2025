//
//  NameMatcher.swift
//  FCTCAttendanceKit
//
//  U5 — normalization, fuzzy scoring, the nickname table and the ambiguity rule.
//
//  Contract (from the plan, unchanged since U1):
//   • The SHEET's short names are the canonical keys. The nickname table maps
//     long-forms and OCR/ASR variants ONTO them ("Colin" → `Col`,
//     "Alex Kravchenko" → `Alex Kr`), never the reverse.
//   • Confidence tiers: ≥ autoCheck → check it; suggest…autoCheck → "did you mean…";
//     below suggest → unmatched (offer add-as-new).
//   • AMBIGUITY RULE (load-bearing): the 2026 roster has near-collisions
//     (`Alex 👑` / `Alex B` / `Alex Kr`, `Dan` / `Dan B`, `Laura E` / `Laura K`).
//     A first-name-only hit must return ALL candidates and auto-pick NONE.
//     Orchestrator ruling (post-U1): this holds even when the query IS an exact
//     roster key — bare "Dan" is ambiguous between `Dan` and `Dan B`.
//
//  Resolution order (first rule that fires wins):
//   1. Exact key WITH its symbol signature   → matched   ("Alex 👑" → `Alex 👑`)
//   2. Bare shared first name                → ambiguous ("Dan" → [`Dan`, `Dan B`])
//   3. Exact key                             → matched   ("Dan B" → `Dan B`)
//   4. Nickname redirect, then retry 1-3     → …         ("Colin" → "Col" → `Col`)
//   5. Qualifier prefix                      → matched   ("Alex Kravchenko" → `Alex Kr`)
//   6. Fuzzy scoring + the 0.1 ambiguity band
//

import Foundation

public enum NameMatch: Hashable, Sendable {
    /// Confident single hit — safe to pre-check.
    case matched(name: String, score: Double)
    /// Plausible but below the auto-check bar; the UI offers "did you mean…".
    /// Never pre-checked.
    case suggestion(name: String, score: Double)
    /// Several roster names are plausible; the human picks. Never auto-checked.
    case ambiguous(candidates: [String])
    /// Nothing close enough; `suggestions` may still be shown as weak hints.
    case unmatched(suggestions: [String])
}

extension NameMatch {

    /// The roster name to pre-check, or nil for every non-committal tier.
    public var autoCheckName: String? {
        if case .matched(let name, _) = self { return name }
        return nil
    }

    /// Names the UI should offer the human, in the order to show them.
    public var offeredNames: [String] {
        switch self {
        case .matched(let name, _): return [name]
        case .suggestion(let name, _): return [name]
        case .ambiguous(let candidates): return candidates
        case .unmatched(let suggestions): return suggestions
        }
    }

    /// True when the app must ask before anything is checked.
    public var needsHuman: Bool {
        if case .matched = self { return false }
        return true
    }
}

public struct NameMatcher: Sendable {

    /// Score at or above which a hit is pre-checked automatically.
    public static let autoCheckThreshold = 0.85
    /// Score at or above which a hit is offered as "did you mean…".
    public static let suggestThreshold = 0.60
    /// Runners-up within this much of the top score are contenders, not also-rans.
    public static let ambiguityBand = 0.10
    /// How many nickname redirects one query may take (loop guard).
    static let maxRedirects = 2

    /// Canonical sheet names, exactly as they appear in the header row.
    public let roster: [String]
    /// Variant → canonical sheet name. See `NicknameTable`.
    public let nicknames: [String: String]

    private let normalizedRoster: [NormalizedName]

    public init(roster: [String], nicknames: [String: String] = NicknameTable.defaults) {
        self.roster = roster
        self.nicknames = nicknames
        self.normalizedRoster = roster.map { NormalizedName($0) }
    }

    /// Resolve one raw extracted name against the roster.
    public func match(_ raw: String) -> NameMatch {
        resolve(raw, depth: 0)
    }

    /// Resolve a batch, preserving input order. Convenience for the parsers.
    public func match(all raws: [String]) -> [(raw: String, match: NameMatch)] {
        raws.map { ($0, match($0)) }
    }

    /// The subset of `raws` that is safe to pre-check, deduped, in roster order.
    public func autoCheckNames(for raws: [String]) -> [String] {
        var picked: Set<String> = []
        for raw in raws {
            if let name = match(raw).autoCheckName { picked.insert(name) }
        }
        return roster.filter { picked.contains($0) }
    }

    // MARK: - Resolution

    private func resolve(_ raw: String, depth: Int) -> NameMatch {
        let query = NormalizedName(raw)
        guard !query.isEmpty, !roster.isEmpty else { return .unmatched(suggestions: []) }

        // 1. Exact key including its symbol signature. A decorated query ("Alex 👑")
        //    carries a disambiguator no other roster key has, so it is not "bare".
        let exact = rosterIndices { $0.identity == query.identity }
        if exact.count == 1, !query.symbols.isEmpty {
            return .matched(name: roster[exact[0]], score: 1.0)
        }

        // 2. Bare first name shared by several members — ask, never guess. This runs
        //    BEFORE plain exact-key equality on purpose (orchestrator ruling: "Dan").
        if query.tokens.count == 1, query.symbols.isEmpty {
            let sharers = rosterIndices { $0.first == query.core }
            if sharers.count >= 2 {
                return .ambiguous(candidates: sharers.map { roster[$0] })
            }
        }

        // 3. Exact key, undecorated and unshared.
        if exact.count == 1 {
            return .matched(name: roster[exact[0]], score: 1.0)
        }

        // 4. Nickname redirect, then start over with the canonical spelling.
        if depth < Self.maxRedirects, let redirect = nicknameRedirect(for: query) {
            return resolve(redirect, depth: depth + 1)
        }

        // 5. Qualifier prefix: "Alex Kravchenko" → `Alex Kr`, "Dan Brown" → `Dan B`.
        if query.tokens.count > 1 {
            let hits = rosterIndices { candidate in
                candidate.first == query.first
                    && !candidate.qualifier.isEmpty
                    && (candidate.qualifier.hasPrefix(query.qualifier)
                        || query.qualifier.hasPrefix(candidate.qualifier))
            }
            if hits.count == 1 {
                return .matched(name: roster[hits[0]], score: 0.95)
            }
            if hits.count > 1 {
                return .ambiguous(candidates: hits.map { roster[$0] })
            }
        }

        // 6. Fuzzy scoring over (full name, compacted name, first token).
        return scoredMatch(for: query)
    }

    private func scoredMatch(for query: NormalizedName) -> NameMatch {
        var scored: [(index: Int, score: Double)] = []
        scored.reserveCapacity(normalizedRoster.count)
        for (index, candidate) in normalizedRoster.enumerated() {
            let score = max(
                StringDistance.similarity(query.core, candidate.core),
                max(
                    StringDistance.similarity(query.compact, candidate.compact),
                    StringDistance.similarity(query.first, candidate.first)
                )
            )
            scored.append((index, score))
        }
        // Highest score first; ties keep roster (sheet) order.
        scored.sort { lhs, rhs in
            lhs.score == rhs.score ? lhs.index < rhs.index : lhs.score > rhs.score
        }
        guard let top = scored.first else { return .unmatched(suggestions: []) }

        if top.score < Self.suggestThreshold {
            let hints = scored.prefix(3)
                .filter { $0.score >= Self.suggestThreshold - 0.1 }
                .map { roster[$0.index] }
            return .unmatched(suggestions: hints)
        }

        let contenders = scored
            .filter { top.score - $0.score <= Self.ambiguityBand && $0.score >= Self.suggestThreshold }
            .sorted { $0.index < $1.index }
            .map { roster[$0.index] }

        if contenders.count >= 2 {
            // A tight cluster at auto-check strength is a real collision: ask.
            if top.score >= Self.autoCheckThreshold {
                return .ambiguous(candidates: contenders)
            }
            // A tight cluster of weak scores is noise, not a collision: nothing is
            // close enough to name, so offer add-as-new with the cluster as hints.
            return .unmatched(suggestions: Array(contenders.prefix(5)))
        }

        if top.score >= Self.autoCheckThreshold {
            return .matched(name: roster[top.index], score: top.score)
        }
        return .suggestion(name: roster[top.index], score: top.score)
    }

    // MARK: - Helpers

    private func rosterIndices(where predicate: (NormalizedName) -> Bool) -> [Int] {
        normalizedRoster.indices.filter { predicate(normalizedRoster[$0]) }
    }

    /// The canonical spelling this query should be retried as, if the table knows it.
    private func nicknameRedirect(for query: NormalizedName) -> String? {
        if let whole = nicknames[query.core], NormalizedName(whole).core != query.core {
            return whole
        }
        guard query.tokens.count > 1, let head = nicknames[query.first] else { return nil }
        var parts = [head]
        parts.append(contentsOf: query.tokens.dropFirst())
        let rebuilt = parts.joined(separator: " ")
        return NormalizedName(rebuilt).core == query.core ? nil : rebuilt
    }
}
