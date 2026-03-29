//
//  EncryptionService.swift
//  OceanCheck
//
//  AES-GCM encryption for data at rest.
//  Key stored in Keychain, auto-migrates unencrypted files on first use.
//

import Foundation
import CryptoKit

// Explicitly nonisolated — all methods use thread-safe Keychain + CryptoKit
enum EncryptionService: Sendable {

    private static let keychainAccount = "com.seapay.kyc.encryptionKey"

    /// Check if Keychain is accessible (fails in some test sandboxes)
    static var isKeychainAvailable: Bool {
        let testKey = "com.seapay.kyc.keychainTest"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.seapay.kyc.test",
            kSecAttrAccount as String: testKey,
            kSecValueData as String: Data([0x01]),
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        SecItemDelete(query as CFDictionary)
        return status == errSecSuccess
    }

    // MARK: - Key Management

    /// Retrieve or generate the 256-bit encryption key from Keychain.
    private static func getOrCreateKey() -> SymmetricKey {
        if let existing = loadKeyFromKeychain() { return existing }
        let key = SymmetricKey(size: .bits256)
        saveKeyToKeychain(key)
        return key
    }

    private static func loadKeyFromKeychain() -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.seapay.kyc.encryption",
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return SymmetricKey(data: data)
    }

    private static func saveKeyToKeychain(_ key: SymmetricKey) {
        let keyData = key.withUnsafeBytes { Data($0) }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.seapay.kyc.encryption",
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    // MARK: - Encrypt / Decrypt

    /// Encrypt data using AES-GCM. Returns nonce + ciphertext + tag.
    static func encrypt(_ plaintext: Data) throws -> Data {
        let key = getOrCreateKey()
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else {
            throw EncryptionError.encryptionFailed
        }
        return combined
    }

    /// Decrypt AES-GCM combined data (nonce + ciphertext + tag).
    static func decrypt(_ ciphertext: Data) throws -> Data {
        let key = getOrCreateKey()
        let box = try AES.GCM.SealedBox(combined: ciphertext)
        return try AES.GCM.open(box, using: key)
    }

    // MARK: - File Helpers

    /// Write encrypted data to a file.
    static func writeEncrypted(_ data: Data, to url: URL) throws {
        let encrypted = try encrypt(data)
        try encrypted.write(to: url, options: .atomic)
    }

    /// Read and decrypt data from a file. Returns nil if file doesn't exist.
    static func readDecrypted(from url: URL) -> Data? {
        guard let ciphertext = try? Data(contentsOf: url) else { return nil }
        // Try decrypting first (normal encrypted file)
        if let plaintext = try? decrypt(ciphertext) { return plaintext }
        // If decryption fails, this might be a legacy unencrypted file — return as-is
        return ciphertext
    }

    /// Detect if a file is encrypted (AES-GCM combined format starts with 12-byte nonce).
    /// We check by attempting decryption — if it works, it's encrypted.
    static func isEncrypted(at url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url), data.count > 28 else { return false }
        return (try? decrypt(data)) != nil
    }

    // MARK: - Migration

    /// Migrate a plaintext JSON file to encrypted format in-place.
    /// Safe to call on already-encrypted files (no-op).
    static func migrateIfNeeded(at url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        guard let data = try? Data(contentsOf: url) else { return }
        // Try to decrypt — if it succeeds, already encrypted
        if (try? decrypt(data)) != nil { return }
        // Verify it's valid JSON (plain text) before encrypting
        guard (try? JSONSerialization.jsonObject(with: data)) != nil else { return }
        // Encrypt in place
        try? writeEncrypted(data, to: url)
    }
}

enum EncryptionError: LocalizedError {
    case encryptionFailed
    case decryptionFailed

    var errorDescription: String? {
        switch self {
        case .encryptionFailed: return "Failed to encrypt data."
        case .decryptionFailed: return "Failed to decrypt data."
        }
    }
}
