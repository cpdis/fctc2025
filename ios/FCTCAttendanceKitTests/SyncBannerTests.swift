//
//  SyncBannerTests.swift
//  FCTCAttendanceKitTests
//
//  CA-28: one event-to-message mapping, and each screen's use of it.
//

import Foundation
import Testing

@testable import FCTCAttendanceKit

@Suite("Sync banner")
@MainActor
struct SyncBannerTests {
    private static let state = SheetState(sheetRevision: "r1")

    /// Every `SyncEvent` case, with the banner it must produce. A new case
    /// fails to compile in `SyncBanner(event:)` before it can miss this list.
    private static let cases: [(SyncEvent, SyncBanner?)] = [
        (.queued(id: UUID()), nil),
        (.written(id: UUID()), SyncBanner(kind: .success, message: "Attendance synced.")),
        (.conflict(id: UUID(), reason: "stale", message: "server text", state: state),
         SyncBanner(kind: .conflict, message: UserFacingError.conflict)),
        (.parked(id: UUID(), message: UserFacingError.offline),
         SyncBanner(kind: .offline, message: UserFacingError.offline)),
        (.parked(id: UUID(), message: UserFacingError.busy),
         SyncBanner(kind: .parked, message: UserFacingError.busy)),
        (.failed(id: UUID(), message: "Row failed."), SyncBanner(kind: .error, message: "Row failed.")),
        (.authenticationRequired(id: UUID()),
         SyncBanner(kind: .authentication, message: UserFacingError.authentication)),
        (.serviceFailed(message: "Store failed."), SyncBanner(kind: .error, message: "Store failed.")),
        (.rosterRefreshed(state), nil),
        (.syncActivity(isActive: true), nil),
        (.syncActivity(isActive: false), nil),
    ]

    @Test("Every sync event maps to one banner or none")
    func everyEvent() {
        for (event, expected) in Self.cases {
            #expect(SyncBanner(event: event) == expected, "\(event)")
        }
    }

    @Test("Only a success is not a problem")
    func problemKinds() {
        let kinds = Self.cases.compactMap(\.1).map(\.kind)
        #expect(kinds.filter { !SyncBanner(kind: $0, message: "").isProblem } == [.success])
    }

    // The screens deliberately differ on `.written`; these pin each one.

    @Test("Home shows the success banner; Outbox clears; Checklist and Runs keep their error")
    func screensOnWritten() async {
        let client = ViewModelSyncClient()
        let home = HomeViewModel(engine: client)
        let outbox = OutboxViewModel(engine: client)
        let picker = RunPickerViewModel(engine: client)

        await client.emit(.failed(id: UUID(), message: "Row failed."))
        #expect(await waitUntil {
            home.syncBanner?.kind == .error && outbox.errorMessage == "Row failed."
                && picker.errorMessage == "Row failed."
        })
        #expect(outbox.syncBanner == SyncBanner(kind: .error, message: "Row failed."))

        await client.emit(.written(id: UUID()))
        #expect(await waitUntil { home.syncBanner?.kind == .success && outbox.syncBanner == nil })
        #expect(home.syncBanner?.message == "Attendance synced.")
        #expect(outbox.errorMessage == nil)
        // Problem-only screens ignore a success.
        #expect(picker.errorMessage == "Row failed.")
    }

    @Test("Outbox sets the inline error only for a hard failure")
    func outboxParkedKeepsInlineError() async {
        let client = ViewModelSyncClient()
        let outbox = OutboxViewModel(engine: client)

        await client.emit(.parked(id: UUID(), message: UserFacingError.offline))
        #expect(await waitUntil { outbox.syncBanner?.kind == .offline })
        #expect(outbox.errorMessage == nil)
    }

    /// Yields up to 30 times; returns whether the condition became true.
    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async -> Bool {
        for _ in 0..<30 where !condition() { await Task.yield() }
        return condition()
    }
}
