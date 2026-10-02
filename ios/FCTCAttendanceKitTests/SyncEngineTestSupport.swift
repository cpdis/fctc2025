//
//  SyncEngineTestSupport.swift
//  FCTCAttendanceKitTests
//
//  Container, engine and fetch helpers shared by the sync engine suites.
//

import Foundation
import SwiftData
import Testing

@testable import FCTCAttendanceKit

func makeContainer() throws -> ModelContainer {
    try ModelContainer(
        for: AttendanceSchema.schema,
        configurations: ModelConfiguration(
            "FCTCAttendanceKitTests",
            schema: AttendanceSchema.schema,
            isStoredInMemoryOnly: true
        )
    )
}

func makeEngine(
    container: ModelContainer,
    transport: any HTTPTransport,
    clock: any SyncClock = ImmediateSyncClock()
) -> SyncEngine {
    let api = SheetAPI(config: configuredAPI, transport: transport)
    return SyncEngine(
        modelContainer: container,
        api: api,
        clock: clock,
        automaticallyDrains: false
    )
}

func fetchPending(
    _ container: ModelContainer,
    id: UUID
) throws -> PendingSubmission? {
    let context = ModelContext(container)
    return try context.fetch(FetchDescriptor<PendingSubmission>()).first { $0.id == id }
}

func fetchAllPending(_ container: ModelContainer) throws -> [PendingSubmission] {
    let context = ModelContext(container)
    return try context.fetch(FetchDescriptor<PendingSubmission>())
}

func fetchMembers(_ container: ModelContainer) throws -> [Member] {
    let context = ModelContext(container)
    return try context.fetch(FetchDescriptor<Member>())
}

func fetchRuns(_ container: ModelContainer) throws -> [ScheduledRun] {
    let context = ModelContext(container)
    return try context.fetch(FetchDescriptor<ScheduledRun>())
}
