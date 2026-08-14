//
//  NameExtractor.swift
//  FCTCAttendanceKit
//
//  STUB (U1) — implementations land in U5.
//
//  One protocol, two implementations:
//   • `ModelExtractor`      — FoundationModels (iOS 26) guided generation, primary.
//   • `HeuristicExtractor`  — deterministic tokenizer, fallback whenever the model is
//                             unavailable (no Apple Intelligence, still downloading,
//                             disabled) or returns low-confidence output.
//  Both feed the same `NameMatcher`: the model proposes, the roster disposes.
//

import Foundation

/// What either extractor pulls out of free text (OCR lines or a voice transcript).
/// Deliberately the same shape as the `*.expected.json` fixtures in
/// `fixtures/attendance/`.
public struct ExtractedEntities: Codable, Hashable, Sendable {
    /// Raw name-ish strings, pre-matching. Order is not significant.
    public var names: [String]
    /// Guest count if stated ("plus two guests"); nil when unstated.
    public var plusOnes: Int?
    /// Distance in km if stated ("eight point seven k"); nil when unstated.
    public var distanceKm: Double?
    /// Guest names when the speaker offered them (resolved Q2).
    public var guestNames: [String]

    public init(
        names: [String] = [],
        plusOnes: Int? = nil,
        distanceKm: Double? = nil,
        guestNames: [String] = []
    ) {
        self.names = names
        self.plusOnes = plusOnes
        self.distanceKm = distanceKm
        self.guestNames = guestNames
    }

    public static let empty = ExtractedEntities()

    public var isEmpty: Bool {
        names.isEmpty && plusOnes == nil && distanceKm == nil && guestNames.isEmpty
    }
}

/// Which modality the text came from. The heuristics are genuinely different: a
/// transcript is one prose sentence, a screenshot is a stack of UI lines.
public enum ExtractionMode: String, Codable, Hashable, Sendable {
    case voice
    case pollScreenshot
}

/// Everything an extractor needs beyond the text itself (U5).
///
/// `lines` exists because OCR arrives as an ordered line dump and joining it into one
/// string then re-splitting is lossy for blank/duplicate lines. Callers that have the
/// lines should pass them; `text` stays authoritative for the voice path.
public struct ExtractionContext: Hashable, Sendable {

    public var mode: ExtractionMode
    public var lines: [String]

    public init(mode: ExtractionMode, lines: [String] = []) {
        self.mode = mode
        self.lines = lines
    }

    public static let voice = ExtractionContext(mode: .voice)
    public static let pollScreenshot = ExtractionContext(mode: .pollScreenshot)

    public static func pollScreenshot(lines: [String]) -> ExtractionContext {
        ExtractionContext(mode: .pollScreenshot, lines: lines)
    }
}

/// Things the UI needs to say out loud after an extraction.
public enum ExtractionWarning: String, Codable, Hashable, Sendable {
    /// A poll CARD screenshot: options and counts, no voter names. Coach the user to
    /// screenshot the "View votes" detail screen instead (resolved Q4).
    case namelessPollCard
    /// The text parsed cleanly but contained nothing to propose.
    case nothingFound
    /// Foundation Models is not usable on this device right now; heuristics ran.
    case modelUnavailable
    /// The model threw; heuristics ran.
    case modelFailed
    /// The model returned nothing useful; heuristics ran.
    case modelLowConfidence
    /// The model invented names that are not in the source text; they were dropped.
    case modelHallucinated
}

/// One extraction, plus everything the caller needs to explain it.
public struct ExtractionResult: Hashable, Sendable {

    public var entities: ExtractedEntities
    public var warnings: [ExtractionWarning]
    /// True when the on-device model produced this (as opposed to the heuristics).
    public var usedModel: Bool
    /// Poll structure when the source was a screenshot; nil for voice.
    public var poll: PollParseResult?

    public init(
        entities: ExtractedEntities = .empty,
        warnings: [ExtractionWarning] = [],
        usedModel: Bool = false,
        poll: PollParseResult? = nil
    ) {
        self.entities = entities
        self.warnings = warnings
        self.usedModel = usedModel
        self.poll = poll
    }

    public static let empty = ExtractionResult()

    public func adding(_ warning: ExtractionWarning) -> ExtractionResult {
        var copy = self
        if !copy.warnings.contains(warning) { copy.warnings.append(warning) }
        return copy
    }
}

/// The seam both smart modalities are written against.
public protocol NameExtractor: Sendable {
    /// True when this extractor can run right now (model downloaded, feature on…).
    var isAvailable: Bool { get async }

    /// Pull entities out of free text. Throwing is reserved for genuine failures;
    /// "found nothing" is `.empty`.
    func extract(from text: String) async throws -> ExtractedEntities

    /// Mode-aware extraction (U5). Defaulted, so U1's conformers keep working.
    func extract(from text: String, context: ExtractionContext) async throws -> ExtractionResult
}

extension NameExtractor {

    public func extract(
        from text: String,
        context: ExtractionContext
    ) async throws -> ExtractionResult {
        let entities = try await extract(from: text)
        return ExtractionResult(
            entities: entities,
            warnings: entities.isEmpty ? [.nothingFound] : []
        )
    }
}

/// Placeholder so callers can be written before U5. Always available, finds nothing.
public struct UnimplementedNameExtractor: NameExtractor {

    public init() {}

    public var isAvailable: Bool {
        get async { true }
    }

    public func extract(from text: String) async throws -> ExtractedEntities {
        .empty
    }
}
