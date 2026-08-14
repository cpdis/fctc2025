//
//  SheetAPI.swift
//  FCTCAttendanceKit
//
//  Typed client for the frozen Apps Script JSON contract. The transport is a seam,
//  so service and outbox tests never touch the network.
//


import Foundation

// MARK: - Wire DTOs

public struct RosterEntry: Codable, Hashable, Sendable {
    public var name: String
    /// A 1-based sheet column coordinate.
    public var colIndex: Int

    public init(name: String, colIndex: Int) {
        self.name = name
        self.colIndex = colIndex
    }
}

public struct RunRecord: Codable, Hashable, Sendable {
    /// A 1-based sheet row coordinate.
    public var rowIndex: Int
    public var date: String
    public var meet: String
    public var run: String
    public var approxKm: Double?
    public var actualKm: Double?
    public var attendees: [String]
    public var plusOnes: Int

    public init(
        rowIndex: Int,
        date: String,
        meet: String,
        run: String,
        approxKm: Double? = nil,
        actualKm: Double? = nil,
        attendees: [String] = [],
        plusOnes: Int = 0
    ) {
        self.rowIndex = rowIndex
        self.date = date
        self.meet = meet
        self.run = run
        self.approxKm = approxKm
        self.actualKm = actualKm
        self.attendees = attendees
        self.plusOnes = plusOnes
    }
}

public struct SheetState: Codable, Hashable, Sendable {
    public var roster: [RosterEntry]
    public var runs: [RunRecord]
    public var seasonYear: Int
    public var sheetRevision: String

    public init(
        roster: [RosterEntry] = [],
        runs: [RunRecord] = [],
        seasonYear: Int = 0,
        sheetRevision: String = ""
    ) {
        self.roster = roster
        self.runs = runs
        self.seasonYear = seasonYear
        self.sheetRevision = sheetRevision
    }
}

/// The `submitAttendance` payload, without the common `secret` and `action` keys.
/// Nil numeric opinions encode as explicit JSON null values.
public struct AttendanceSubmission: Codable, Hashable, Sendable {
    public var rowIndex: Int
    public var expectedDate: String
    public var expectedRun: String
    public var attendees: [String]
    public var plusOnes: Int?
    public var actualKm: Double?
    public var mode: SubmissionMode
    public var baseRevision: String?

    public init(
        rowIndex: Int,
        expectedDate: String,
        expectedRun: String,
        attendees: [String],
        plusOnes: Int?,
        actualKm: Double? = nil,
        mode: SubmissionMode = .merge,
        baseRevision: String? = nil
    ) {
        self.rowIndex = rowIndex
        self.expectedDate = expectedDate
        self.expectedRun = expectedRun
        self.attendees = attendees
        self.plusOnes = plusOnes
        self.actualKm = actualKm
        self.mode = mode
        self.baseRevision = baseRevision
    }

    /// Snapshot a SwiftData row before it crosses an actor boundary.
    public init(_ pending: PendingSubmission) {
        self.init(
            rowIndex: pending.rowIndex,
            expectedDate: pending.expectedDate,
            expectedRun: pending.expectedRun,
            attendees: pending.attendees,
            plusOnes: pending.plusOnes,
            actualKm: pending.actualKm,
            mode: pending.mode,
            baseRevision: pending.baseRevision
        )
    }

    private enum CodingKeys: String, CodingKey {
        case rowIndex, expectedDate, expectedRun, attendees
        case plusOnes, actualKm, mode, baseRevision
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rowIndex, forKey: .rowIndex)
        try container.encode(expectedDate, forKey: .expectedDate)
        try container.encode(expectedRun, forKey: .expectedRun)
        try container.encode(attendees, forKey: .attendees)
        try container.encode(plusOnes, forKey: .plusOnes)
        try container.encode(actualKm, forKey: .actualKm)
        try container.encode(mode, forKey: .mode)
        try container.encode(baseRevision, forKey: .baseRevision)
    }
}

public struct AddRunRequest: Codable, Hashable, Sendable {
    public var date: String
    public var meet: String
    public var run: String
    public var approxKm: Double?

    public init(date: String, meet: String, run: String, approxKm: Double? = nil) {
        self.date = date
        self.meet = meet
        self.run = run
        self.approxKm = approxKm
    }

    private enum CodingKeys: String, CodingKey { case date, meet, run, approxKm }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(date, forKey: .date)
        try container.encode(meet, forKey: .meet)
        try container.encode(run, forKey: .run)
        try container.encode(approxKm, forKey: .approxKm)
    }
}

public struct AddMemberResult: Codable, Hashable, Sendable {
    public var roster: [RosterEntry]
    public var sheetRevision: String
}

public struct AddRunResult: Codable, Hashable, Sendable {
    public var runs: [RunRecord]
    public var sheetRevision: String
}

public struct SheetConflict: Codable, Hashable, Sendable {
    public var reason: String
    public var message: String
    public var state: SheetState
}

public enum SubmissionOutcome: Hashable, Sendable {
    case written(cells: Int, sheetRevision: String)
    case conflict(reason: String, message: String, state: SheetState)
}

// MARK: - Errors and configuration

public enum SheetAPIError: Error, Sendable, Equatable {
    case notConfigured
    case network(String)
    case badSecret(message: String)
    case unknownAction(message: String)
    case duplicateMember(message: String)
    case badPayload(message: String)
    case sheetUnreadable(message: String)
    case busy(message: String)
    case internalError(message: String)
    case server(code: String, message: String)
    case decoding(String)
    case notImplemented

    public var code: String {
        switch self {
        case .notConfigured: "not_configured"
        case .network: "network"
        case .badSecret: "bad_secret"
        case .unknownAction: "unknown_action"
        case .duplicateMember: "duplicate_member"
        case .badPayload: "bad_payload"
        case .sheetUnreadable: "sheet_unreadable"
        case .busy: "busy"
        case .internalError: "internal_error"
        case .server(let code, _): code
        case .decoding: "decoding"
        case .notImplemented: "not_implemented"
        }
    }

    public var isRetryable: Bool {
        switch self {
        case .network, .busy: true
        default: false
        }
    }
}

extension SheetAPIError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notConfigured: "The sheet endpoint and secret are not configured."
        case .network(let message), .decoding(let message): message
        case .badSecret(let message), .unknownAction(let message),
             .duplicateMember(let message), .badPayload(let message),
             .sheetUnreadable(let message), .busy(let message),
             .internalError(let message), .server(_, let message): message
        case .notImplemented: "This service is not implemented."
        }
    }
}

/// Endpoint and shared secret supplied by app settings. No credential is compiled in.
public struct AppConfig: Hashable, Sendable {
    public var endpoint: URL?
    public var secret: String
    public var deviceName: String?

    public var isConfigured: Bool { endpoint != nil && !secret.isEmpty }

    public init(endpoint: URL? = nil, secret: String = "", deviceName: String? = nil) {
        self.endpoint = endpoint
        self.secret = secret
        self.deviceName = deviceName
    }
}

/// Compatibility name used by the U1 scaffold and early U4 work.
public typealias SheetAPIConfiguration = AppConfig

// MARK: - Transport

public protocol HTTPTransport: Sendable {
    func post(_ body: Data) async throws -> Data
}

public enum HTTPTransportError: Error, Sendable, Equatable {
    case invalidResponse
    case statusCode(Int)
}

/// The only type in the kit that knows about URLSession.
public actor URLSessionTransport: HTTPTransport {
    private let endpoint: URL
    private let session: URLSession

    public init(endpoint: URL, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.session = session
    }

    public func post(_ body: Data) async throws -> Data {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HTTPTransportError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw HTTPTransportError.statusCode(httpResponse.statusCode)
        }
        return data
    }
}

// MARK: - Client

public protocol SheetAPIClient: Sendable {
    func getState() async throws -> SheetState
    func submitAttendance(_ submission: AttendanceSubmission) async throws -> SubmissionOutcome
    func addMember(name: String) async throws -> AddMemberResult
    func addRun(_ request: AddRunRequest) async throws -> AddRunResult
}

public actor SheetAPI: SheetAPIClient {
    private let config: AppConfig
    private let transport: (any HTTPTransport)?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(config: AppConfig, transport: (any HTTPTransport)? = nil) {
        self.config = config
        if let transport {
            self.transport = transport
        } else if let endpoint = config.endpoint {
            self.transport = URLSessionTransport(endpoint: endpoint)
        } else {
            self.transport = nil
        }
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    public init(
        configuration: SheetAPIConfiguration,
        transport: (any HTTPTransport)? = nil
    ) {
        self.init(config: configuration, transport: transport)
    }

    public func getState() async throws -> SheetState {
        try await send(
            CommonRequest(secret: config.secret, action: "getState"),
            as: SheetState.self
        )
    }

    public func submitAttendance(
        _ submission: AttendanceSubmission
    ) async throws -> SubmissionOutcome {
        let response = try await send(
            SubmitRequest(secret: config.secret, submission: submission),
            as: SubmitResponse.self
        )
        if let conflict = response.conflict {
            return .conflict(
                reason: conflict.reason,
                message: conflict.message,
                state: conflict.state
            )
        }
        guard let written = response.written, let revision = response.sheetRevision else {
            throw SheetAPIError.decoding("A submit response had no write or conflict result.")
        }
        return .written(cells: written, sheetRevision: revision)
    }

    public func addMember(name: String) async throws -> AddMemberResult {
        try await send(
            AddMemberRequest(secret: config.secret, action: "addMember", name: name),
            as: AddMemberResult.self
        )
    }

    public func addRun(_ request: AddRunRequest) async throws -> AddRunResult {
        try await send(
            AddRunWireRequest(secret: config.secret, request: request),
            as: AddRunResult.self
        )
    }

    /// Compatibility overload for the U1 seam.
    public func addRun(
        date: String,
        meet: String,
        run: String,
        approxKm: Double?
    ) async throws -> AddRunResult {
        try await addRun(AddRunRequest(date: date, meet: meet, run: run, approxKm: approxKm))
    }

    private func send<Request: Encodable, Response: Decodable>(
        _ request: Request,
        as responseType: Response.Type
    ) async throws -> Response {
        guard config.isConfigured, let transport else {
            throw SheetAPIError.notConfigured
        }

        let body: Data
        do {
            body = try encoder.encode(request)
        } catch {
            throw SheetAPIError.decoding("Could not encode the request: \(error)")
        }

        let data: Data
        do {
            data = try await transport.post(body)
        } catch let error as SheetAPIError {
            throw error
        } catch {
            throw SheetAPIError.network(String(describing: error))
        }

        do {
            return try decoder.decode(CheckedResponse<Response>.self, from: data).payload
        } catch let error as SheetAPIError {
            throw error
        } catch {
            throw SheetAPIError.decoding("Could not decode the response body: \(error)")
        }
    }
}

// MARK: - Private envelopes

private struct CheckedResponse<Payload: Decodable>: Decodable {
    let payload: Payload

    private enum CodingKeys: String, CodingKey { case ok, error, message }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(Bool.self, forKey: .ok) else {
            let code = try container.decodeIfPresent(String.self, forKey: .error)
                ?? "unknown_error"
            let message = try container.decodeIfPresent(String.self, forKey: .message)
                ?? "The sheet returned an error without a message."
            throw sheetServerError(code: code, message: message)
        }
        payload = try Payload(from: decoder)
    }
}

private func sheetServerError(code: String, message: String) -> SheetAPIError {
    switch code {
    case "bad_secret": .badSecret(message: message)
    case "unknown_action": .unknownAction(message: message)
    case "duplicate_member": .duplicateMember(message: message)
    case "bad_payload": .badPayload(message: message)
    case "sheet_unreadable": .sheetUnreadable(message: message)
    case "busy": .busy(message: message)
    case "internal_error": .internalError(message: message)
    default: .server(code: code, message: message)
    }
}

private struct SubmitResponse: Decodable {
    let written: Int?
    let sheetRevision: String?
    let conflict: SheetConflict?
}

private struct CommonRequest: Encodable {
    let secret: String
    let action: String
}

private struct AddMemberRequest: Encodable {
    let secret: String
    let action: String
    let name: String
}

private struct SubmitRequest: Encodable {
    let secret: String
    let action = "submitAttendance"
    let rowIndex: Int
    let expectedDate: String
    let expectedRun: String
    let attendees: [String]
    let plusOnes: Int?
    let actualKm: Double?
    let mode: SubmissionMode
    let baseRevision: String?

    init(secret: String, submission: AttendanceSubmission) {
        self.secret = secret
        self.rowIndex = submission.rowIndex
        self.expectedDate = submission.expectedDate
        self.expectedRun = submission.expectedRun
        self.attendees = submission.attendees
        self.plusOnes = submission.plusOnes
        self.actualKm = submission.actualKm
        self.mode = submission.mode
        self.baseRevision = submission.baseRevision
    }

    private enum CodingKeys: String, CodingKey {
        case secret, action, rowIndex, expectedDate, expectedRun, attendees
        case plusOnes, actualKm, mode, baseRevision
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(secret, forKey: .secret)
        try container.encode(action, forKey: .action)
        try container.encode(rowIndex, forKey: .rowIndex)
        try container.encode(expectedDate, forKey: .expectedDate)
        try container.encode(expectedRun, forKey: .expectedRun)
        try container.encode(attendees, forKey: .attendees)
        try container.encode(plusOnes, forKey: .plusOnes)
        try container.encode(actualKm, forKey: .actualKm)
        try container.encode(mode, forKey: .mode)
        try container.encode(baseRevision, forKey: .baseRevision)
    }
}

private struct AddRunWireRequest: Encodable {
    let secret: String
    let action = "addRun"
    let date: String
    let meet: String
    let run: String
    let approxKm: Double?

    init(secret: String, request: AddRunRequest) {
        self.secret = secret
        self.date = request.date
        self.meet = request.meet
        self.run = request.run
        self.approxKm = request.approxKm
    }

    private enum CodingKeys: String, CodingKey {
        case secret, action, date, meet, run, approxKm
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(secret, forKey: .secret)
        try container.encode(action, forKey: .action)
        try container.encode(date, forKey: .date)
        try container.encode(meet, forKey: .meet)
        try container.encode(run, forKey: .run)
        try container.encode(approxKm, forKey: .approxKm)
    }
}

/// Keeps early UI work compilable while it migrates from the U1 placeholder.
public struct UnimplementedSheetAPI: SheetAPIClient {
    public init() {}

    public func getState() async throws -> SheetState { throw SheetAPIError.notImplemented }
    public func submitAttendance(
        _ submission: AttendanceSubmission
    ) async throws -> SubmissionOutcome { throw SheetAPIError.notImplemented }
    public func addMember(name: String) async throws -> AddMemberResult {
        throw SheetAPIError.notImplemented
    }
    public func addRun(_ request: AddRunRequest) async throws -> AddRunResult {
        throw SheetAPIError.notImplemented
    }
}
