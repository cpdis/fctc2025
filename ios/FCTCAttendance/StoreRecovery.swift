//
//  StoreRecovery.swift
//  FCTCAttendance
//
//  Opens the SwiftData store and, when it cannot open, sets the old files aside
//  instead of crashing. A crash here would loop on every launch with the outbox
//  (the only copy of unsent submissions) stuck on disk. Nothing is ever deleted.
//
//    open(configuration) ── ok ──▶ container
//         │ throws
//         ▼
//    file exists and readable? ── no ──▶ rethrow, touch nothing (locked device)
//         │ yes
//         ▼
//    move -wal, -shm, then the store ──▶ "Set aside <ISO date>/" beside them
//         ▼
//    remember the folder for the notice ──▶ open a fresh store ──▶ container
//
//  Any error that escapes is fatal in `FCTCAttendanceApp.init`.
//

import FCTCAttendanceKit
import Foundation
import OSLog
import SwiftData

enum StoreRecovery {

    private static let logger = Logger(subsystem: "com.cpdis.fctc-attendance", category: "store")

    /// Holds the set-aside folder name until the person dismisses the notice.
    static let noticeKey = "storeRecovery.setAsideFolder"

    /// Returns an open container, setting a broken store aside first if needed.
    /// Throws only when nothing more can be done safely; the caller crashes then.
    static func openContainer(_ configuration: ModelConfiguration) throws -> ModelContainer {
        logLocation(of: configuration)
        do {
            return try AttendanceSchema.makeContainer(configuration)
        } catch {
            logger.fault("Store failed to open: \(String(describing: error), privacy: .public)")
            let store = configuration.url
            // No file means the disk failed, not the data: nothing to set aside.
            // An unreadable file is a locked device, not a broken store; moving a
            // healthy store aside would strand the outbox, so leave it for later.
            guard FileManager.default.fileExists(atPath: store.path), isReadable(store) else {
                throw error
            }
        }
        let folder = try setAside(configuration.url)
        UserDefaults.standard.set(folder.lastPathComponent, forKey: noticeKey)
        logger.notice("Set the store aside in \(folder.path, privacy: .public)")
        return try AttendanceSchema.makeContainer(configuration)
    }

    /// Moves the store and its SQLite sidecars into a timestamped folder beside
    /// them. The sidecars go first: if a later move fails, the old store stays
    /// paired with what is left, and a fresh database never meets an orphaned
    /// `-wal` (SQLite would discard it). Other files in the directory stay put.
    private static func setAside(_ store: URL) throws -> URL {
        let fileManager = FileManager.default
        let stamp = Date.now.formatted(Date.ISO8601FormatStyle(timeSeparator: .omitted))
        let folder = store.deletingLastPathComponent()
            .appending(path: "Set aside \(stamp)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = store.lastPathComponent
        for fileName in [name + "-wal", name + "-shm", name] {
            let source = store.deletingLastPathComponent().appending(path: fileName)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            try fileManager.moveItem(at: source, to: folder.appending(path: fileName))
        }
        return folder
    }

    /// True when the first byte can be read. Data protection makes `open`
    /// fail with EPERM before the first unlock.
    private static func isReadable(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 1)) != nil
    }

    /// Logs where the store lives and, in debug builds, stops if the group
    /// identifier is not one this app is entitled to (no container URL) or the
    /// store resolved outside it. Either would silently open an empty store.
    private static func logLocation(of configuration: ModelConfiguration) {
        let store = configuration.url
        logger.debug("Store at \(store.path, privacy: .public)")
        // UI tests use a temp URL with no group; there is nothing to check.
        guard let identifier = configuration.groupAppContainerIdentifier else { return }
        let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
        assert(
            group.map {
                store.resolvingSymlinksInPath().path.hasPrefix($0.resolvingSymlinksInPath().path)
            } == true,
            "The store is not in the App Group container \(identifier): \(store.path)"
        )
    }
}
