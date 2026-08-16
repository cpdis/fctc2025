//
//  SharedScreenshotInbox.swift
//  FCTCAttendanceKit
//
//  File-only seam between the share extension and the main app.
//

import Foundation

public enum AppGroupConstants {
    public static let identifier = "group.com.cpdis.fctc-attendance"
    public static let inboxDirectory = "ScreenshotInbox"
}

public enum SharedScreenshotLimits {
    public static let maximumImageCount = 12
    public static let maximumInputBytes = 32 * 1_024 * 1_024
    public static let maximumSourcePixels = 48_000_000
    public static let targetPixels = 4_000_000
    public static let maximumStoredImageBytes = 16 * 1_024 * 1_024
    public static let maximumInboxBytes = 96 * 1_024 * 1_024
    public static let maximumAge: TimeInterval = 24 * 60 * 60
}

public struct SharedScreenshotInbox: @unchecked Sendable {
    private let containerURL: URL?
    private let fileManager: FileManager

    public init(
        containerURL: URL? = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppGroupConstants.identifier
        ),
        fileManager: FileManager = .default
    ) {
        self.containerURL = containerURL
        self.fileManager = fileManager
    }

    public func inboxURL() throws -> URL {
        guard let containerURL else { throw SharedScreenshotInboxError.unavailableContainer }
        let inbox = containerURL.appending(path: AppGroupConstants.inboxDirectory, directoryHint: .isDirectory)
        try fileManager.createDirectory(
            at: inbox,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        try? fileManager.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: inbox.path
        )
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var protectedInbox = inbox
        try? protectedInbox.setResourceValues(resourceValues)
        purgeExpiredFiles(in: inbox, now: .now)
        return inbox
    }

    public func list() throws -> [URL] {
        let contents = try fileManager.contentsOfDirectory(
            at: inboxURL(),
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        return contents
            .filter { $0.pathExtension.caseInsensitiveCompare("png") == .orderedSame }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .prefix(SharedScreenshotLimits.maximumImageCount)
            .map { $0 }
    }

    public func storedByteCount() throws -> Int {
        try fileManager.contentsOfDirectory(
            at: inboxURL(),
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ).reduce(into: 0) { total, url in
            total += (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
    }

    public func remove(_ urls: [URL]) throws {
        let inbox = try inboxURL().standardizedFileURL
        for url in urls {
            let candidate = url.standardizedFileURL
            guard candidate.deletingLastPathComponent() == inbox else { continue }
            if fileManager.fileExists(atPath: candidate.path) {
                try fileManager.removeItem(at: candidate)
            }
        }
    }

    /// Clear every received file, including a corrupt or unsupported item. A bad
    /// share must not prompt on every foreground activation forever.
    public func clear() throws {
        let inbox = try inboxURL()
        for url in try fileManager.contentsOfDirectory(
            at: inbox,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            try fileManager.removeItem(at: url)
        }
    }

    private func purgeExpiredFiles(in inbox: URL, now: Date) {
        let cutoff = now.addingTimeInterval(-SharedScreenshotLimits.maximumAge)
        let urls = (try? fileManager.contentsOfDirectory(
            at: inbox,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        for url in urls {
            let modified = try? url.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate
            if let modified, modified < cutoff {
                try? fileManager.removeItem(at: url)
            }
        }
    }
}

public enum SharedScreenshotInboxError: LocalizedError, Sendable, Equatable {
    case unavailableContainer

    public var errorDescription: String? {
        "The shared screenshot inbox is not available. Check the App Group signing setup."
    }
}
