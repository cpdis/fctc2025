//
//  SettingsViewModel.swift
//  FCTCAttendanceKit
//

import Foundation
import Observation

@MainActor
@Observable
public final class SettingsViewModel {
    public var endpoint = ""
    public var secret = ""
    public var deviceName = ""
    public private(set) var isRefreshing = false
    public private(set) var errorMessage: String?
    public private(set) var successMessage: String?

    @ObservationIgnored private let persistence: any AppConfigPersisting
    @ObservationIgnored private var engine: any SyncEngineClient
    @ObservationIgnored private let eventMonitor = SyncEventMonitor()

    public init(
        persistence: any AppConfigPersisting,
        engine: any SyncEngineClient
    ) {
        self.persistence = persistence
        self.engine = engine
        do {
            importConfiguration(try persistence.load())
        } catch {
            errorMessage = error.localizedDescription
        }
        observeEvents()
    }

    public var canSave: Bool {
        validatedEndpoint != nil && !secret.isEmpty
    }

    public func replaceEngine(_ engine: any SyncEngineClient) {
        self.engine = engine
        observeEvents()
    }

    @discardableResult
    public func save() throws -> AppConfig {
        guard let endpoint = validatedEndpoint else {
            throw SettingsError.invalidEndpoint
        }
        guard !secret.isEmpty else { throw SettingsError.emptySecret }
        let config = AppConfig(
            endpoint: endpoint,
            secret: secret,
            deviceName: deviceName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
        do {
            try persistence.save(config)
            errorMessage = nil
            successMessage = "Settings saved."
            return config
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    public func refreshRoster() async throws {
        isRefreshing = true
        errorMessage = nil
        successMessage = nil
        defer { isRefreshing = false }
        do {
            _ = try await engine.refreshState()
            successMessage = "Roster refreshed."
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    /// U8's QR scanner can hand its decoded configuration to this seam without
    /// changing the settings form or its persistence rules.
    public func importConfiguration(_ config: AppConfig) {
        endpoint = config.endpoint?.absoluteString ?? ""
        secret = config.secret
        deviceName = config.deviceName ?? ""
    }

    private var validatedEndpoint: URL? {
        guard let url = URL(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              ["https", "http"].contains(scheme),
              url.host != nil
        else { return nil }
        return url
    }

    private func observeEvents() {
        eventMonitor.start(engine: engine) { [weak self] event in
            if case .rosterRefreshed = event {
                self?.successMessage = "Roster refreshed."
            }
        }
    }
}

public enum SettingsError: LocalizedError, Sendable, Equatable {
    case invalidEndpoint
    case emptySecret

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint: "Enter a valid HTTP or HTTPS endpoint."
        case .emptySecret: "Enter the shared secret."
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
