//
//  TransferHashTests.swift
//  SeaPay KYCTests
//
//  Tests for transfer package integrity hashing.
//

import XCTest
@testable import SeaPay_KYC

final class TransferHashTests: XCTestCase {

    func testHashIsDeterministic() {
        let vessel = "{\"name\":\"Test\"}".data(using: .utf8)!
        let checks = "[{\"id\":\"1\"}]".data(using: .utf8)!

        let hash1 = TransferHash.compute(vesselData: vessel, checksData: checks)
        let hash2 = TransferHash.compute(vesselData: vessel, checksData: checks)
        XCTAssertEqual(hash1, hash2, "Same input should produce same hash")
    }

    func testHashChangesWithDifferentData() {
        let vessel1 = "{\"name\":\"Vessel A\"}".data(using: .utf8)!
        let vessel2 = "{\"name\":\"Vessel B\"}".data(using: .utf8)!
        let checks = "[{\"id\":\"1\"}]".data(using: .utf8)!

        let hash1 = TransferHash.compute(vesselData: vessel1, checksData: checks)
        let hash2 = TransferHash.compute(vesselData: vessel2, checksData: checks)
        XCTAssertNotEqual(hash1, hash2, "Different input should produce different hash")
    }

    func testHashIsValidSHA256() {
        let vessel = "{}".data(using: .utf8)!
        let checks = "[]".data(using: .utf8)!
        let hash = TransferHash.compute(vesselData: vessel, checksData: checks)

        XCTAssertEqual(hash.count, 64, "SHA256 hex string should be 64 chars")
        XCTAssertTrue(hash.allSatisfy { $0.isHexDigit }, "Should only contain hex characters")
    }

    func testHashWithEmptyData() {
        let hash = TransferHash.compute(vesselData: Data(), checksData: Data())
        XCTAssertEqual(hash.count, 64, "Empty data should still produce valid hash")
    }
}
