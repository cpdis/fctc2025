import Foundation
import SwiftData
import Testing
@testable import FCTCAttendanceKit

@Suite("Guest store migration")
struct GuestMigrationTests {
    @Test("The installed on-disk schema retains queued names and ambiguous done evidence")
    func installedStoreUpgrade() async throws {
        // This source store was captured by the previous app schema before any
        // guest changes. Work only on a copy; never mutate the baseline evidence.
        let directory = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = try copyFixture("guests/legacy-v1.store", into: directory)
        let container = try AttendanceSchema.makeContainer(
            ModelConfiguration(schema: AttendanceSchema.schema, url: destination))
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

    /// Build 8's store has `SharedSheetCache` rows without `liveAt`. Build 9 must
    /// open it in place (lightweight migration), keep the rows, and treat them as
    /// unstamped, so a cold launch still finds the live season by year.
    @Test("A build 8 store opens with liveAt and keeps its shared cache rows")
    func build8StoreUpgrade() throws {
        let directory = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = try copyFixture("guests/build8-shared.store", into: directory)
        let container = try AttendanceSchema.makeContainer(
            ModelConfiguration(schema: AttendanceSchema.schema, url: destination))
        let context = ModelContext(container)

        let rows = try context.fetch(FetchDescriptor<SharedSheetCache>())
        let row = try #require(rows.first)
        #expect(rows.count == 1)
        #expect(row.liveAt == nil)
        #expect(row.state?.seasonSheetId == 26)
        #expect(SharedSheetCache.live(in: rows, endpoint: "https://ui-test.invalid/exec")?.cache.key == row.key)
        #expect(try context.fetch(FetchDescriptor<Member>()).count == 4)
        #expect(try context.fetch(FetchDescriptor<ScheduledRun>()).count == 9)
    }

    /// Both captured stores predate `AttendanceSchemaV1`, so neither carries a
    /// version the plan knows. The app opens through the plan, so both must
    /// still upgrade in place, keep their rows, and open again afterwards.
    @Test("Captured stores open through the migration plan", arguments: [
        ("guests/legacy-v1.store", 1),
        ("guests/build8-shared.store", 4),
    ])
    func opensThroughMigrationPlan(fixture: String, members: Int) throws {
        let directory = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = try copyFixture(fixture, into: directory)
        let configuration = ModelConfiguration(
            schema: AttendanceSchema.schema, url: destination, cloudKitDatabase: .none
        )
        let container = try AttendanceSchema.makeContainer(configuration)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Member>()) == members)
        // The second open finds a store the plan now recognises.
        let reopened = try AttendanceSchema.makeContainer(configuration)
        #expect(try ModelContext(reopened).fetch(FetchDescriptor<Member>()).count == members)
    }

    /// A wrong group identifier would quietly open an empty store somewhere else,
    /// stranding the outbox. Runs wherever the test host can see the group.
    @Test(
        "The app store stays in the App Group container",
        .enabled(if: FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppGroupConstants.identifier
        ) != nil)
    )
    func appStoreLivesInAppGroup() throws {
        let configuration = AttendanceSchema.appStoreConfiguration()
        let group = try #require(FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppGroupConstants.identifier
        ))
        #expect(configuration.groupAppContainerIdentifier == AppGroupConstants.identifier)
        #expect(configuration.url.lastPathComponent == "FCTCAttendance.store")
        #expect(configuration.url.resolvingSymlinksInPath().path()
            .hasPrefix(group.resolvingSymlinksInPath().path()))
    }

    private func makeScratchDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("fctc-migration-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Copies a captured store and any `-wal`/`-shm` sidecars, so tests never
    /// mutate the baseline evidence and never open a store without its journal.
    private func copyFixture(_ name: String, into directory: URL) throws -> URL {
        let source = try Fixtures.url(name)
        let destination = directory.appendingPathComponent(source.lastPathComponent)
        try FileManager.default.copyItem(at: source, to: destination)
        for suffix in ["-wal", "-shm"] where FileManager.default.fileExists(atPath: source.path + suffix) {
            try FileManager.default.copyItem(atPath: source.path + suffix, toPath: destination.path + suffix)
        }
        return destination
    }
}
