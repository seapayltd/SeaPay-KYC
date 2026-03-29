//
//  EncryptionTests.swift
//  SeaPay KYCTests
//
//  Tests for AES-GCM encryption/decryption and migration.
//

import XCTest
@testable import SeaPay_KYC

final class EncryptionTests: XCTestCase {

    // MARK: - Encrypt / Decrypt Round-Trip

    func testEncryptDecryptRoundTrip() throws {
        let original = "Sensitive PII data: passport number AB123456".data(using: .utf8)!
        let encrypted = try EncryptionService.encrypt(original)
        let decrypted = try EncryptionService.decrypt(encrypted)
        XCTAssertEqual(decrypted, original)
    }

    func testEncryptedDataDiffersFromOriginal() throws {
        let original = "Test data".data(using: .utf8)!
        let encrypted = try EncryptionService.encrypt(original)
        XCTAssertNotEqual(encrypted, original)
        XCTAssertGreaterThan(encrypted.count, original.count, "Encrypted data includes nonce + tag overhead")
    }

    func testEncryptEmptyData() throws {
        let empty = Data()
        let encrypted = try EncryptionService.encrypt(empty)
        let decrypted = try EncryptionService.decrypt(encrypted)
        XCTAssertEqual(decrypted, empty)
    }

    func testEncryptLargeData() throws {
        let large = Data(repeating: 0xAB, count: 1_000_000) // 1MB
        let encrypted = try EncryptionService.encrypt(large)
        let decrypted = try EncryptionService.decrypt(encrypted)
        XCTAssertEqual(decrypted, large)
    }

    // MARK: - File Helpers

    func testWriteAndReadEncrypted() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test_encrypted.bin")
        defer { try? FileManager.default.removeItem(at: url) }

        let original = "{\"name\": \"test\"}".data(using: .utf8)!
        try EncryptionService.writeEncrypted(original, to: url)

        let readBack = EncryptionService.readDecrypted(from: url)
        XCTAssertEqual(readBack, original)
    }

    func testReadDecryptedFallsBackToPlaintext() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test_plaintext.json")
        defer { try? FileManager.default.removeItem(at: url) }

        let plaintext = "[{\"id\":\"1\"}]".data(using: .utf8)!
        try? plaintext.write(to: url)

        let readBack = EncryptionService.readDecrypted(from: url)
        XCTAssertEqual(readBack, plaintext, "Should return plaintext as-is if decryption fails")
    }

    func testReadDecryptedFromMissingFile() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("nonexistent_\(UUID().uuidString).json")
        XCTAssertNil(EncryptionService.readDecrypted(from: url))
    }

    // MARK: - Migration

    func testMigrateEncryptsPlaintextJSON() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test_migrate.json")
        defer { try? FileManager.default.removeItem(at: url) }

        let json = "[{\"name\":\"test\"}]".data(using: .utf8)!
        try json.write(to: url)

        EncryptionService.migrateIfNeeded(at: url)

        // File should now be encrypted (not readable as JSON directly)
        let raw = try Data(contentsOf: url)
        XCTAssertNil(try? JSONSerialization.jsonObject(with: raw), "File should be encrypted, not readable as JSON")

        // But readDecrypted should work
        let decrypted = EncryptionService.readDecrypted(from: url)
        XCTAssertEqual(decrypted, json)
    }

    func testMigrateSkipsAlreadyEncrypted() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test_migrate2.json")
        defer { try? FileManager.default.removeItem(at: url) }

        let json = "[{\"name\":\"test\"}]".data(using: .utf8)!
        try EncryptionService.writeEncrypted(json, to: url)

        let beforeSize = try Data(contentsOf: url).count
        EncryptionService.migrateIfNeeded(at: url) // Should be a no-op
        let afterSize = try Data(contentsOf: url).count

        XCTAssertEqual(beforeSize, afterSize, "Already encrypted file should not change")
    }
}
