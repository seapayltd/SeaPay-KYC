//
//  VesselTests.swift
//  SeaPay KYCTests
//
//  Tests for Vessel model: Codable, computed properties, backward compatibility.
//

import XCTest
@testable import SeaPay_KYC

final class VesselTests: XCTestCase {

    // MARK: - Computed Properties

    func testGrossTonnageValue() {
        var v = Vessel(name: "Test")
        v.grossTonnage = "480"
        XCTAssertEqual(v.grossTonnageValue, 480)

        v.grossTonnage = "1,234"
        XCTAssertEqual(v.grossTonnageValue, 1234)

        v.grossTonnage = " 500 "
        XCTAssertEqual(v.grossTonnageValue, 500)

        v.grossTonnage = ""
        XCTAssertNil(v.grossTonnageValue)

        v.grossTonnage = "abc"
        XCTAssertNil(v.grossTonnageValue)
    }

    func testLengthOverallMetres() {
        var v = Vessel(name: "Test")
        v.lengthOverall = "42.5"
        XCTAssertEqual(v.lengthOverallMetres, 42.5)

        v.lengthOverall = "42.5m"
        XCTAssertEqual(v.lengthOverallMetres, 42.5)
    }

    func testRegisteredLengthValue() {
        var v = Vessel(name: "Test")
        v.registeredLength = "38.2"
        XCTAssertEqual(v.registeredLengthValue, 38.2)
    }

    func testRegulatoryLengthPrefersRegistered() {
        var v = Vessel(name: "Test")
        v.registeredLength = "38.2"
        v.lengthOverall = "42.5"
        XCTAssertEqual(v.regulatoryLength, 38.2, "Should prefer registered length")
    }

    func testRegulatoryLengthFallsBackToLOA() {
        var v = Vessel(name: "Test")
        v.registeredLength = ""
        v.lengthOverall = "42.5"
        XCTAssertEqual(v.regulatoryLength, 42.5, "Should fall back to LOA")
    }

    func testYearBuiltValue() {
        var v = Vessel(name: "Test")
        v.yearBuilt = "2019"
        XCTAssertEqual(v.yearBuiltValue, 2019)

        v.yearBuilt = ""
        XCTAssertNil(v.yearBuiltValue)
    }

    // MARK: - Codable Round-Trip

    func testCodableRoundTrip() throws {
        var vessel = Vessel(name: "M/Y OCEANUS", imoNumber: "9876543", flagState: "Malta", vesselType: .megayachtCharter)
        vessel.grossTonnage = "480"
        vessel.registeredLength = "38.2"
        vessel.lengthOverall = "42.5"

        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let data = try encoder.encode(vessel)
        let decoded = try decoder.decode(Vessel.self, from: data)

        XCTAssertEqual(decoded.name, "M/Y OCEANUS")
        XCTAssertEqual(decoded.imoNumber, "9876543")
        XCTAssertEqual(decoded.flagState, "Malta")
        XCTAssertEqual(decoded.vesselType, .megayachtCharter)
        XCTAssertEqual(decoded.grossTonnage, "480")
        XCTAssertEqual(decoded.registeredLength, "38.2")
    }

    // MARK: - Backward Compatibility (registeredLength missing)

    func testDecodesWithoutRegisteredLength() throws {
        // Simulate JSON from older app version without registeredLength field
        let json = """
        {
            "id": "test-id",
            "name": "OLD VESSEL",
            "imoNumber": "1234567",
            "officialNumber": "",
            "callSign": "",
            "flagState": "Malta",
            "portOfRegistry": "Valletta",
            "certificateNumber": "",
            "builder": "",
            "yearBuilt": "2020",
            "hullMaterial": "",
            "vesselDescription": "",
            "lengthOverall": "30.0",
            "breadth": "7.0",
            "depth": "3.0",
            "draught": "2.0",
            "grossTonnage": "200",
            "netTonnage": "60",
            "propulsionType": "",
            "engineDescription": "",
            "engineMaker": "",
            "propulsionPower": "",
            "estimatedSpeed": "",
            "registeredOwner": "Test Owner",
            "ownerAddress": "",
            "registrationDate": "",
            "certificateExpiry": "",
            "createdAt": "2024-01-01T00:00:00Z"
        }
        """
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let vessel = try decoder.decode(Vessel.self, from: data)

        XCTAssertEqual(vessel.name, "OLD VESSEL")
        XCTAssertEqual(vessel.registeredLength, "", "Should default to empty string")
        XCTAssertEqual(vessel.regulatoryLength, 30.0, "Should fall back to LOA")
    }
}
