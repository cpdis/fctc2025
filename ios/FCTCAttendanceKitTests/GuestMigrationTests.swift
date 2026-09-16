import Foundation
import SwiftData
import Testing
@testable import FCTCAttendanceKit

@Suite("Guest store migration", .serialized)
struct GuestMigrationTests {
    @Test("The installed on-disk schema retains queued names and ambiguous done evidence")
    func installedStoreUpgrade() async throws {
        // This source store was captured by the previous app schema before any
        // guest changes. Work only on a copy; never mutate the baseline evidence.
        let source = try Fixtures.url("guests/legacy-v1.store")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("fctc-migration-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("legacy.store")
        try FileManager.default.copyItem(at: source, to: destination)
        for suffix in ["-wal", "-shm"] where FileManager.default.fileExists(atPath: source.path + suffix) {
            try FileManager.default.copyItem(atPath: source.path + suffix, toPath: destination.path + suffix)
        }
        let container = try ModelContainer(for: AttendanceSchema.schema,
            configurations: ModelConfiguration(schema: AttendanceSchema.schema, url: destination))
        let context = ModelContext(container)
        let rows = try context.fetch(FetchDescriptor<PendingSubmission>())
        #expect(rows.count == 2)
        let queued = try #require(rows.first { $0.id.uuidString.lowercased().hasPrefix("aaaaaaaa") })
        let done = try #require(rows.first { $0.id.uuidString.lowercased().hasPrefix("bbbbbbbb") })
        #expect(queued.guestNames == ["Rene"])
        #expect(queued.status == .queued)
        #expect(done.guestNames == ["Rene"])
        #expect(done.status == .done)
        #expect(done.outcome == nil)
        #expect(queued.runIdentity == nil)
        #expect(try context.fetch(FetchDescriptor<Member>()).contains { $0.name == "Col" })
        let transport = StubTransport()
        let engine = SyncEngine(modelContainer: container, api: SheetAPI(config: configuredAPI, transport: transport), automaticallyDrains: false)
        await engine.drain()
        #expect(await transport.requestCount == 0)
        let candidates = try await engine.recoveryCandidates(includeDismissed: true)
        #expect(candidates.count == 2)
        #expect(candidates.contains { $0.evidenceStatus == "legacy_ambiguous" })
        #expect(candidates.allSatisfy { $0.selectedRun == nil && $0.status == .pending })
        try await engine.updateRecoveryCandidate(id: candidates[0].id, guestId: nil, run: nil, status: .dismissed)
        #expect(try await engine.recoveryCandidates(includeDismissed: true).count == 2)
        #expect(try await engine.recoveryCandidates(includeDismissed: false).count == 1)
    }
}
