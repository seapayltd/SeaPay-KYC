//
//  ComplianceEngineTests.swift
//  SeaPay KYCTests
//
//  Tests for flag state document requirements and compliance engine.
//

import XCTest
@testable import SeaPay_KYC

final class ComplianceEngineTests: XCTestCase {

    // MARK: - Crew Document Requirements

    func testMaltaCaptainRequirements() {
        let docs = FlagStateRequirements.required(flag: "Malta", vesselType: .megayachtCharter, rank: .captain)
        XCTAssertTrue(docs.contains(.passport), "Captain needs passport")
        XCTAssertTrue(docs.contains(.seamansBook), "Captain needs seaman's book")
        XCTAssertTrue(docs.contains(.stcwBST), "Captain needs STCW BST")
        XCTAssertTrue(docs.contains(.cocDeck), "Captain needs deck COC")
    }

    func testEngineerRequirements() {
        let docs = FlagStateRequirements.required(flag: "Malta", vesselType: .megayachtCharter, rank: .chiefEngineer)
        XCTAssertTrue(docs.contains(.cocEngine), "Chief Engineer needs engine COC")
        XCTAssertFalse(docs.contains(.cocDeck), "Chief Engineer should not need deck COC")
    }

    func testCookRequirements() {
        let docs = FlagStateRequirements.required(flag: "Malta", vesselType: .megayachtCharter, rank: .cook)
        XCTAssertTrue(docs.contains(.passport))
        XCTAssertTrue(docs.contains(.stcwBST))
        XCTAssertTrue(docs.contains(.shipsCookCert), "Cook needs ship's cook certificate")
    }

    func testEmptyFlagStillReturnsBasics() {
        let docs = FlagStateRequirements.required(flag: "", vesselType: nil, rank: .ab)
        XCTAssertTrue(docs.contains(.passport), "Always need passport regardless of flag")
        XCTAssertTrue(docs.contains(.stcwBST), "Always need STCW BST")
    }

    // MARK: - Vessel Document Requirements

    func testMaltaYachtVesselDocs() {
        let docs = FlagStateRequirements.requiredVesselDocs(
            flag: "Malta", vesselType: .megayachtCharter,
            grossTonnage: 480, lengthOverall: 42.5, registeredLength: 38.2, yearBuilt: 2019
        )
        let types = docs.map(\.type)
        XCTAssertTrue(types.contains(.certificateOfRegistry), "All vessels need CoR")
        XCTAssertTrue(types.contains(.safetyManagementCert), "GT > 500 or charter needs SMC")
    }

    func testSmallVesselSkipsLargeShipDocs() {
        let docs = FlagStateRequirements.requiredVesselDocs(
            flag: "Malta", vesselType: .megayachtPrivate,
            grossTonnage: 100, lengthOverall: 20, registeredLength: 18, yearBuilt: 2022
        )
        let types = docs.map(\.type)
        // Small private yacht should not need IOPP (only >400 GT)
        XCTAssertFalse(types.contains(.ioppCert), "Sub-400 GT should not need IOPP")
    }

    // MARK: - Entity Type Requirements

    func testOwnerEntityDocRequirements() {
        let docs = FlagStateRequirements.requiredForEntity(.owner)
        XCTAssertTrue(docs.contains(.passport), "Owner needs passport")
        XCTAssertTrue(docs.contains(.articlesOfAssociation), "Owner needs Articles")
        XCTAssertTrue(docs.contains(.certificateOfIncorporation), "Owner needs CoI")
    }

    func testUBOEntityDocRequirements() {
        let docs = FlagStateRequirements.requiredForEntity(.ubo)
        XCTAssertTrue(docs.contains(.passport))
        XCTAssertTrue(docs.contains(.uboDeclaration), "UBO needs declaration")
    }

    func testTrusteeEntityDocRequirements() {
        let docs = FlagStateRequirements.requiredForEntity(.trustee)
        XCTAssertFalse(docs.isEmpty, "Trustee should have document requirements")
        XCTAssertTrue(docs.contains(.passport))
    }

    func testSeafarerEntityNotInComplianceDocs() {
        let docs = FlagStateRequirements.requiredForEntity(.seafarer)
        // Seafarer entity requirements use the flag-based system, not entity-based
        // This should return empty or basic docs
        XCTAssertTrue(docs.isEmpty || docs.contains(.passport))
    }

    // MARK: - Multiple Flag States

    func testCaymanIslandsRequirements() {
        let docs = FlagStateRequirements.required(flag: "Cayman Islands", vesselType: .megayachtCharter, rank: .captain)
        XCTAssertFalse(docs.isEmpty, "Cayman should have requirements")
    }

    func testUKRedEnsignRequirements() {
        let docs = FlagStateRequirements.required(flag: "United Kingdom", vesselType: .megayachtCharter, rank: .captain)
        XCTAssertFalse(docs.isEmpty, "UK should have requirements")
    }

    func testMarshallIslandsRequirements() {
        let vesselDocs = FlagStateRequirements.requiredVesselDocs(
            flag: "Marshall Islands", vesselType: .megayachtCharter,
            grossTonnage: 500, lengthOverall: 45, registeredLength: 40, yearBuilt: 2020
        )
        XCTAssertFalse(vesselDocs.isEmpty, "Marshall Islands should have vessel doc requirements")
    }
}
