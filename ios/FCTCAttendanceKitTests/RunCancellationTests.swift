//
//  RunCancellationTests.swift
//  FCTCAttendanceKitTests
//
//  Run cancelled (docs/plans/2026-11-23-1050-feat-run-cancelled-plan.md, U3).
//  The marker rule comes from the fixture every stack reads; a cancelled run
//  stops every attendance prompt; the engine's cancel never lands late.
//

import Foundation
import SwiftData
import Testing

@testable import FCTCAttendanceKit

@Suite("Run cancelled")
struct RunCancellationTests {

    // MARK: The marker rule (R1, R2)

    @Test("Every fixture Run cell parses to its label and marked flag")
    func fixture() throws {
        let fixture = try JSONDecoder().decode(
            CancellationFixture.self, from: Data(contentsOf: Fixtures.url("run-cancellation.json")))
        #expect(!fixture.cases.isEmpty)
        for sample in fixture.cases {
            let parsed = RunLabel.cancellation(sample.raw)
            #expect(parsed.label == sample.label, "\(sample.raw)")
            #expect(parsed.marked == sample.marked, "\(sample.raw)")
            // The marker never reaches the label, type or event.
            #expect(RunLabel(sample.raw) == RunLabel(sample.label), "\(sample.raw)")
        }
    }

    @Test("A marked run is cancelled only while it has no attendance")
    func cancelledState() {
        let blank = run("Fri, 8-May", "River Loop (cancelled)")
        #expect(blank.isCancelled)
        #expect(!blank.needsAttendance)
        #expect(!run("Fri, 8-May", "River Loop (cancelled)", attendees: ["Dan"]).isCancelled)
        #expect(!run("Fri, 8-May", "River Loop (cancelled)", plusOnes: 1).isCancelled)
        #expect(run("Fri, 8-May", "River Loop").needsAttendance)
        let record = RunRecord(rowIndex: 70, date: "Fri, 8-May", meet: "MSBB", run: "River Loop (cancelled)")
        #expect(record.isCancelled)
        #expect(!record.needsAttendance)
    }

    // MARK: Prompts (R8)

    @Test("Catch-up and the default run skip a cancelled past run")
    func catchUp() {
        let now = day(20)
        let runs = [
            run("Wed, 6-May", "Intervals", at: day(6)),
            run("Fri, 8-May", "River Loop (cancelled)", at: day(8)),
            run("Mon, 11-May", "Intervals", at: day(11), attendees: ["Aaron"]),
        ]
        #expect(CatchUpPlanner.unrecordedPastRuns(among: runs, now: now).map(\.date) == ["Wed, 6-May"])
        #expect(CatchUpPlanner.nextOlderUnrecorded(after: runs[2], among: runs, now: now)?.date == "Wed, 6-May")
        #expect(RunPickerViewModel.defaultRun(from: runs, now: now)?.date == "Wed, 6-May")
    }

    @Test("With every due run recorded or cancelled, the default run is the latest recorded one")
    func defaultRunFallback() {
        let runs = [
            run("Mon, 11-May", "Intervals", at: day(11), attendees: ["Aaron"]),
            run("Fri, 15-May", "N/hood Loop (cancelled)", at: day(15)),
        ]
        #expect(RunPickerViewModel.defaultRun(from: runs, now: day(20))?.date == "Mon, 11-May")
    }

    @Test("N of M recorded leaves a cancelled run out of both numbers")
    func recordingProgress() {
        let runs = [
            run("Wed, 6-May", "Intervals", at: day(6), attendees: ["Aaron"]),
            run("Fri, 8-May", "River Loop (cancelled)", at: day(8)),
            run("Mon, 11-May", "Intervals", at: day(11)),
        ]
        let progress = CatchUpPlanner.recordingProgress(of: runs)
        #expect(progress.recorded == 1)
        #expect(progress.scheduled == 2)
    }

    @Test("Home's today card reads cancelled; a marked run with a runner reads recorded")
    @MainActor
    func todayStatus() {
        #expect(HomeViewModel.status(of: run("Fri, 8-May", "River Loop (cancelled)"), submissions: []) == .cancelled)
        let ran = run("Fri, 8-May", "River Loop (cancelled)", attendees: ["Dan"])
        #expect(HomeViewModel.status(of: ran, submissions: []) == .recorded(runners: 1))
    }

    @Test("Home's This Week count and today card skip a cancelled run")
    @MainActor
    func homeWeek() {
        let calendar = perthCalendar
        let home = HomeViewModel(engine: ViewModelSyncClient())
        // Mon 18 May: a cancelled run today, and two club runs later this week.
        let runs = [
            run("Mon, 18-May", "Cruise (cancelled)", at: day(18)),
            run("Mon, 18-May", "Cruise", at: day(18), row: 2),
            run("Wed, 20-May", "Intervals", at: day(20)),
            run("Fri, 22-May", "Soft Sand", at: day(22)),
        ]
        home.update(runs: runs, submissions: [], now: day(18, hour: 9), calendar: calendar)
        #expect(home.thisWeekCount == 3)
        #expect(home.todayRun?.run == "Cruise", "A run that needs attendance wins today's card")
        #expect(home.todayStatus == .open)
        home.update(runs: Array(runs.prefix(1)), submissions: [], now: day(18, hour: 9), calendar: calendar)
        #expect(home.todayStatus == .cancelled)
    }

    // MARK: Club days (R11)

    @Test("A cancelled blank row changes no club day, streak or best")
    func clubDays() {
        let plain = [
            run("Wed, 6-May", "Intervals", attendees: ["Aaron"]),
            run("Fri, 8-May", "River Loop"),
            run("Mon, 11-May", "Intervals", attendees: ["Aaron"]),
        ]
        var marked = plain
        marked[1].run = "River Loop (cancelled)"
        let before = ClubDays(runs: plain.compactMap { ClubRun($0) })
        let after = ClubDays(runs: marked.compactMap { ClubRun($0) })
        #expect(after == before)
        #expect(after.record(for: "Aaron").current == 2)
    }

    // MARK: Capability (KTD5)

    @Test("A server that does not advertise runCancellation hides the action")
    func capability() throws {
        let fields = #""apiVersion":2,"sharedGuests":true,"stableRunIdentity":true,"guestHistory":true,"guestPromotion":true,"operationReceipts":true"#
        let versionSix = try JSONDecoder().decode(GuestCapabilities.self, from: Data("{\(fields)}".utf8))
        #expect(!versionSix.canCancelRuns)
        let current = try JSONDecoder().decode(GuestCapabilities.self, from: Data("{\(fields),\"runCancellation\":true}".utf8))
        #expect(current.canCancelRuns)
    }

    // MARK: Availability on Review & Confirm (R3)

    @Test("Run cancelled is offered only for a blank shared run with nothing on its way")
    @MainActor
    func availability() {
        let blank = sharedRun("Fri, 8-May", "River Loop")
        let model = ChecklistViewModel(run: blank, roster: ["Col", "Dan"], engine: ViewModelSyncClient())
        #expect(model.canCancelRun(serverSupports: true, submissions: []))
        #expect(!model.canCancelRun(serverSupports: false, submissions: []))
        #expect(!model.canCancelRun(serverSupports: true, submissions: [queuedSave(for: blank)]))

        model.toggleMember("Col")
        #expect(!model.canCancelRun(serverSupports: true, submissions: []), "Ticks in the draft mean the run happened")

        let ran = ChecklistViewModel(run: sharedRun("Fri, 8-May", "River Loop", attendees: ["Dan"]),
                                     roster: ["Col", "Dan"], engine: ViewModelSyncClient())
        #expect(!ran.canCancelRun(serverSupports: true, submissions: []))
        let cancelled = ChecklistViewModel(run: sharedRun("Fri, 8-May", "River Loop (cancelled)"),
                                           roster: ["Col"], engine: ViewModelSyncClient())
        #expect(!cancelled.canCancelRun(serverSupports: true, submissions: []))
        #expect(cancelled.run.isCancelled)
        let legacy = ChecklistViewModel(run: run("Fri, 8-May", "River Loop"), roster: ["Col"], engine: ViewModelSyncClient())
        #expect(!legacy.canCancelRun(serverSupports: true, submissions: []), "A legacy run has no stable identity")
    }

    // MARK: The engine operation (KTD7, R7)

    @Test("Cancel sends the run's identity and adopts the refreshed season")
    func engineCancel() async throws {
        let setup = try await cancellationEngine()
        var saved = setup.state
        saved.runs[0].run = "Soft Sand (cancelled)"
        await setup.transport.append(.response(completedResponse()))
        await setup.transport.append(.response(try stateData(saved)))

        let state = try await setup.engine.setRunCancelled(setup.run, cancelled: true)

        #expect(state.runs.first { $0.identity == setup.run.runIdentity }?.isCancelled == true)
        let requests = try await setup.transport.requests.map { try JSONDecoder().decode(GuestJSON.self, from: $0) }
        let cancel = try #require(requests.first { $0["action"]?.string == "setRunCancelled" })
        #expect(cancel["runId"]?.string == setup.run.runIdentity?.runId)
        #expect(cancel["seasonSheetId"]?.int == setup.run.runIdentity?.seasonSheetId)
        #expect(cancel["spreadsheetId"]?.string == setup.run.runIdentity?.spreadsheetId)
        #expect(cancel["expectedRun"]?.string == "Soft Sand")
        #expect(cancel["expectedDate"]?.string == setup.run.date)
        #expect(cancel["cancelled"] == .bool(true))
        #expect(try liveGuestOperations(setup.container).isEmpty)
    }

    @Test("A cancel that fails is closed, throws, and never lands later")
    func engineFailures() async throws {
        let refusals: [StubTransport.Step] = [
            .failure(.notSent),
            .response(json(#"{"ok":false,"error":"busy","message":"Another change is being saved."}"#)),
            .response(try conflictResponse("run_has_attendance")),
            .response(try conflictResponse("pending_verification", operationId: "ffffffff-0000-4000-8000-000000000000")),
        ]
        for refusal in refusals {
            let setup = try await cancellationEngine()
            await setup.transport.append(refusal)
            await #expect(throws: (any Error).self) { _ = try await setup.engine.setRunCancelled(setup.run, cancelled: true) }
            #expect(try liveGuestOperations(setup.container).isEmpty, "\(refusal)")

            // A later sync, for example after recording runners, sends no cancel.
            let sent = await setup.transport.requestCount
            await setup.engine.drain()
            let later = try await setup.transport.requests.dropFirst(sent).map { try JSONDecoder().decode(GuestJSON.self, from: $0) }
            #expect(!later.contains { $0["action"]?.string == "setRunCancelled" }, "\(refusal)")
        }
    }

    @Test("Restore sends cancelled: false and adopts the plain run")
    func engineRestore() async throws {
        let setup = try await cancellationEngine(label: "Soft Sand (cancelled)")
        #expect(setup.run.isCancelled)
        await setup.transport.append(.response(completedResponse()))
        var restored = setup.state
        restored.runs[0].run = "Soft Sand"
        await setup.transport.append(.response(try stateData(restored)))

        let state = try await setup.engine.setRunCancelled(setup.run, cancelled: false)

        let run = try #require(state.runs.first { $0.identity == setup.run.runIdentity })
        #expect(!run.isCancelled)
        #expect(run.needsAttendance)
        let requests = try await setup.transport.requests.map { try JSONDecoder().decode(GuestJSON.self, from: $0) }
        let restore = try #require(requests.first { $0["action"]?.string == "setRunCancelled" })
        #expect(restore["cancelled"] == .bool(false))
        #expect(restore["expectedRun"]?.string == "Soft Sand (cancelled)")
    }

    @Test("A cancel that lands is not reported as failed when the re-read fails")
    func engineCompletedButOffline() async throws {
        let setup = try await cancellationEngine()
        await setup.transport.append(.response(completedResponse()))
        // No getState answer follows: every re-read attempt fails.

        let state = try await setup.engine.setRunCancelled(setup.run, cancelled: true)

        let run = try #require(state.runs.first { $0.identity == setup.run.runIdentity })
        #expect(run.run == "Soft Sand (cancelled)")
        #expect(run.isCancelled)
        #expect(try liveGuestOperations(setup.container).isEmpty)
    }

    @Test("A refused cancel keeps its reason; one never sent says so")
    func engineFailureMessages() async throws {
        let cases: [(StubTransport.Step, RunCancellationError)] = [
            (.failure(.notSent), .notSent),
            (.response(json(#"{"ok":false,"error":"busy","message":"Another change is being saved."}"#)), .refused(UserFacingError.busy)),
        ]
        for (step, expected) in cases {
            let setup = try await cancellationEngine()
            await setup.transport.append(step)
            await #expect(throws: expected) { _ = try await setup.engine.setRunCancelled(setup.run, cancelled: true) }
        }
    }

    @Test("A cancel made while a drain is running is closed and never sent")
    func engineDuringDrain() async throws {
        var state = try JSONDecoder().decode(SheetState.self, from: guestStateResponse())
        state.capabilities?.runCancellation = true
        state.runs[0].attendees = []; state.runs[0].plusOnes = 0
        state.runs[0].namedGuestIds = []; state.runs[0].unnamedGuests = 0
        let container = try guestContainer()
        let transport = GatedTransport([try stateData(state)])
        let engine = guestEngine(container, transport)
        _ = try await engine.refreshState()
        let run = RunSnapshot(record: state.runs[0], state: state, endpointIdentity: configuredAPI.endpoint?.absoluteString)
        let draft = AttendanceDraft(rowIndex: run.rowIndex, expectedDate: run.date, expectedRun: run.run,
            checks: ["Col": .manual], actualKm: 7.2, baseRevision: state.sheetRevision,
            runIdentity: run.runIdentity, endpointIdentity: run.endpointIdentity, unnamedGuests: 0)
        _ = try await engine.enqueue(draft: draft, mode: .merge, deviceName: nil)

        // The save's request is held, so this drain is still running.
        await transport.holdNextRequest()
        let draining = Task { await engine.drain() }
        try await transport.waitUntilHolding()

        await #expect(throws: RunCancellationError.notSent) { _ = try await engine.setRunCancelled(run, cancelled: true) }
        await transport.release()
        await draining.value

        let requests = try await transport.requests.map { try JSONDecoder().decode(GuestJSON.self, from: $0) }
        #expect(!requests.contains { $0["action"]?.string == "setRunCancelled" })
        #expect(try liveGuestOperations(container).isEmpty)
    }

    @Test("A reminder saved before a cancel still opens the run")
    func reminderRoute() {
        let cancelled = run("Fri, 8-May", "River Loop (cancelled)")
        #expect(cancelled.matches(rowIndex: 70, date: "Fri, 8-May", run: "River Loop"))
        #expect(cancelled.matches(rowIndex: 70, date: "Fri, 8-May", run: "River Loop (cancelled)"))
        #expect(!cancelled.matches(rowIndex: 70, date: "Fri, 8-May", run: "Cruise"))
        #expect(!cancelled.matches(rowIndex: 71, date: "Fri, 8-May", run: "River Loop"))
    }

    @Test("A refused cancel hands back the runners the server saw")
    @MainActor
    func refusedShowsRunners() async throws {
        let setup = try await cancellationEngine()
        var seen = setup.state
        seen.runs[0].attendees = ["Col", "Toby"]
        await setup.transport.append(.response(try conflictResponse("run_has_attendance", state: seen)))
        let model = ChecklistViewModel(run: setup.run, roster: ["Col", "Toby"], engine: setup.engine)

        await #expect(throws: (any Error).self) { try await model.setCancelled(true) }

        #expect(model.run.attendees == ["Col", "Toby"])
        #expect(model.errorMessage?.isEmpty == false)
        #expect(!model.isChangingCancellation)
    }

    @Test("A cancel whose delivery is unknown waits for its receipt")
    func engineUnknownDelivery() async throws {
        let setup = try await cancellationEngine()
        await setup.transport.append(.failure(.ambiguousTimeout))
        await #expect(throws: (any Error).self) { _ = try await setup.engine.setRunCancelled(setup.run, cancelled: true) }
        let rows = try ModelContext(setup.container).fetch(FetchDescriptor<PendingGuestOperation>())
        #expect(rows.map(\.phase) == [.checking])
    }
}

// MARK: - Helpers

private struct CancellationFixture: Decodable {
    struct Case: Decodable {
        let raw: String
        let label: String
        let marked: Bool
    }
    let cases: [Case]
}

private let perthCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Australia/Perth")!
    return calendar
}()

/// Midnight (or `hour`) on a day in May 2026, Perth.
private func day(_ day: Int, hour: Int = 0) -> Date {
    perthCalendar.date(from: DateComponents(year: 2026, month: 5, day: day, hour: hour))!
}

private func run(
    _ date: String, _ label: String, at scheduledAt: Date? = nil,
    attendees: [String] = [], plusOnes: Int = 0, row: Int = 70
) -> RunSnapshot {
    RunSnapshot(rowIndex: row, date: date, scheduledAt: scheduledAt, meet: "MSBB", run: label,
                attendees: attendees, plusOnes: plusOnes, seasonYear: 2026)
}

private func sharedRun(_ date: String, _ label: String, attendees: [String] = []) -> RunSnapshot {
    RunSnapshot(rowIndex: 70, date: date, scheduledAt: day(8), meet: "MSBB", run: label, attendees: attendees,
                runIdentity: RunIdentity(spreadsheetId: "workbook", seasonSheetId: 26, runId: "00000070-2222-4222-8222-222222222222"),
                endpointIdentity: configuredAPI.endpoint?.absoluteString, unnamedGuests: 0, seasonYear: 2026)
}

private func queuedSave(for run: RunSnapshot) -> PendingSubmissionSnapshot {
    PendingSubmissionSnapshot(id: UUID(), rowIndex: run.rowIndex, expectedDate: run.date, expectedRun: run.run,
        attendees: ["Col"], plusOnes: 0, actualKm: nil, mode: .merge, status: .queued, createdAt: .now,
        runIdentity: run.runIdentity, endpointIdentity: run.endpointIdentity)
}

private struct CancellationSetup {
    let engine: SyncEngine
    let transport: StubTransport
    let container: ModelContainer
    let state: SheetState
    let run: RunSnapshot
}

/// The contract's shared season with its first run blank and cancellation advertised.
private func cancellationEngine(label: String = "Soft Sand") async throws -> CancellationSetup {
    var state = try JSONDecoder().decode(SheetState.self, from: guestStateResponse())
    state.capabilities?.runCancellation = true
    state.runs[0].run = label
    state.runs[0].attendees = []
    state.runs[0].plusOnes = 0
    state.runs[0].namedGuestIds = []
    state.runs[0].unnamedGuests = 0
    let container = try guestContainer()
    let transport = StubTransport([.response(try stateData(state))])
    let engine = guestEngine(container, transport)
    _ = try await engine.refreshState()
    let run = RunSnapshot(record: state.runs[0], state: state, endpointIdentity: configuredAPI.endpoint?.absoluteString)
    return CancellationSetup(engine: engine, transport: transport, container: container, state: state, run: run)
}

private func completedResponse() -> Data {
    json(#"{"ok":true,"status":"completed","written":1,"sheetRevision":"after-cancel"}"#)
}

private func conflictResponse(_ reason: String, operationId: String? = nil, state: SheetState? = nil) throws -> Data {
    let conflict = SharedGuestConflict(reason: reason, message: "Refused: \(reason).", state: state, operationId: operationId)
    return try JSONEncoder().encode(GuestJSON.object(["ok": .bool(true), "conflict": try .value(conflict)]))
}

/// Guest operations a later drain could still send.
private func liveGuestOperations(_ container: ModelContainer) throws -> [PendingGuestOperation] {
    try ModelContext(container).fetch(FetchDescriptor<PendingGuestOperation>())
        .filter { $0.phase != .completed && $0.phase != .superseded }
}

/// A transport that can hold one request, so a test can act while a drain is mid-send.
private actor GatedTransport: HTTPTransport {
    private var responses: [Data]
    private(set) var requests: [Data] = []
    private var holdNext = false
    private var held: CheckedContinuation<Void, Never>?

    init(_ responses: [Data]) { self.responses = responses }

    func holdNextRequest() { holdNext = true }

    func release() {
        held?.resume()
        held = nil
    }

    func waitUntilHolding() async throws {
        for _ in 0..<10_000 where held == nil { await Task.yield() }
        try #require(held != nil, "The drain never sent a request")
    }

    func post(_ body: Data) async throws -> Data {
        requests.append(body)
        if holdNext {
            holdNext = false
            await withCheckedContinuation { held = $0 }
        }
        guard !responses.isEmpty else { throw StubTransportFailure.offline }
        return responses.removeFirst()
    }
}
