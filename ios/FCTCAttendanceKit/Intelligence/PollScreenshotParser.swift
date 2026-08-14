//
//  PollScreenshotParser.swift
//  FCTCAttendanceKit
//
//  U6 image-to-proposal orchestration. Vision stays behind TextRecognizer, so the
//  fixture line dumps can test the complete pipeline without a photo library.
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

import CoreGraphics
import Foundation
import Vision

/// One OCR observation before the poll parser converts it to a plain text line.
/// Vision and test fakes use the same normalized image-space coordinates.
public struct RecognizedTextLine: Hashable, Sendable {
    public var text: String
    public var boundingBox: CGRect

    public init(text: String, boundingBox: CGRect) {
        self.text = text
        self.boundingBox = boundingBox
    }
}

/// The only image-recognition dependency in the screenshot pipeline. Tests replay
/// line fixtures here and never need Vision or a photo library.
public protocol TextRecognizer: Sendable {
    func recognizeText(in image: CGImage) async throws -> [RecognizedTextLine]
}

/// On-device production OCR. The synchronous Vision request runs in a detached task,
/// so a sheet presented from a MainActor view never blocks UI work.
public struct VisionTextRecognizer: TextRecognizer {

    public init() {}

    public func recognizeText(in image: CGImage) async throws -> [RecognizedTextLine] {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en"]
            request.usesLanguageCorrection = false

            let handler = VNImageRequestHandler(cgImage: image)
            try handler.perform([request])
            return (request.results ?? []).compactMap { observation in
                guard let text = observation.topCandidates(1).first?.string else { return nil }
                return RecognizedTextLine(text: text, boundingBox: observation.boundingBox)
            }
        }.value
    }
}

public enum PollScreenshotParserError: LocalizedError, Sendable {
    case imagePreparationFailed

    public var errorDescription: String? {
        switch self {
        case .imagePreparationFailed:
            "The screenshot could not be prepared for text recognition."
        }
    }
}

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

    /// Four megapixels preserves screenshot text while bounding Vision's memory use.
    public static let maximumPixelCount = 4_000_000

    private let scanner: PollLineScanner
    private let recognizer: any TextRecognizer
    private let extractor: any NameExtractor

    public init(
        scanner: PollLineScanner = PollLineScanner(),
        recognizer: any TextRecognizer = VisionTextRecognizer(),
        extractor: (any NameExtractor)? = nil
    ) {
        self.scanner = scanner
        self.recognizer = recognizer
        // Keep one scanner contract across direct parsing and extraction. Callers can
        // still inject a different extractor when they need model-backed behavior.
        self.extractor = extractor ?? HeuristicExtractor(poll: scanner)
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
            for name in result.candidateNames {
                let key = NormalizedName(name).core
                guard !key.isEmpty, seen.insert(key).inserted else { continue }
                merged.candidateNames.append(name)
            }
        }
        return merged
    }

    /// Recognize one image after applying the memory bound, then impose a stable
    /// reading order. Vision coordinates start at the lower-left, so larger Y values
    /// are visually higher on the screenshot.
    public func recognizeLines(in image: CGImage) async throws -> [String] {
        let prepared = try Self.prepareForRecognition(image)
        let observations = try await recognizer.recognizeText(in: prepared)
        return observations.enumerated()
            .sorted { lhs, rhs in
                let verticalDistance = lhs.element.boundingBox.midY - rhs.element.boundingBox.midY
                if abs(verticalDistance) > 0.005 { return verticalDistance > 0 }
                let horizontalDistance = lhs.element.boundingBox.minX - rhs.element.boundingBox.minX
                if abs(horizontalDistance) > 0.005 { return horizontalDistance < 0 }
                return lhs.offset < rhs.offset
            }
            .map(\.element.text)
    }

    /// Image-to-entities orchestration used by the import sheet. Screenshots run in
    /// selection order so both proposal and UI order are deterministic.
    public func extract(images: [CGImage]) async throws -> ExtractionResult {
        var screenshots: [[String]] = []
        screenshots.reserveCapacity(images.count)
        for image in images {
            screenshots.append(try await recognizeLines(in: image))
        }
        return try await extract(screenshots: screenshots)
    }

    /// Fixture-friendly half of the pipeline. Each screenshot is extracted on its
    /// own so option groups never bleed across screenshot boundaries, then results
    /// are unioned before DraftProposalSet performs its frozen normalized dedupe.
    public func extract(screenshots: [[String]]) async throws -> ExtractionResult {
        var entities = ExtractedEntities.empty
        var warnings: [ExtractionWarning] = []
        var poll = PollParseResult.empty
        var seenCandidates = Set<String>()

        for lines in screenshots {
            let result = try await extractor.extract(
                from: lines.joined(separator: "\n"),
                context: .pollScreenshot(lines: lines)
            )
            entities.names.append(contentsOf: result.entities.names)
            entities.guestNames.append(contentsOf: result.entities.guestNames)
            if entities.plusOnes == nil { entities.plusOnes = result.entities.plusOnes }
            if entities.distanceKm == nil { entities.distanceKm = result.entities.distanceKm }
            for warning in result.warnings where !warnings.contains(warning) {
                warnings.append(warning)
            }
            guard let parsed = result.poll else { continue }
            poll.isVoteDetailScreen = poll.isVoteDetailScreen || parsed.isVoteDetailScreen
            poll.options.append(contentsOf: parsed.options)
            for name in parsed.candidateNames {
                let key = NormalizedName(name).core
                guard !key.isEmpty, seenCandidates.insert(key).inserted else { continue }
                poll.candidateNames.append(name)
            }
        }

        if !entities.isEmpty {
            warnings.removeAll { $0 == .nothingFound }
        } else if warnings.isEmpty {
            warnings.append(.nothingFound)
        }
        return ExtractionResult(
            entities: entities,
            warnings: warnings,
            usedModel: false,
            poll: poll
        )
    }

    /// Return the original only when it already satisfies the pixel budget. Large
    /// originals remain caller-owned and are never persisted by this pipeline.
    public static func prepareForRecognition(_ image: CGImage) throws -> CGImage {
        let pixelCount = image.width * image.height
        guard pixelCount > maximumPixelCount else { return image }

        let scale = sqrt(Double(maximumPixelCount) / Double(pixelCount))
        let width = max(1, Int((Double(image.width) * scale).rounded(.down)))
        let height = max(1, Int((Double(image.height) * scale).rounded(.down)))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw PollScreenshotParserError.imagePreparationFailed
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let resized = context.makeImage() else {
            throw PollScreenshotParserError.imagePreparationFailed
        }
        return resized
    }
}
