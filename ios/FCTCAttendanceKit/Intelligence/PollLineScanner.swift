//
//  PollLineScanner.swift
//  FCTCAttendanceKit
//
//  U5 — the deterministic half of poll parsing: WhatsApp chrome in, option blocks and
//  candidate names out. Pure `[String]` → `PollParseResult`, no Vision import, so it
//  runs against `fixtures/attendance/*.ocr.txt` with no camera roll and no simulator.
//  U6 owns the image → lines step and hands its output straight to `scan(lines:)`.
//
//  The two rules that do most of the work:
//
//  1. NOTHING BEFORE THE FIRST OPTION HEADER IS A NAME. On a "View votes" screen the
//     lines above the first option are the status bar, "Poll", the group name, the
//     question and "Select one or more". On a poll CARD the author's name sits up
//     there too ("Colin" in `poll-card-nameless.ocr.txt`) — a name-shaped line that is
//     emphatically not a voter. Starting only after the first option header drops all
//     of them without a brittle list of things-that-look-like-chrome.
//  2. NO NAMES ⇒ NOT THE VOTES SCREEN. A card gives option labels and counts and
//     nothing else, so `isVoteDetailScreen` is false and the UI sends the user back
//     for the "View votes" screenshot (resolved Q4) instead of proposing nothing.
//

import Foundation

public struct PollLineScanner: Sendable {

    /// Option labels recognised on their own line (the poll-card layout puts the count
    /// on the NEXT line). Kept tight so a voter's name is never mistaken for an option.
    static let optionLabels: Set<String> = [
        "yes", "no", "maybe", "nope", "yep", "yeah", "probably", "unsure",
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
        "mon", "tue", "tues", "wed", "weds", "thu", "thur", "thurs", "fri", "sat", "sun",
        "both", "either", "neither", "in", "out",
    ]

    /// Options that do NOT mean "coming". Everything else (Yes, a day name) does.
    static let negativeLabels: Set<String> = [
        "no", "nope", "maybe", "unsure", "neither", "out", "cant", "cannot", "sorry",
    ]

    /// Whole lines that are always WhatsApp chrome, wherever they appear.
    static let chromeLines: Set<String> = [
        "poll", "polls", "select one or more", "select one", "view votes",
        "view all votes", "see votes", "who voted", "votes", "vote", "results",
        "poll results", "final results", "tap to vote", "anonymous poll",
        "you voted", "back", "cancel", "done", "close", "forwarded", "edited",
    ]

    public init() {}

    /// Parse one screenshot's OCR lines.
    public func scan(lines: [String]) -> PollParseResult {
        var options: [PollOption] = []
        var candidateNames: [String] = []
        var seen: Set<String> = []
        var started = false

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            let core = NormalizedName(line).core

            if Self.isTimestamp(line) || Self.isPercentage(line) { continue }
            if Self.chromeLines.contains(core) { continue }

            if let header = Self.inlineOptionHeader(line) {
                options.append(
                    PollOption(
                        label: header.label,
                        voteCount: header.count,
                        rawNames: [],
                        isAffirmative: Self.isAffirmative(header.label)
                    )
                )
                started = true
                continue
            }

            if Self.optionLabels.contains(core), !line.hasSuffix("?") {
                let label = Self.cleaned(line)
                options.append(
                    PollOption(
                        label: label.isEmpty ? line : label,
                        voteCount: nil,
                        rawNames: [],
                        isAffirmative: Self.isAffirmative(label.isEmpty ? line : label)
                    )
                )
                started = true
                continue
            }

            // Everything above the first option header is header chrome by definition.
            guard started, !options.isEmpty else { continue }

            if let count = Self.standaloneCount(line) {
                if options[options.count - 1].voteCount == nil {
                    options[options.count - 1].voteCount = count
                }
                continue
            }

            guard Self.isNameLike(line) else { continue }
            options[options.count - 1].rawNames.append(line)
            if seen.insert(line).inserted {
                candidateNames.append(line)
            }
        }

        let hasNames = options.contains { !$0.rawNames.isEmpty }
        return PollParseResult(
            isVoteDetailScreen: hasNames,
            options: options,
            candidateNames: candidateNames
        )
    }

    // MARK: - Line classification

    /// "Yes ✓ 13 votes" → ("Yes", 13). Nil when the line is not an option header.
    static func inlineOptionHeader(_ line: String) -> (label: String, count: Int)? {
        let words = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard words.count >= 3 else { return nil }
        let last = words[words.count - 1].lowercased()
        guard last == "votes" || last == "vote" else { return nil }
        let countWord = words[words.count - 2]
        guard !countWord.isEmpty, countWord.allSatisfy(\.isNumber),
              let count = Int(countWord) else { return nil }
        let labelWords = words[0..<(words.count - 2)]
            .map { cleaned($0) }
            .filter { !$0.isEmpty }
        let label = labelWords.joined(separator: " ")
        guard !label.isEmpty else { return nil }
        return (label, count)
    }

    /// A line that is only a count: "13" or "13 votes".
    static func standaloneCount(_ line: String) -> Int? {
        let words = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        if words.count == 1, words[0].count <= 4, words[0].allSatisfy(\.isNumber) {
            return Int(words[0])
        }
        if words.count == 2, words[0].allSatisfy(\.isNumber) {
            let unit = words[1].lowercased()
            if unit == "votes" || unit == "vote" { return Int(words[0]) }
        }
        return nil
    }

    /// "9:41", "19:42", "9:41 AM".
    static func isTimestamp(_ line: String) -> Bool {
        var body = line.lowercased().trimmingCharacters(in: .whitespaces)
        for suffix in ["a.m.", "p.m.", "am", "pm"] where body.hasSuffix(suffix) {
            body = String(body.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
            break
        }
        let parts = body.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        let hour = parts[0]
        let minute = parts[1]
        guard (1...2).contains(hour.count), minute.count == 2 else { return false }
        return hour.allSatisfy(\.isNumber) && minute.allSatisfy(\.isNumber)
    }

    /// "62%".
    static func isPercentage(_ line: String) -> Bool {
        let body = line.trimmingCharacters(in: .whitespaces)
        guard body.hasSuffix("%") else { return false }
        let digits = body.dropLast().trimmingCharacters(in: .whitespaces)
        return !digits.isEmpty && digits.allSatisfy(\.isNumber)
    }

    /// Could this line be somebody's name?
    static func isNameLike(_ line: String) -> Bool {
        let body = line.trimmingCharacters(in: .whitespaces)
        guard body.count >= 2, body.count <= 40 else { return false }
        guard !body.hasSuffix("?"), !body.hasSuffix(":") else { return false }
        let normalized = NormalizedName(body)
        guard !normalized.isEmpty, normalized.tokens.count <= 4 else { return false }
        guard normalized.core.contains(where: { $0.isLetter }) else { return false }
        if chromeLines.contains(normalized.core) { return false }
        if optionLabels.contains(normalized.core) { return false }
        return true
    }

    /// Does a vote for this option mean "I'm coming"?
    static func isAffirmative(_ label: String) -> Bool {
        !negativeLabels.contains(NormalizedName(label).core)
    }

    /// Strip symbols (✓) and edge punctuation from one word or line.
    static func cleaned(_ text: String) -> String {
        var kept = ""
        for character in text where !NormalizedName.isSymbolic(character) {
            kept.append(character)
        }
        return kept.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ",.;:-–—"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
