//
//  PollScreenshotParserTests.swift
//  FCTCAttendanceKitTests
//
//  U6 — the full screenshot pipeline without Vision. The fake recognizer replays
//  the fixture line dumps as positioned observations, so these tests cover ordering,
//  extraction, matching and the frozen DraftProposalSet triage seam.
//

import CoreGraphics
import Foundation
import Testing

@testable import FCTCAttendanceKit

@Suite("PollScreenshotParser — full OCR pipeline")
struct PollScreenshotParserTests {

    @Test("Every poll fixture reaches its expected proposal tiers", arguments: Fixtures.ocrFixtures)
    func fixturePipeline(stem: String) async throws {
        let expected = try Fixtures.expected(stem)
        let lines = try Fixtures.lines("\(stem).ocr.txt")
        let recognizer = FixtureTextRecognizer(screenshots: [lines])
        let parser = PollScreenshotParser(recognizer: recognizer)

        let extraction = try await parser.extract(images: [Self.image()])
        let set = DraftProposalSet(
            entities: extraction.entities,
            matcher: Roster.matcher,
            provenance: .ocr
        )

        #expect(Set(set.autoCheckNames) == Set(expected.names))
        #expect(Self.ambiguous(in: set) == Dictionary(
            uniqueKeysWithValues: expected.ambiguous.map { ($0.raw, $0.candidates) }
        ))
        #expect(Set(Self.suggestedRaws(in: set)) == Set(expected.unmatchedRaw))
        #expect(extraction.poll?.isVoteDetailScreen == expected.isVoteDetailScreen)
        #expect(extraction.warnings.contains(.namelessPollCard) == (expected.needsVotesView ?? false))
    }

    @Test("Positioned observations stay in top-to-bottom line order")
    func observationOrderingIsStable() async throws {
        let lines = try Fixtures.lines("poll-2.ocr.txt")
        let recognizer = FixtureTextRecognizer(screenshots: [lines], returnsBottomFirst: true)
        let parser = PollScreenshotParser(recognizer: recognizer)

        let recognized = try await parser.recognizeLines(in: Self.image())

        #expect(recognized == lines)
    }

    @Test("Several screenshots union in image order and dedupe normalized raw names")
    func unionAndDedupe() async throws {
        let recognizer = FixtureTextRecognizer(screenshots: [
            ["Yes ✓ 3 votes", "Aaron", "Col", "Dan"],
            ["Yes ✓ 4 votes", " col ", "Scott", "Aaron", "Kate"],
        ])
        let parser = PollScreenshotParser(recognizer: recognizer)

        let extraction = try await parser.extract(images: [Self.image(), Self.image()])
        let set = DraftProposalSet(
            entities: extraction.entities,
            matcher: Roster.matcher,
            provenance: .ocr
        )

        #expect(set.proposals.map(\.raw) == ["Aaron", "Col", "Dan", "Scott", "Kate"])
        #expect(set.autoCheckNames == ["Aaron", "Col", "Scott", "Kate B"])
        #expect(Self.ambiguous(in: set)["Dan"] == ["Dan", "Dan B"])
    }

    @Test("A nameless poll card reaches the coach warning with no proposals")
    func namelessCard() async throws {
        let lines = try Fixtures.lines("poll-card-nameless.ocr.txt")
        let parser = PollScreenshotParser(
            recognizer: FixtureTextRecognizer(screenshots: [lines])
        )

        let extraction = try await parser.extract(images: [Self.image()])
        let set = DraftProposalSet(
            entities: extraction.entities,
            matcher: Roster.matcher,
            provenance: .ocr
        )

        #expect(extraction.warnings.contains(.namelessPollCard))
        #expect(extraction.poll?.isVoteDetailScreen == false)
        #expect(set.isEmpty)
    }

    @Test("Images above four megapixels are reduced before recognition")
    func largeImagesAreDownscaled() async throws {
        let recognizer = FixtureTextRecognizer(screenshots: [["Yes ✓ 1 vote", "Aaron"]])
        let parser = PollScreenshotParser(recognizer: recognizer)
        let original = Self.image(width: 2_500, height: 2_000)

        _ = try await parser.recognizeLines(in: original)

        let size = try #require(await recognizer.receivedSizes().first)
        #expect(size.width * size.height <= PollScreenshotParser.maximumPixelCount)
        #expect(size.width < original.width)
        #expect(size.height < original.height)
        #expect(original.width == 2_500)
        #expect(original.height == 2_000)
    }

    private static func ambiguous(in set: DraftProposalSet) -> [String: [String]] {
        Dictionary(uniqueKeysWithValues: set.proposals.compactMap { proposal in
            guard case .pick(let candidates) = proposal.resolution else { return nil }
            return (proposal.raw, candidates)
        })
    }

    private static func suggestedRaws(in set: DraftProposalSet) -> [String] {
        set.proposals.compactMap { proposal in
            guard case .suggest = proposal.resolution else { return nil }
            return proposal.raw
        }
    }

    private static func image(width: Int = 8, height: Int = 8) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }
}

private actor FixtureTextRecognizer: TextRecognizer {
    private let screenshots: [[String]]
    private let returnsBottomFirst: Bool
    private var nextIndex = 0
    private var sizes: [(width: Int, height: Int)] = []

    init(screenshots: [[String]], returnsBottomFirst: Bool = true) {
        self.screenshots = screenshots
        self.returnsBottomFirst = returnsBottomFirst
    }

    func recognizeText(in image: CGImage) async throws -> [RecognizedTextLine] {
        sizes.append((image.width, image.height))
        guard screenshots.indices.contains(nextIndex) else { return [] }
        let lines = screenshots[nextIndex]
        nextIndex += 1
        let observations = lines.enumerated().map { index, line in
            RecognizedTextLine(
                text: line,
                boundingBox: CGRect(
                    x: 0,
                    y: 1 - (CGFloat(index + 1) / CGFloat(lines.count + 1)),
                    width: 0.8,
                    height: 0.02
                )
            )
        }
        return returnsBottomFirst ? observations.reversed() : observations
    }

    func receivedSizes() -> [(width: Int, height: Int)] {
        sizes
    }
}
