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
    /// Custom URL scheme the setup QR encodes, claimed by the app in its Info.plist
    /// so the iOS Camera app opens FCTC Attendance instead of Safari. Keep in sync
    /// with `ios/project.yml` and `apps-script/make-setup-qr.js`.
    public static let scheme = "fctc-attendance"
    /// The one action the scheme carries: `fctc-attendance://setup?…`.
    public static let host = "setup"

    public init() {}

    /// Accepts either form of setup code:
    ///
    /// - `fctc-attendance://setup?endpoint=…&secret=…&device=…`, what the generator
    ///   writes now, and what arrives through `onOpenURL` when the code is scanned
    ///   with the Camera app.
    /// - The original JSON object, so codes handed out before the change still work
    ///   in the in-app scanner.
    public func parse(_ payload: String) throws -> AppConfig {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        let decoded = try Self.isSetupLink(trimmed)
            ? Self.decodeSetupLink(trimmed)
            : Self.decodeJSON(trimmed)

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

    /// True for anything carrying our scheme, so a malformed link reports itself as
    /// a bad setup code rather than falling through to the JSON decoder.
    public static func isSetupLink(_ payload: String) -> Bool {
        URLComponents(string: payload)?.scheme?.lowercased() == scheme
    }

    private static func decodeSetupLink(_ payload: String) throws -> SetupCodePayload {
        guard let components = URLComponents(string: payload),
              components.host?.lowercased() == host,
              // `queryItems` percent-decodes for us; the generator writes %20 rather
              // than `+` because this decoder does not treat `+` as a space.
              let items = components.queryItems,
              let endpoint = items.first(where: { $0.name == "endpoint" })?.value,
              let secret = items.first(where: { $0.name == "secret" })?.value
        else {
            throw SetupCodeError.invalidPayload
        }
        return SetupCodePayload(
            endpoint: endpoint,
            secret: secret,
            deviceName: items.first(where: { $0.name == "device" })?.value
        )
    }

    private static func decodeJSON(_ payload: String) throws -> SetupCodePayload {
        do {
            return try JSONDecoder().decode(SetupCodePayload.self, from: Data(payload.utf8))
        } catch {
            throw SetupCodeError.invalidPayload
        }
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
