//
//  ModelExtractor.swift
//  FCTCAttendanceKit
//
//  U5 — the Foundation Models (iOS 26) extractor: guided generation turns a messy
//  transcript or OCR dump straight into typed entities, on device, offline, free.
//
//  Everything framework-shaped lives behind `ModelGateway` so the decision logic
//  (available? threw? hallucinated? empty?) is testable with a fake, on any machine,
//  without Apple Intelligence and without the framework linked.
//
//  Three safety rails, because a language model that guesses names would quietly
//  corrupt the sheet:
//   • The instructions forbid inventing names.
//   • GROUNDING: any returned name whose letters do not appear in the source text is
//     dropped and flagged (`.modelHallucinated`).
//   • Every surviving name still goes through `NameMatcher`, which auto-checks
//     nothing ambiguous. The model proposes; the roster disposes.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Why the on-device model cannot run right now.
public enum ModelUnavailableReason: String, Codable, Hashable, Sendable {
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case frameworkMissing
    case unknown
}

public enum ModelAvailability: Hashable, Sendable {
    case available
    case unavailable(reason: ModelUnavailableReason)

    public var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }
}

public enum ModelGatewayError: Error, Hashable, Sendable {
    case frameworkUnavailable
    case modelUnavailable(reason: ModelUnavailableReason)
    case emptyResponse
}

/// The seam. One implementation talks to FoundationModels; the tests use a fake.
public protocol ModelGateway: Sendable {
    var availability: ModelAvailability { get async }
    func extractEntities(
        from text: String,
        context: ExtractionContext
    ) async throws -> ExtractedEntities
}

// MARK: - FoundationModels payload

#if canImport(FoundationModels)

/// The guided-generation schema. Deliberately the same shape as `ExtractedEntities`
/// and as the `*.expected.json` fixtures.
@Generable
struct GeneratedAttendance {

    @Guide(description: "Every person's name that literally appears in the text, copied exactly. Never invent, complete or correct a name.")
    var names: [String]

    @Guide(description: "How many guests or plus-ones the text mentions. Use 0 when the text says there were none. Omit when the text does not mention guests.")
    var plusOnes: Int?

    @Guide(description: "The distance in kilometres the text states, for example 8.7 for 'eight point seven k'. Omit when no distance is stated.")
    var distanceKm: Double?

    @Guide(description: "Names of guests when the text names them, otherwise an empty list. A guest name must not also appear in names.")
    var guestNames: [String]
}

#endif

// MARK: - Real gateway

/// Talks to `SystemLanguageModel` when the framework is present; reports
/// `.frameworkMissing` when it is not (so the kit still builds and tests anywhere).
public struct FoundationModelsGateway: ModelGateway {

    public init() {}

    public var availability: ModelAvailability {
        get async {
            #if canImport(FoundationModels)
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible:
                    return .unavailable(reason: .deviceNotEligible)
                case .appleIntelligenceNotEnabled:
                    return .unavailable(reason: .appleIntelligenceNotEnabled)
                case .modelNotReady:
                    return .unavailable(reason: .modelNotReady)
                @unknown default:
                    return .unavailable(reason: .unknown)
                }
            @unknown default:
                return .unavailable(reason: .unknown)
            }
            #else
            return .unavailable(reason: .frameworkMissing)
            #endif
        }
    }

    public func extractEntities(
        from text: String,
        context: ExtractionContext
    ) async throws -> ExtractedEntities {
        #if canImport(FoundationModels)
        let session = LanguageModelSession {
            Self.instructions(for: context.mode)
        }
        let response = try await session.respond(
            to: Self.prompt(for: text, mode: context.mode),
            generating: GeneratedAttendance.self
        )
        let generated = response.content
        return ExtractedEntities(
            names: generated.names,
            plusOnes: generated.plusOnes,
            distanceKm: generated.distanceKm,
            guestNames: generated.guestNames
        )
        #else
        throw ModelGatewayError.frameworkUnavailable
        #endif
    }

    static func instructions(for mode: ExtractionMode) -> String {
        switch mode {
        case .voice:
            return """
            You extract attendance facts from a short spoken note about a running \
            club session. Extract ONLY names that literally appear in the text. \
            Never guess, never complete a surname, never add anyone who is not \
            named. Leave a field out when the text does not state it. Words like \
            "came", "turned up", "we did" are not names.
            """
        case .pollScreenshot:
            return """
            You extract voter names from the text of a WhatsApp poll screenshot. \
            Extract ONLY names that literally appear in the text, copied exactly. \
            Ignore interface text: option labels such as Yes, No and Maybe, vote \
            counts, percentages, timestamps, the group name, the poll question and \
            "View votes". Never invent or complete a name.
            """
        }
    }

    static func prompt(for text: String, mode: ExtractionMode) -> String {
        switch mode {
        case .voice:
            return "Spoken note:\n\(text)"
        case .pollScreenshot:
            return "Screenshot text lines:\n\(text)"
        }
    }
}

// MARK: - Extractor

/// Primary extractor: model first, heuristics whenever the model cannot be trusted.
public struct ModelExtractor: NameExtractor {

    public let gateway: any ModelGateway
    public let fallback: HeuristicExtractor

    public init(
        gateway: any ModelGateway = FoundationModelsGateway(),
        fallback: HeuristicExtractor = HeuristicExtractor()
    ) {
        self.gateway = gateway
        self.fallback = fallback
    }

    public var isAvailable: Bool {
        get async {
            await gateway.availability.isAvailable
        }
    }

    public func extract(from text: String) async throws -> ExtractedEntities {
        try await extract(from: text, context: .voice).entities
    }

    public func extract(
        from text: String,
        context: ExtractionContext
    ) async throws -> ExtractionResult {
        let heuristic = fallback.extract(text: text, context: context)

        guard await gateway.availability.isAvailable else {
            return heuristic.adding(.modelUnavailable)
        }

        let raw: ExtractedEntities
        do {
            raw = try await gateway.extractEntities(from: text, context: context)
        } catch {
            return heuristic.adding(.modelFailed)
        }

        let source = context.lines.isEmpty ? text : context.lines.joined(separator: "\n")
        let grounded = Self.grounded(raw, in: source)
        let dropped = grounded.names.count != raw.names.count
            || grounded.guestNames.count != raw.guestNames.count

        if grounded.isEmpty {
            var result = heuristic.adding(.modelLowConfidence)
            if dropped { result = result.adding(.modelHallucinated) }
            return result
        }

        // Keep whatever the model did not state but the heuristics did: the scanner is
        // better at "no guests" and at spoken decimals than a paraphrasing model.
        var entities = grounded
        if entities.plusOnes == nil { entities.plusOnes = heuristic.entities.plusOnes }
        if entities.distanceKm == nil { entities.distanceKm = heuristic.entities.distanceKm }

        var result = ExtractionResult(
            entities: entities,
            warnings: heuristic.warnings.filter { $0 == .namelessPollCard },
            usedModel: true,
            poll: heuristic.poll
        )
        if dropped { result = result.adding(.modelHallucinated) }
        return result
    }

    /// Drop anything the model returned that is not actually in the source text.
    static func grounded(_ entities: ExtractedEntities, in source: String) -> ExtractedEntities {
        let haystack = NormalizedName(source).compact
        func isPresent(_ candidate: String) -> Bool {
            let needle = NormalizedName(candidate).compact
            guard !needle.isEmpty else { return false }
            return haystack.contains(needle)
        }
        return ExtractedEntities(
            names: entities.names.filter(isPresent),
            plusOnes: entities.plusOnes,
            distanceKm: entities.distanceKm,
            guestNames: entities.guestNames.filter(isPresent)
        )
    }
}
