//
//  ServiceTests.swift
//  FCTCAttendanceKitTests
//
//  Contract tests for the typed Apps Script client.
//


import Foundation
import Testing

@testable import FCTCAttendanceKit

enum StubTransportFailure: Error, Sendable {
    case offline
    case ambiguousTimeout
}

actor StubTransport: HTTPTransport {
    enum Step: Sendable {
        case response(Data)
        case failure(StubTransportFailure)
    }

    private var steps: [Step]
    private(set) var requests: [Data] = []

    init(_ steps: [Step] = []) {
        self.steps = steps
    }

    func post(_ body: Data) async throws -> Data {
        requests.append(body)
        guard !steps.isEmpty else { throw StubTransportFailure.offline }

        switch steps.removeFirst() {
        case .response(let data):
            return data
        case .failure(let error):
            throw error
        }
    }

    func append(_ step: Step) {
        steps.append(step)
    }

    var requestCount: Int { requests.count }
}

func json(_ value: String) -> Data {
    Data(value.utf8)
}

let configuredAPI = AppConfig(
    endpoint: URL(string: "https://script.google.com/macros/s/test/exec"),
    secret: "shhh",
    deviceName: "Colin's iPhone"
)

let stateResponse = json(
    """
    {
      "ok": true,
      "roster": [
        {"name": "Aaron", "colIndex": 6},
        {"name": "Col", "colIndex": 7}
      ],
      "runs": [{
        "rowIndex": 42,
        "date": "Fri, 2-Jan",
        "meet": "Il Lido",
        "run": "Soft Sand",
        "approxKm": 7.1,
        "actualKm": null,
        "attendees": ["Aaron"],
        "plusOnes": 1
      }],
      "seasonYear": 2026,
      "sheetRevision": "rev-1"
    }
    """
)

/// The same state from a script that serves lifetime totals. `stateResponse` above
/// deliberately omits them, so the rest of the suite keeps proving the app works
/// against a deployment that predates the field.
///
/// Kept as text as well as data so a test can vary one number without restating
/// the whole payload.
let stateResponseWithTotalsText =
    """
    {
      "ok": true,
      "roster": [
        {"name": "Aaron", "colIndex": 6},
        {"name": "Col", "colIndex": 7}
      ],
      "runs": [{
        "rowIndex": 42,
        "date": "Fri, 2-Jan",
        "meet": "Il Lido",
        "run": "Soft Sand",
        "approxKm": 7.1,
        "actualKm": null,
        "attendees": ["Aaron"],
        "plusOnes": 1
      }],
      "seasonYear": 2026,
      "sheetRevision": "rev-1",
      "lifetimeTotals": [
        {"name": "Aaron", "runs": 129},
        {"name": "Col", "runs": 47},
        {"name": "Ghost", "runs": 5}
      ]
    }
    """

let stateResponseWithTotals = json(stateResponseWithTotalsText)

@Suite("Sheet API")
struct ServiceTests {

    @Test("An unconfigured endpoint is reported as such")
    func configuration() async {
        #expect(!AppConfig().isConfigured)
        #expect(configuredAPI.isConfigured)

        let api = SheetAPI(config: AppConfig(), transport: StubTransport())
        await #expect(throws: SheetAPIError.notConfigured) {
            try await api.getState()
        }
    }

    @Test("getState posts the secret and exact action")
    func getState() async throws {
        let transport = StubTransport([.response(stateResponse)])
        let api = SheetAPI(config: configuredAPI, transport: transport)

        let state = try await api.getState()

        #expect(state.seasonYear == 2026)
        #expect(state.sheetRevision == "rev-1")
        #expect(state.roster.last == RosterEntry(name: "Col", colIndex: 7))
        #expect(state.runs.first?.rowIndex == 42)

        let body = try #require(await transport.requests.first)
        let object = try #require(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        #expect(object["secret"] as? String == "shhh")
        #expect(object["action"] as? String == "getState")
        #expect(Set(object.keys) == ["secret", "action"])
    }

    @Test("getState decodes lifetime totals when the script serves them")
    func getStateLifetimeTotals() async throws {
        let transport = StubTransport([.response(stateResponseWithTotals)])
        let api = SheetAPI(config: configuredAPI, transport: transport)

        let state = try await api.getState()

        #expect(state.lifetimeTotals.count == 3)
        #expect(state.lifetimeTotals.first == MemberTotal(name: "Aaron", runs: 129))
        #expect(state.lifetimeTotals.contains(MemberTotal(name: "Col", runs: 47)))
    }

    @Test("getState against a script without the field decodes to no totals")
    func getStateWithoutLifetimeTotals() async throws {
        // The deployed build must keep working against an older script, and a
        // missing key must not be a decode failure that breaks the whole refresh.
        let transport = StubTransport([.response(stateResponse)])
        let api = SheetAPI(config: configuredAPI, transport: transport)

        let state = try await api.getState()

        #expect(state.lifetimeTotals.isEmpty)
        #expect(state.roster.count == 2, "the rest of the payload still decodes")
    }

    @Test("submitAttendance decodes write metadata")
    func submissionSuccess() async throws {
        let transport = StubTransport([
            .response(json("{\"ok\":true,\"written\":39,\"sheetRevision\":\"rev-2\"}")),
        ])
        let api = SheetAPI(config: configuredAPI, transport: transport)

        let outcome = try await api.submitAttendance(.fixture)

        #expect(outcome == .written(cells: 39, sheetRevision: "rev-2"))

        let body = try #require(await transport.requests.first)
        let object = try #require(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        let expectedKeys = Set([
            "secret", "action", "rowIndex", "expectedDate", "expectedRun",
            "attendees", "plusOnes", "actualKm", "mode", "baseRevision",
        ])
        #expect(Set(object.keys) == expectedKeys)
        #expect(object["secret"] as? String == "shhh")
        #expect(object["action"] as? String == "submitAttendance")
        #expect(object["rowIndex"] as? Int == 42)
        #expect(object["expectedDate"] as? String == "Fri, 2-Jan")
        #expect(object["expectedRun"] as? String == "Soft Sand")
        #expect(object["attendees"] as? [String] == ["Col"])
        #expect(object["plusOnes"] as? Int == 1)
        #expect(object["actualKm"] as? Double == 7.1)
        #expect(object["mode"] as? String == "overwrite")
        #expect(object["baseRevision"] as? String == "rev-1")
    }

    @Test("submitAttendance conflict carries its message and fresh state")
    func submissionConflict() async throws {
        let transport = StubTransport([
            .response(json(
                """
                {
                  "ok": true,
                  "conflict": {
                    "reason": "stale_revision",
                    "message": "The sheet changed since this submission was prepared.",
                    "state": {
                      "roster": [], "runs": [], "seasonYear": 2026,
                      "sheetRevision": "rev-fresh"
                    }
                  }
                }
                """
            )),
        ])
        let api = SheetAPI(config: configuredAPI, transport: transport)

        let outcome = try await api.submitAttendance(.fixture)

        #expect(
            outcome == .conflict(
                reason: "stale_revision",
                message: "The sheet changed since this submission was prepared.",
                state: SheetState(seasonYear: 2026, sheetRevision: "rev-fresh")
            )
        )
    }

    @Test("addMember and addRun retain the returned revision")
    func structuralWrites() async throws {
        let transport = StubTransport([
            .response(json(
                """
                {"ok":true,"roster":[{"name":"Bilbo","colIndex":8}],"sheetRevision":"rev-2"}
                """
            )),
            .response(json(
                """
                {"ok":true,"runs":[],"sheetRevision":"rev-3"}
                """
            )),
        ])
        let api = SheetAPI(config: configuredAPI, transport: transport)

        let memberResult = try await api.addMember(name: "Bilbo")
        let runResult = try await api.addRun(
            AddRunRequest(date: "Sat, 3-Jan", meet: "Il Lido", run: "Parkrun", approxKm: 5)
        )

        #expect(memberResult.sheetRevision == "rev-2")
        #expect(memberResult.roster == [RosterEntry(name: "Bilbo", colIndex: 8)])
        #expect(runResult.sheetRevision == "rev-3")

        let requests = await transport.requests
        let memberBody = try #require(
            JSONSerialization.jsonObject(with: requests[0]) as? [String: Any]
        )
        #expect(Set(memberBody.keys) == ["secret", "action", "name"])
        #expect(memberBody["secret"] as? String == "shhh")
        #expect(memberBody["action"] as? String == "addMember")
        #expect(memberBody["name"] as? String == "Bilbo")

        let runBody = try #require(
            JSONSerialization.jsonObject(with: requests[1]) as? [String: Any]
        )
        #expect(Set(runBody.keys) == [
            "secret", "action", "date", "meet", "run", "approxKm",
        ])
        #expect(runBody["secret"] as? String == "shhh")
        #expect(runBody["action"] as? String == "addRun")
        #expect(runBody["date"] as? String == "Sat, 3-Jan")
        #expect(runBody["meet"] as? String == "Il Lido")
        #expect(runBody["run"] as? String == "Parkrun")
        #expect(runBody["approxKm"] as? Double == 5)
    }

    @Test("Every frozen server error code has a typed error")
    func typedErrors() async {
        let cases: [(String, SheetAPIError)] = [
            ("bad_secret", .badSecret(message: "message")),
            ("unknown_action", .unknownAction(message: "message")),
            ("duplicate_member", .duplicateMember(message: "message")),
            ("bad_payload", .badPayload(message: "message")),
            ("sheet_unreadable", .sheetUnreadable(message: "message")),
            ("busy", .busy(message: "message")),
            ("internal_error", .internalError(message: "message")),
        ]

        for (code, expected) in cases {
            let transport = StubTransport([
                .response(json("{\"ok\":false,\"error\":\"\(code)\",\"message\":\"message\"}")),
            ])
            let api = SheetAPI(config: configuredAPI, transport: transport)

            do {
                _ = try await api.getState()
                Issue.record("Expected typed error for \(code)")
            } catch let error as SheetAPIError {
                #expect(error == expected)
            } catch {
                Issue.record("Unexpected error for \(code): \(error)")
            }
        }
    }

    @Test("Transport failures become retryable network errors")
    func transportFailure() async {
        let api = SheetAPI(
            config: configuredAPI,
            transport: StubTransport([.failure(.offline)])
        )

        do {
            _ = try await api.getState()
            Issue.record("Expected a network error")
        } catch let error as SheetAPIError {
            #expect(error.isRetryable)
            #expect(error.code == "network")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Backoff uses the required 2, 4, 8, 16 second schedule")
    func retryPolicyDelays() {
        let policy = RetryPolicy.default
        #expect(policy.maxAttempts == 5)
        #expect(policy.delay(forAttempt: 1) == 0)
        #expect(policy.delay(forAttempt: 2) == 2)
        #expect(policy.delay(forAttempt: 3) == 4)
        #expect(policy.delay(forAttempt: 4) == 8)
        #expect(policy.delay(forAttempt: 5) == 16)
        #expect(policy.delay(forAttempt: 10) == 16)
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
        #expect(payload.plusOnes == 1)
        #expect(payload.mode == .overwrite)
        #expect(payload.baseRevision == "rev-1")
    }

    @Test("The submitAttendance payload encodes frozen keys and explicit null opinions")
    func submissionEncoding() throws {
        let payload = AttendanceSubmission(
            rowIndex: 42,
            expectedDate: "Fri, 2-Jan",
            expectedRun: "Soft Sand",
            attendees: ["Col"],
            plusOnes: nil,
            actualKm: nil,
            mode: .merge,
            baseRevision: "rev-1"
        )

        let data = try JSONEncoder().encode(payload)
        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        let expectedKeys = Set([
            "rowIndex", "expectedDate", "expectedRun", "attendees",
            "plusOnes", "actualKm", "mode", "baseRevision",
        ])
        #expect(Set(object.keys) == expectedKeys)
        #expect(object["plusOnes"] is NSNull)
        #expect(object["actualKm"] is NSNull)
        #expect(object["mode"] as? String == "merge")
    }

    @Test("The transport envelope preserves explicit null opinions")
    func submissionEnvelopeNulls() async throws {
        let transport = StubTransport([
            .response(json("{\"ok\":true,\"written\":0,\"sheetRevision\":\"rev-1\"}")),
        ])
        let api = SheetAPI(config: configuredAPI, transport: transport)
        let submission = AttendanceSubmission(
            rowIndex: 42,
            expectedDate: "Fri, 2-Jan",
            expectedRun: "Soft Sand",
            attendees: [],
            plusOnes: nil,
            actualKm: nil,
            baseRevision: nil
        )

        _ = try await api.submitAttendance(submission)

        let body = try #require(await transport.requests.first)
        let object = try #require(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        #expect(object["plusOnes"] is NSNull)
        #expect(object["actualKm"] is NSNull)
        #expect(object["baseRevision"] is NSNull)
    }
}

extension AttendanceSubmission {
    static let fixture = AttendanceSubmission(
        rowIndex: 42,
        expectedDate: "Fri, 2-Jan",
        expectedRun: "Soft Sand",
        attendees: ["Col"],
        plusOnes: 1,
        actualKm: 7.1,
        mode: .overwrite,
        baseRevision: "rev-1"
    )
}
