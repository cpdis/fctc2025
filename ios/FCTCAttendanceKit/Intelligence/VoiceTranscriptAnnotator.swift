//
//  VoiceTranscriptAnnotator.swift
//  FCTCAttendanceKit
//
//  U7 — presentation metadata for the live transcript. It reuses U5's scanner and
//  spans, then marks only tokens that contributed as names or numeric values.
//

import Foundation

public enum VoiceTranscriptTokenKind: Equatable, Sendable {
    case plain
    case name
    case number
}

public struct VoiceTranscriptToken: Equatable, Sendable, Identifiable {
    public let index: Int
    public let text: String
    public let kind: VoiceTranscriptTokenKind

    public var id: Int { index }
}

public struct VoiceTranscriptAnnotator: Sendable {
    private let parser: VoiceEntryParser

    public init(parser: VoiceEntryParser = VoiceEntryParser()) {
        self.parser = parser
    }

    public func annotate(_ transcript: String) -> [VoiceTranscriptToken] {
        let tokens = VoiceTranscriptScanner.tokenize(transcript)
        guard !tokens.isEmpty else { return [] }

        let entities = parser.parse(transcript: transcript)
        var nameIndices = Set<Int>()
        for name in entities.names + entities.guestNames {
            let parts = NormalizedName(name).tokens
            guard !parts.isEmpty, parts.count <= tokens.count else { continue }
            for start in 0...(tokens.count - parts.count) {
                let candidate = tokens[start..<(start + parts.count)].map(\.core)
                if candidate == parts {
                    nameIndices.formUnion(start..<(start + parts.count))
                }
            }
        }

        var numberIndices = Set<Int>()
        let distance = VoiceTranscriptScanner.findDistance(tokens)
        if let distance {
            markNumericTokens(
                tokens,
                in: distance.start..<distance.end,
                includingZeroWords: false,
                into: &numberIndices
            )
        }
        let skip = distance.map { (start: $0.start, end: $0.end) }
        if let guests = VoiceTranscriptScanner.findGuests(tokens, skipping: skip) {
            markNumericTokens(
                tokens,
                in: guests.start..<guests.end,
                includingZeroWords: true,
                into: &numberIndices
            )
        }

        return tokens.map { token in
            let kind: VoiceTranscriptTokenKind
            if nameIndices.contains(token.index) {
                kind = .name
            } else if numberIndices.contains(token.index) {
                kind = .number
            } else {
                kind = .plain
            }
            return VoiceTranscriptToken(index: token.index, text: token.text, kind: kind)
        }
    }

    private func markNumericTokens(
        _ tokens: [VoiceTranscriptScanner.VoiceToken],
        in range: Range<Int>,
        includingZeroWords: Bool,
        into indices: inout Set<Int>
    ) {
        for index in range where tokens.indices.contains(index) {
            let token = tokens[index]
            let isNumber = token.hasDigits
                || VoiceTranscriptScanner.units[token.core] != nil
                || VoiceTranscriptScanner.tens[token.core] != nil
                || token.core == "point"
                || (includingZeroWords && ["no", "none", "nil"].contains(token.core))
            if isNumber { indices.insert(index) }
        }
    }
}
