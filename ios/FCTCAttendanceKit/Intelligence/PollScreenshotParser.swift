//
//  PollScreenshotParser.swift
//  FCTCAttendanceKit
//
//  STUB (U1) — the Vision pipeline and chrome-line filtering land in U6.
//
//  Input is the LINE DUMP Vision produces for a WhatsApp screenshot; this type is
//  pure (no Vision import) so it can be fixture-tested without a camera roll. The
//  fixtures live at `fixtures/attendance/*.ocr.txt` with matching
//  `*.expected.json`.
//
//  Design notes carried from the plan:
//   • The user is coached (one-time screen) to screenshot the "View votes" DETAIL
//     view, which lists plain voter names grouped under option headers.
//   • A poll CARD screenshot (counts, no names) must be DETECTED, not guessed at:
//     `isVoteDetailScreen == false` → prompt for the votes view
//     (`fixtures/attendance/poll-card-nameless.ocr.txt`).
//   • Multi-screenshot import = union of candidates with dedupe.
//   • Poll "yes" ≠ attended: everything here only ever PROPOSES checks.
//

import Foundation

/// One option block in the "View votes" view: its header line, its vote count and the
/// voter names listed under it.
public struct PollOption: Codable, Hashable, Sendable {
    /// Option text as OCR'd ("Yes", "No", "Maybe", "Friday").
    public var label: String
    /// Count parsed from the header ("Yes ✓ 12 votes" → 12); nil when unreadable.
    public var voteCount: Int?
    /// Raw voter name lines under this option, in screen order.
    public var rawNames: [String]
    /// Whether a vote for this option means "coming" (Yes/day-name) as opposed to
    /// No/Maybe. Only affirmative options seed pre-checks.
    public var isAffirmative: Bool

    public init(
        label: String,
        voteCount: Int? = nil,
        rawNames: [String] = [],
        isAffirmative: Bool = true
    ) {
        self.label = label
        self.voteCount = voteCount
        self.rawNames = rawNames
        self.isAffirmative = isAffirmative
    }
}

public struct PollParseResult: Codable, Hashable, Sendable {
    /// False for a poll card with counts but no names → coach the user to open
    /// "View votes".
    public var isVoteDetailScreen: Bool
    /// Option blocks in screen order.
    public var options: [PollOption]
    /// Every name line found, deduped, in screen order.
    public var candidateNames: [String]

    public init(
        isVoteDetailScreen: Bool = false,
        options: [PollOption] = [],
        candidateNames: [String] = []
    ) {
        self.isVoteDetailScreen = isVoteDetailScreen
        self.options = options
        self.candidateNames = candidateNames
    }

    public static let empty = PollParseResult()

    /// Names under affirmative options only — the set U6 hands to `NameMatcher` for
    /// pre-checking.
    public var affirmativeNames: [String] {
        options.filter(\.isAffirmative).flatMap(\.rawNames)
    }
}

public struct PollScreenshotParser: Sendable {

    private let scanner: PollLineScanner

    public init(scanner: PollLineScanner = PollLineScanner()) {
        self.scanner = scanner
    }

    /// Parse one screenshot's OCR lines.
    ///
    /// U5 implemented the line rules in `PollLineScanner` (the packet gives the OCR
    /// chrome filtering and nameless-card detection to U5's heuristics); this type
    /// stays as the name U6 wires Vision up to.
    public func parse(lines: [String]) -> PollParseResult {
        scanner.scan(lines: lines)
    }

    /// Multi-screenshot union: parse each dump and dedupe candidates across them.
    public func parse(screenshots: [[String]]) -> PollParseResult {
        var merged = PollParseResult(isVoteDetailScreen: false)
        var seen = Set<String>()
        for lines in screenshots {
            let result = parse(lines: lines)
            merged.isVoteDetailScreen = merged.isVoteDetailScreen || result.isVoteDetailScreen
            merged.options.append(contentsOf: result.options)
            for name in result.candidateNames where seen.insert(name).inserted {
                merged.candidateNames.append(name)
            }
        }
        return merged
    }
}
