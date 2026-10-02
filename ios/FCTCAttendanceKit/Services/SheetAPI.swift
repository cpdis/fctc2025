import Foundation
import os

// MARK: - Errors and configuration

public enum SheetAPIError: Error, Sendable, Equatable {
    case notConfigured
    case network(String)
    /// Completed transport evidence proves that no request was sent.
    case requestNotSent(String)
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
        case .requestNotSent: "request_not_sent"
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
        case .network, .requestNotSent, .busy: true
        default: false
        }
    }
}

extension SheetAPIError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notConfigured: "The sheet endpoint and secret are not configured."
        case .network(let message), .requestNotSent(let message), .decoding(let message): message
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

/// Every textual and reflected form hides the secret, so no log line,
/// string interpolation or debugger dump can leak it.
extension AppConfig: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    private static let redacted = "<redacted>"

    public var description: String {
        "AppConfig(endpoint: \(endpoint?.absoluteString ?? "nil"), secret: \(Self.redacted), "
            + "deviceName: \(deviceName ?? "nil"))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(self, children: [
            "endpoint": endpoint as Any,
            "secret": Self.redacted,
            "deviceName": deviceName as Any,
        ], displayStyle: .struct)
    }
}

// MARK: - Transport

public protocol HTTPTransport: Sendable {
    func post(_ body: Data) async throws -> Data
}

public enum HTTPTransportError: Error, Sendable, Equatable {
    case invalidResponse
    case statusCode(Int)
    case requestNotSent(String)
}

/// The only type in the kit that knows about URLSession.
public actor URLSessionTransport: HTTPTransport {
    private let endpoint: URL
    private let session: URLSession
    private static let logger = Logger(subsystem: "com.cpdis.fctc-attendance", category: "network")

    /// Ephemeral (no cookies or disk cache) with a 30 s request timeout, so a
    /// stalled Apps Script call fails soon instead of after the 60 s default.
    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }

    /// Tests inject a `session`; the app uses the dedicated one.
    public init(endpoint: URL, session: URLSession? = nil) {
        self.endpoint = endpoint
        self.session = session ?? Self.makeSession()
    }

    public func post(_ body: Data) async throws -> Data {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let delivery = RequestDeliveryTracker()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request, delegate: delivery)
        } catch {
            // The endpoint is hashed; the error is reduced to its code.
            Self.logger.error(
                "Request failed: \((error as? URLError)?.code.rawValue ?? 0, privacy: .public) at \(self.endpoint.absoluteString, privacy: .private(mask: .hash))"
            )
            // An error code alone cannot distinguish initial connection failure
            // from a failure following a redirect after the server committed.
            if delivery.provesRequestWasNotSent {
                throw HTTPTransportError.requestNotSent(String(describing: error))
            }
            throw error
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HTTPTransportError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            Self.logger.error(
                "Request failed: HTTP \(httpResponse.statusCode, privacy: .public) at \(self.endpoint.absoluteString, privacy: .private(mask: .hash))"
            )
            throw HTTPTransportError.statusCode(httpResponse.statusCode)
        }
        return data
    }
}

// MARK: - Client

public protocol SheetAPIClient: Sendable {
    var endpointIdentity: String? { get }
    func getState(seasonSheetId: Int?) async throws -> SheetState
    func sharedRead(action: String, fields: [String: GuestJSON]) async throws -> GuestJSON
    func perform(_ operation: SharedGuestOperation) async throws -> GuestJSON
    func operationStatus(id: UUID) async throws -> GuestOperationReceipt?
    func getState() async throws -> SheetState
    func submitAttendance(_ submission: AttendanceSubmission) async throws -> SubmissionOutcome
    func addMember(name: String) async throws -> AddMemberResult
    func addRun(_ request: AddRunRequest) async throws -> AddRunResult
}

public actor SheetAPI: SheetAPIClient {
    let config: AppConfig
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

    func send<Request: Encodable, Response: Decodable>(
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
        } catch HTTPTransportError.requestNotSent(let message) {
            throw SheetAPIError.requestNotSent(message)
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
