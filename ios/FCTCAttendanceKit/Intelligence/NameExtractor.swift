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

/// The seam both smart modalities are written against.
public protocol NameExtractor: Sendable {
    /// True when this extractor can run right now (model downloaded, feature on…).
    var isAvailable: Bool { get async }

    /// Pull entities out of free text. Throwing is reserved for genuine failures;
    /// "found nothing" is `.empty`.
    func extract(from text: String) async throws -> ExtractedEntities
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
