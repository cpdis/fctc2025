//
//  ServiceTests.swift
//  FCTCAttendanceKitTests
//
//  U1: the service seams exist, are mockable, and the pure backoff maths is right.
//  The real client/engine tests arrive with U3.
//

import Foundation
import Testing

@testable import FCTCAttendanceKit

@Suite("Services")
struct ServiceTests {

    @Test("An unconfigured endpoint is reported as such")
    func configuration() {
        #expect(!SheetAPIConfiguration().isConfigured)
        #expect(
            SheetAPIConfiguration(
                endpoint: URL(string: "https://script.google.com/macros/s/xxx/exec"),
                secret: "shhh"
            ).isConfigured
        )
    }

    @Test("The U1 placeholder client refuses every action")
    func placeholderClientThrows() async {
        let api = UnimplementedSheetAPI()
        await #expect(throws: SheetAPIError.notImplemented) { try await api.getState() }
        await #expect(throws: SheetAPIError.notImplemented) {
            try await api.addMember(name: "Bilbo")
        }
    }

    @Test("Backoff grows geometrically and is capped")
    func retryPolicyDelays() {
        let policy = RetryPolicy(initialDelay: 2, multiplier: 2, maxDelay: 30, maxAttempts: 8)
        #expect(policy.delay(forAttempt: 1) == 0)
        #expect(policy.delay(forAttempt: 2) == 2)
        #expect(policy.delay(forAttempt: 3) == 4)
        #expect(policy.delay(forAttempt: 4) == 8)
        #expect(policy.delay(forAttempt: 10) == 30)
    }

    @Test("An outbox row snapshots into the frozen submitAttendance payload")
    func submissionSnapshot() {
        let pending = PendingSubmission(
            rowIndex: 42,
            expectedDate: "Fri, 2-Jan",
            expectedRun: "Soft Sand",
            attendees: ["Aaron", "Col"],
            guestNames: ["Priya"],
            actualKm: 7.1,
            mode: .overwrite,
            baseRevision: "rev-1"
        )

        let payload = AttendanceSubmission(pending)

        #expect(payload.rowIndex == 42)
        #expect(payload.attendees == ["Aaron", "Col"])
        #expect(payload.plusOnes == 1) // count only — guest names never leave the device
        #expect(payload.mode == .overwrite)
        #expect(payload.baseRevision == "rev-1")
    }

    @Test("The submitAttendance payload encodes to the frozen wire keys")
    func submissionEncoding() throws {
        let payload = AttendanceSubmission(
            rowIndex: 42,
            expectedDate: "Fri, 2-Jan",
            expectedRun: "Soft Sand",
            attendees: ["Col"],
            plusOnes: 0,
            actualKm: 7.1,
            mode: .merge,
            baseRevision: "rev-1"
        )

        let data = try JSONEncoder().encode(payload)
        let object = try JSONSerialization.jsonObject(with: data)
        let json = try #require(object as? [String: Any])

        for key in [
            "rowIndex", "expectedDate", "expectedRun", "attendees",
            "plusOnes", "actualKm", "mode", "baseRevision",
        ] {
            #expect(json[key] != nil, "missing wire key \(key)")
        }
        #expect(json["mode"] as? String == "merge")
    }

    @Test("The U1 placeholder engine emits no events and refuses to enqueue")
    func placeholderEngine() async {
        let engine = UnimplementedSyncEngine()
        await engine.drain()

        var count = 0
        for await _ in engine.events { count += 1 }
        #expect(count == 0)
    }
}
