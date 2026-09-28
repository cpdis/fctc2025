//
//  SetupCodeReview.swift
//  FCTCAttendanceKit
//
//  What a person must see before a setup link may replace this phone's connection.
//  Any web page or chat message can open `fctc-attendance://setup?…`, and every
//  Apps Script endpoint shares the host `script.google.com`, so the host alone
//  cannot tell the club's sheet from an attacker's. The deployment ID can.
//

import Foundation

/// The sheet deployment an endpoint talks to, in a form a person can check.
///
///     https://script.google.com/macros/s/AKfycbz…x9Qc/exec
///                                        └─── id ───┘      label "AKfy…x9Qc"
///     https://sheet.example/exec           id and label    "sheet.example/exec"
public struct SheetDeployment: Hashable, Sendable {
    /// The comparison key: the Apps Script deployment ID, or host plus path.
    public let id: String
    /// A short form of `id` that fits on one alert line.
    public let label: String

    /// Nil when the endpoint has no host, so there is nothing to show or compare.
    public init?(endpoint: URL?) {
        // Percent-encoded on purpose: a look-alike character shows as `%D1%95`
        // instead of rendering as the letter it imitates.
        guard let endpoint,
              let host = endpoint.host(percentEncoded: true)?.lowercased(),
              !host.isEmpty
        else { return nil }
        if let deploymentID = Self.appsScriptDeploymentID(host: host, path: endpoint.pathComponents) {
            id = deploymentID
            label = Self.abbreviated(deploymentID)
        } else {
            let port = endpoint.port.map { ":\($0)" } ?? ""
            var path = endpoint.path(percentEncoded: true)
            // `/exec` and `/exec/` reach the same handler.
            if path.hasSuffix("/") { path.removeLast() }
            id = host + port + path
            label = id
        }
    }

    /// `/macros/s/<id>/exec`, or `/a/macros/<domain>/s/<id>/exec` on Workspace.
    private static func appsScriptDeploymentID(host: String, path: [String]) -> String? {
        guard host == "script.google.com" else { return nil }
        let parts = path.filter { $0 != "/" }
        guard let macros = parts.firstIndex(of: "macros"),
              let marker = parts[macros...].firstIndex(of: "s"),
              parts.indices.contains(marker + 1)
        else { return nil }
        let id = parts[marker + 1]
        // Real deployment IDs are URL-safe base64. Anything else (for example
        // look-alike Unicode) is not one, so it falls back to the full path.
        let isDeploymentID = id.allSatisfy {
            $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_")
        }
        return isDeploymentID ? id : nil
    }

    /// Deployment IDs run to about 70 characters. Every one starts `AKfycb`, so the
    /// prefix only says "Apps Script"; the suffix is what tells two apart.
    private static func abbreviated(_ id: String) -> String {
        guard id.count > 12 else { return id }
        return "\(id.prefix(4))…\(id.suffix(4))"
    }
}

/// The confirmation a setup link needs before it may touch the saved connection.
/// Pure value logic, so the copy and the same-or-different decision are testable.
public struct SetupCodeReview: Equatable, Sendable {
    public enum Change: Equatable, Sendable {
        /// The phone has no working connection yet.
        case firstConnection
        /// The code points at the deployment the phone already uses.
        case sameSheet
        /// The code points at a different deployment than `current`.
        case replacesSheet(current: SheetDeployment)
    }

    public let deployment: SheetDeployment
    public let deviceName: String?
    public let change: Change
    /// Outstanding submissions SyncEngine stops sending if this code is applied.
    public let strandedSubmissions: Int

    /// - Parameter waitingSubmissions: outstanding rows for `current`'s endpoint,
    ///   from `PendingSubmission.outstandingCount(endpointIdentity:in:)`.
    public init?(incoming: AppConfig, current: AppConfig, waitingSubmissions: Int) {
        guard let deployment = SheetDeployment(endpoint: incoming.endpoint) else { return nil }
        self.deployment = deployment
        deviceName = incoming.deviceName
        let currentDeployment = current.isConfigured ? SheetDeployment(endpoint: current.endpoint) : nil
        if let currentDeployment {
            change = currentDeployment == deployment ? .sameSheet : .replacesSheet(current: currentDeployment)
        } else {
            change = .firstConnection
        }
        // SyncEngine scopes each row to the exact endpoint string and parks rows
        // for any other string. So even a same-deployment code strands them if the
        // URL text differs (for example an added query).
        let endpointChanges = incoming.endpoint?.absoluteString != current.endpoint?.absoluteString
        strandedSubmissions = endpointChanges ? waitingSubmissions : 0
    }

    public var title: String {
        switch change {
        case .firstConnection: "Connect this phone?"
        case .sameSheet: "Update this connection?"
        case .replacesSheet: "Replace the sheet connection?"
        }
    }

    /// The confirm button repeats the title's verb.
    public var confirmTitle: String {
        switch change {
        case .firstConnection: "Connect"
        case .sameSheet: "Update"
        case .replacesSheet: "Replace"
        }
    }

    /// True when confirming loses something: another sheet or waiting submissions.
    public var isDestructive: Bool {
        if case .replacesSheet = change { return true }
        return strandedSubmissions > 0
    }

    /// Two paragraphs: what the code points at, then what confirming changes.
    public var message: String {
        let identity = "Sheet: \(deployment.label)\nDevice: \(deviceName ?? "no name")"
        var sentences: [String] = []
        var closing: String?
        switch change {
        case .firstConnection:
            closing = "Connect only if you recognise this sheet."
        case .sameSheet:
            sentences.append("This phone already uses this sheet. The code updates the secret and device name.")
        case .replacesSheet(let current):
            sentences.append("This replaces the current sheet, \(current.label).")
            closing = "Replace only if you recognise the new sheet."
        }
        switch strandedSubmissions {
        case 0:
            break
        case 1:
            sentences.append("The app will not send 1 submission that is waiting to sync. It stays in Outbox for review.")
        default:
            sentences.append("The app will not send \(strandedSubmissions) submissions that are waiting to sync. They stay in Outbox for review.")
        }
        if let closing { sentences.append(closing) }
        return identity + "\n\n" + sentences.joined(separator: " ")
    }
}
