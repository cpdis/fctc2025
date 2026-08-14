//
//  VoiceEntryParser.swift
//  FCTCAttendanceKit
//
//  STUB (U1) — the real transcript parsing lands in U7.
//
//  Pure text in, entities out: `SFSpeechRecognizer` stays in the view layer so this
//  is fixture-testable (`fixtures/attendance/voice-*.transcript.txt` +
//  `*.expected.json`). Cases the fixtures cover:
//   • "plus two guests" / "no guests"                → plusOnes
//   • "eight point seven k" / "ten point four two km" → distanceKm
//   • conjunction-heavy phrasing ("X, Y and Z came, and also W turned up")
//   • long-form names the roster stores short ("Colin" → `Col`)
//   • first-name-only collisions (`Alex`, `Dan`, `Laura`) → ambiguous, never guessed
//

import Foundation

public struct VoiceEntryParser: Sendable {

    public init() {}

    /// Parse a transcript into entities.
    ///
    /// TODO(U7): tokenize, strip stop-phrases ("came", "said they", "turned up",
    /// "plus", "and"), read spelled-out numbers, extract distance and guest count,
    /// leave the rest as candidate names for `NameMatcher`.
    public func parse(transcript: String) -> ExtractedEntities {
        .empty
    }
}

/// Adapts the parser to the shared `NameExtractor` seam so voice and OCR can share
/// downstream code (and so U5's extractors can be swapped in behind it).
public struct VoiceEntryExtractor: NameExtractor {

    private let parser: VoiceEntryParser

    public init(parser: VoiceEntryParser = VoiceEntryParser()) {
        self.parser = parser
    }

    public var isAvailable: Bool {
        get async { true }
    }

    public func extract(from text: String) async throws -> ExtractedEntities {
        parser.parse(transcript: text)
    }
}
