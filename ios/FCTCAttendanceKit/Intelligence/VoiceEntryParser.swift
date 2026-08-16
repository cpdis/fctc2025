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

    private let scanner: VoiceTranscriptScanner

    public init(scanner: VoiceTranscriptScanner = VoiceTranscriptScanner()) {
        self.scanner = scanner
    }

    /// Parse a transcript into entities.
    ///
    /// U5 implemented the transcript rules in `VoiceTranscriptScanner` (the packet
    /// gives stop-phrase stripping, spelled-out numbers and plus-ones parsing to U5's
    /// heuristics); this type stays as the name U7 wires `SFSpeechRecognizer` up to.
    public func parse(transcript: String) -> ExtractedEntities {
        scanner.scan(transcript: transcript)
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
