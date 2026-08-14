//
//  SetupCodeParser.swift
//  FCTCAttendanceKit
//
//  Camera-free setup-code validation. The app scanner supplies only a String, so
//  tests can cover the complete secret and endpoint contract without AVFoundation.
//

import Foundation

public protocol SetupCodePayloadParsing: Sendable {
    func parse(_ payload: String) throws -> AppConfig
}

public struct SetupCodeParser: SetupCodePayloadParsing {
    public init() {}

    public func parse(_ payload: String) throws -> AppConfig {
        let decoded: SetupCodePayload
        do {
            decoded = try JSONDecoder().decode(
                SetupCodePayload.self,
                from: Data(payload.utf8)
            )
        } catch {
            throw SetupCodeError.invalidPayload
        }

        let endpointText = decoded.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let endpoint = URL(string: endpointText),
              endpoint.scheme?.lowercased() == "https",
              endpoint.host != nil
        else {
            throw SetupCodeError.invalidEndpoint
        }

        let secret = decoded.secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !secret.isEmpty else { throw SetupCodeError.emptySecret }

        let deviceName = decoded.deviceName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        return AppConfig(endpoint: endpoint, secret: secret, deviceName: deviceName)
    }
}

public enum SetupCodeError: LocalizedError, Sendable, Equatable {
    case invalidPayload
    case invalidEndpoint
    case emptySecret

    public var errorDescription: String? {
        switch self {
        case .invalidPayload:
            "This setup code is not valid. Generate a new code and try again."
        case .invalidEndpoint:
            "This setup code needs a valid HTTPS endpoint."
        case .emptySecret:
            "This setup code does not include a shared secret."
        }
    }
}

private struct SetupCodePayload: Decodable {
    let endpoint: String
    let secret: String
    let deviceName: String?
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
