//
//  ImportedScreenshot.swift
//  FCTCAttendance
//
//  One poll screenshot prepared for OCR: decoded, reduced to the recognition
//  pixel budget, and paired with a small thumbnail. All decoding runs off the
//  main actor; the original bytes are never stored.
//

import CoreGraphics
import FCTCAttendanceKit
import Foundation
import ImageIO

struct ImportedScreenshot: Identifiable, @unchecked Sendable {
    let id: UUID
    let image: CGImage
    let thumbnail: CGImage

    init(image: CGImage, id: UUID = UUID()) {
        self.id = id
        self.image = image
        thumbnail = (try? Self.resize(image, maximumDimension: 224)) ?? image
    }

    static func prepare(data: Data) async throws -> ImportedScreenshot {
        try await Task.detached(priority: .userInitiated) {
            try prepareSynchronously(data: data)
        }.value
    }

    static func prepare(fileURL: URL) async throws -> ImportedScreenshot {
        try await Task.detached(priority: .userInitiated) {
            let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
            return try prepareSynchronously(data: data)
        }.value
    }

    private static func prepareSynchronously(data: Data) throws -> ImportedScreenshot {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ScreenshotImportError.unreadableImage
        }
        let prepared = try PollScreenshotParser.prepareForRecognition(decoded)
        return ImportedScreenshot(image: prepared)
    }

    private static func resize(
        _ image: CGImage,
        maximumDimension: Int
    ) throws -> CGImage {
        let scale = min(
            Double(maximumDimension) / Double(image.width),
            Double(maximumDimension) / Double(image.height),
            1
        )
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
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let thumbnail = context.makeImage() else {
            throw PollScreenshotParserError.imagePreparationFailed
        }
        return thumbnail
    }
}

enum ScreenshotImportError: LocalizedError {
    case unreadableImage

    var errorDescription: String? {
        "One selected screenshot could not be read."
    }
}
