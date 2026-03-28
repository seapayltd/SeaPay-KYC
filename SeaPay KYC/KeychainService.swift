//
//  KeychainService.swift
//  SeaPay KYC
//
//  Secure storage using iOS Keychain
//

import Foundation
import Security

enum KeychainService: Sendable {
    nonisolated private static let serviceName = "com.seapay.kyc"

    enum Key: String, Sendable, CaseIterable {
        case authToken
        case diditAPIKey
        case claudeAPIKey
        case workflowID
        case diditAccessToken
        case appMode // "agent" or "subject"
    }

    nonisolated static func save(_ value: String, for key: Key) {
        guard let data = value.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key.rawValue
        ]

        SecItemDelete(query as CFDictionary)

        var newItem = query
        newItem[kSecValueData as String] = data
        newItem[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        SecItemAdd(newItem as CFDictionary, nil)
    }

    nonisolated static func get(_ key: Key) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    nonisolated static func delete(_ key: Key) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key.rawValue
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Deletes ALL keys including API key
    nonisolated static func deleteAll() {
        for key in Key.allCases {
            delete(key)
        }
    }

    /// Deletes auth token but keeps API keys
    nonisolated static func deleteAuthTokens() {
        delete(.authToken)
    }
}
