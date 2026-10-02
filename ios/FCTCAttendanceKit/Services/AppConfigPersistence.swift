//
//  AppConfigPersistence.swift
//  FCTCAttendanceKit
//
//  Non-secret settings use UserDefaults. The shared secret uses Keychain Services.
//  Both are protocol-fronted so view-model tests never access a real keychain.
//

import Foundation
import Security

public protocol SecretStoring: Sendable {
    func readSecret() throws -> String?
    /// Stores a non-empty secret. `save` routes an empty one to `deleteSecret`.
    func writeSecret(_ value: String) throws
    /// Removes the stored secret. A missing secret counts as success (PLAT-18).
    func deleteSecret() throws
}

public protocol AppConfigPersisting: Sendable {
    func load() throws -> AppConfig
    func save(_ config: AppConfig) throws
}

/// `@unchecked` because `UserDefaults` is not marked `Sendable`, though Apple
/// documents it as thread-safe; every other stored property is immutable.
public final class UserDefaultsAppConfigPersistence: AppConfigPersisting, @unchecked Sendable {
    private enum Key {
        static let endpoint = "fctc.endpoint"
        static let deviceName = "fctc.deviceName"
    }

    private let defaults: UserDefaults
    private let secretStore: any SecretStoring

    public init(
        defaults: UserDefaults = .standard,
        secretStore: any SecretStoring = KeychainSecretStore()
    ) {
        self.defaults = defaults
        self.secretStore = secretStore
    }

    /// Throws `AppConfigLoadError` when the secret cannot be read. The error
    /// keeps the endpoint, so a locked keychain never reads as "not set up".
    public func load() throws -> AppConfig {
        var config = AppConfig(
            endpoint: defaults.string(forKey: Key.endpoint).flatMap(URL.init(string:)),
            deviceName: defaults.string(forKey: Key.deviceName)
        )
        do {
            config.secret = try secretStore.readSecret() ?? ""
        } catch {
            throw AppConfigLoadError(endpointOnly: config, underlying: error)
        }
        return config
    }

    public func save(_ config: AppConfig) throws {
        // Write the sensitive value first. If Keychain rejects the write, the visible
        // endpoint does not move ahead to a configuration the app cannot use.
        // An empty secret means "forget it", never "store an empty string".
        if config.secret.isEmpty {
            try secretStore.deleteSecret()
        } else {
            try secretStore.writeSecret(config.secret)
        }
        defaults.set(config.endpoint?.absoluteString, forKey: Key.endpoint)
        defaults.set(config.deviceName, forKey: Key.deviceName)
    }
}

public struct KeychainSecretStore: SecretStoring {
    private let service: String
    private let account: String

    public init(
        service: String = "com.cpdis.fctc-attendance",
        account: String = "sheet-shared-secret"
    ) {
        self.service = service
        self.account = account
    }

    public func readSecret() throws -> String? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(
            baseQuery(matchingData: true) as CFDictionary,
            &result
        )
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainStoreError(status: status) }
        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8)
        else { throw KeychainStoreError.invalidData }
        return value
    }

    public func writeSecret(_ value: String) throws {
        let data = Data(value.utf8)
        let updateStatus = SecItemUpdate(
            baseQuery() as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainStoreError(status: updateStatus)
        }

        var insert = baseQuery()
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let insertStatus = SecItemAdd(insert as CFDictionary, nil)
        guard insertStatus == errSecSuccess else {
            throw KeychainStoreError(status: insertStatus)
        }
    }

    /// Removes the stored secret. A missing item counts as success.
    public func deleteSecret() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError(status: status)
        }
    }

    private func baseQuery(matchingData: Bool = false) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if matchingData {
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
        }
        return query
    }
}

/// The saved endpoint loaded but the secret did not. `endpointOnly` has the
/// endpoint and device name with an empty secret.
public struct AppConfigLoadError: LocalizedError, Sendable {
    public let endpointOnly: AppConfig
    public let underlying: any Error

    public init(endpointOnly: AppConfig, underlying: any Error) {
        self.endpointOnly = endpointOnly
        self.underlying = underlying
    }

    /// The secret is there but unreadable until the device unlocks: retry
    /// later, and do not ask the person to set up the app again.
    public var isRetryLater: Bool {
        (underlying as? KeychainStoreError) == .interactionNotAllowed
    }

    public var errorDescription: String? { underlying.localizedDescription }
}

public enum KeychainStoreError: LocalizedError, Sendable, Equatable {
    case operationFailed(OSStatus)
    /// `errSecInteractionNotAllowed` (-25308): the device has not been unlocked
    /// since it started, so an `AfterFirstUnlock` item cannot be read yet.
    case interactionNotAllowed
    case invalidData

    init(status: OSStatus) {
        self = status == errSecInteractionNotAllowed ? .interactionNotAllowed : .operationFailed(status)
    }

    public var errorDescription: String? {
        switch self {
        case .operationFailed(let status):
            SecCopyErrorMessageString(status, nil) as String?
                ?? "Keychain operation failed (\(status))."
        case .interactionNotAllowed:
            "The keychain stays locked until this iPhone is unlocked."
        case .invalidData:
            "The saved secret is not valid UTF-8 text."
        }
    }
}
