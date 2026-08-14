//
//  ShareViewController.swift
//  FCTCAttendanceShare
//
//  Minimal image-only share extension. It writes PNGs to the App Group inbox.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers
import ImageIO

final class ShareViewController: UIViewController {
    private var imageProviders: [NSItemProvider] = []
    private var host: UIHostingController<ShareConfirmationView>?

    override func viewDidLoad() {
        super.viewDidLoad()
        imageProviders = receivedImageProviders()
        render()
    }

    private func render(errorMessage: String? = nil, isImporting: Bool = false) {
        let root = ShareConfirmationView(
            count: imageProviders.count,
            errorMessage: errorMessage,
            isImporting: isImporting,
            onImport: { [weak self] in self?.beginImport() },
            onCancel: { [weak self] in self?.cancel() }
        )
        if let host {
            host.rootView = root
            return
        }
        let host = UIHostingController(rootView: root)
        self.host = host
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
    }

    private func receivedImageProviders() -> [NSItemProvider] {
        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        return items.flatMap { $0.attachments ?? [] }
            .filter { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }
            .prefix(12)
            .map { $0 }
    }

    private func beginImport() {
        let providers = imageProviders
        render(isImporting: true)
        Task {
            let inbox = SharedScreenshotInbox()
            var writtenURLs: [URL] = []
            do {
                let existingCount = try inbox.list().count
                guard existingCount + providers.count <= SharedScreenshotLimits.maximumImageCount else {
                    throw ShareImportError.inboxFull
                }
                let inboxURL = try inbox.inboxURL()
                var storedBytes = try inbox.storedByteCount()
                for provider in providers {
                    let data = try await provider.imageData()
                    let currentInboxBytes = storedBytes
                    let stored = try await Task.detached(priority: .userInitiated) {
                        try Self.prepareAndWrite(
                            data: data,
                            inboxURL: inboxURL,
                            currentInboxBytes: currentInboxBytes
                        )
                    }.value
                    writtenURLs.append(stored.url)
                    storedBytes += stored.byteCount
                }
            } catch {
                try? inbox.remove(writtenURLs)
                render(errorMessage: ShareImportError.message(for: error))
                return
            }
            extensionContext?.completeRequest(returningItems: nil)
        }
    }

    private nonisolated static func prepareAndWrite(
        data: Data,
        inboxURL: URL,
        currentInboxBytes: Int
    ) throws -> (url: URL, byteCount: Int) {
        guard !data.isEmpty,
              data.count <= SharedScreenshotLimits.maximumInputBytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0,
              height > 0
        else { throw ShareImportError.unsupportedImage }

        let (pixelCount, overflow) = width.multipliedReportingOverflow(by: height)
        guard !overflow, pixelCount <= SharedScreenshotLimits.maximumSourcePixels else {
            throw ShareImportError.imageTooLarge
        }
        let scale = min(
            1,
            sqrt(Double(SharedScreenshotLimits.targetPixels) / Double(pixelCount))
        )
        let maximumDimension = max(1, Int(Double(max(width, height)) * scale))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumDimension,
        ]
        guard let prepared = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let png = UIImage(cgImage: prepared).pngData(),
              png.count <= SharedScreenshotLimits.maximumStoredImageBytes,
              currentInboxBytes + png.count <= SharedScreenshotLimits.maximumInboxBytes
        else { throw ShareImportError.imageTooLarge }

        let filename = "\(Date.now.timeIntervalSince1970)-\(UUID().uuidString).png"
        let url = inboxURL.appending(path: filename)
        try png.write(to: url, options: [.atomic, .completeFileProtection])
        return (url, png.count)
    }

    private func cancel() {
        extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
    }

}

private struct ShareConfirmationView: View {
    let count: Int
    let errorMessage: String?
    let isImporting: Bool
    let onImport: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 38, weight: .medium))
                .foregroundStyle(.tint)
            Text("Share with FCTC")
                .font(.title2.bold())
            Text("Import \(count) screenshot\(count == 1 ? "" : "s") into attendance review?")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("Screenshots stay on this device and are removed after import or dismissal.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            if isImporting {
                ProgressView("Preparing screenshots")
            } else {
                Button("Import", action: onImport)
                    .buttonStyle(.borderedProminent)
                    .disabled(count == 0)
            }
            Button("Cancel", role: .cancel, action: onCancel)
                .disabled(isImporting)
        }
        .padding(28)
    }
}

private enum ShareImportError: LocalizedError {
    case inboxFull
    case unsupportedImage
    case imageTooLarge

    static func message(for error: Error) -> String {
        (error as? ShareImportError)?.errorDescription
            ?? "The screenshots could not be prepared. Try again."
    }

    var errorDescription: String? {
        switch self {
        case .inboxFull:
            "Open FCTC Attendance and import the waiting screenshots first."
        case .unsupportedImage:
            "One screenshot could not be read. Choose a different image."
        case .imageTooLarge:
            "One screenshot is too large to import safely."
        }
    }
}

private extension NSItemProvider {
    @MainActor
    func imageData() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
                if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown))
                }
            }
        }
    }
}
