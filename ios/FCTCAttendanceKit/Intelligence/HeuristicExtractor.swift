//
//  HeuristicExtractor.swift
//  FCTCAttendanceKit
//
//  U5 — the deterministic `NameExtractor`. Always available, never asks permission,
//  never phones home, identical output for identical input. It is both the fallback
//  for `ModelExtractor` and the reference the fixtures are written against.
//
//  It owns no parsing rules of its own: voice goes to `VoiceTranscriptScanner`, poll
//  screenshots to `PollLineScanner`. This type is the adapter that picks one and
//  packages the result (including the nameless-poll-card warning).
//

import Foundation

public struct HeuristicExtractor: NameExtractor {

    private let voice: VoiceTranscriptScanner
    private let poll: PollLineScanner

    public init(
        voice: VoiceTranscriptScanner = VoiceTranscriptScanner(),
        poll: PollLineScanner = PollLineScanner()
    ) {
        self.voice = voice
        self.poll = poll
    }

    /// Heuristics need no model download and no entitlement.
    public var isAvailable: Bool {
        get async { true }
    }

    public func extract(from text: String) async throws -> ExtractedEntities {
        extract(text: text, context: .voice).entities
    }

    public func extract(
        from text: String,
        context: ExtractionContext
    ) async throws -> ExtractionResult {
        extract(text: text, context: context)
    }

    /// Synchronous core — the parsers are pure, so callers that are not already in an
    /// async context (and the tests) do not need to pretend otherwise.
    public func extract(text: String, context: ExtractionContext = .voice) -> ExtractionResult {
        switch context.mode {
        case .voice:
            let entities = voice.scan(transcript: text)
            return ExtractionResult(
                entities: entities,
                warnings: entities.isEmpty ? [.nothingFound] : [],
                usedModel: false
            )

        case .pollScreenshot:
            let lines = context.lines.isEmpty ? Self.split(text) : context.lines
            let parsed = poll.scan(lines: lines)
            // Poll "yes" ≠ attended, but only affirmative options are worth proposing.
            let entities = ExtractedEntities(names: parsed.affirmativeNames)
            var warnings: [ExtractionWarning] = []
            if !parsed.isVoteDetailScreen, !parsed.options.isEmpty {
                warnings.append(.namelessPollCard)
            }
            if entities.isEmpty && warnings.isEmpty {
                warnings.append(.nothingFound)
            }
            return ExtractionResult(
                entities: entities,
                warnings: warnings,
                usedModel: false,
                poll: parsed
            )
        }
    }

    /// Parse an OCR line dump given as one blob of text.
    public func extract(lines: [String]) -> ExtractionResult {
        extract(text: "", context: .pollScreenshot(lines: lines))
    }

    static func split(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isNewline }).map(String.init)
    }
}
