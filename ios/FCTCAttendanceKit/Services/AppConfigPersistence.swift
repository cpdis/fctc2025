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
    func writeSecret(_ value: String) throws
}

public protocol AppConfigPersisting: Sendable {
    func load() throws -> AppConfig
    func save(_ config: AppConfig) throws
}

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

    public func load() throws -> AppConfig {
        AppConfig(
            endpoint: defaults.string(forKey: Key.endpoint).flatMap(URL.init(string:)),
            secret: try secretStore.readSecret() ?? "",
            deviceName: defaults.string(forKey: Key.deviceName)
        )
    }

    public func save(_ config: AppConfig) throws {
        // Write the sensitive value first. If Keychain rejects the write, the visible
        // endpoint does not move ahead to a configuration the app cannot use.
        try secretStore.writeSecret(config.secret)
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
        if value.isEmpty {
            let status = SecItemDelete(baseQuery() as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw KeychainStoreError(status: status)
            }
            return
        }

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

public enum KeychainStoreError: LocalizedError, Sendable, Equatable {
    case operationFailed(OSStatus)
    case invalidData

    init(status: OSStatus) {
        self = .operationFailed(status)
    }

    public var errorDescription: String? {
        switch self {
        case .operationFailed(let status):
            SecCopyErrorMessageString(status, nil) as String?
                ?? "Keychain operation failed (\(status))."
        case .invalidData:
            "The saved secret is not valid UTF-8 text."
        }
    }
}
