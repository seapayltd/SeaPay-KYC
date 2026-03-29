//
//  KYCCheckTests.swift
//  SeaPay KYCTests
//
//  Tests for KYCCheck model: Codable, entity types, status transitions.
//

import XCTest
@testable import SeaPay_KYC

final class KYCCheckTests: XCTestCase {

    private func makeCheck(
        status: KYCCheck.CheckStatus = .pending,
        entityType: KYCCheck.EntityType = .seafarer
    ) -> KYCCheck {
        KYCCheck(
            id: UUID().uuidString,
            customerId: "TEST-001",
            customerName: "Test Person",
            agentId: "AGENT-001",
            agentName: "Test Agent",
            checkType: .idVerification,
            status: status,
            entityType: entityType,
            createdAt: Date()
        )
    }

    // MARK: - Codable Round-Trip

    func testCodableRoundTrip() throws {
        var check = makeCheck()
        check.extractedName = "John Smith"
        check.documentType = "Passport"
        check.documentNumber = "AB123456"
        check.nationality = "GB"
        check.amlStatus = "Approved"
        check.amlScore = 5
        check.vesselId = "vessel-123"
        check.crewRank = .captain

        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let data = try encoder.encode(check)
        let decoded = try decoder.decode(KYCCheck.self, from: data)

        XCTAssertEqual(decoded.customerName, "Test Person")
        XCTAssertEqual(decoded.extractedName, "John Smith")
        XCTAssertEqual(decoded.documentNumber, "AB123456")
        XCTAssertEqual(decoded.nationality, "GB")
        XCTAssertEqual(decoded.amlScore, 5)
        XCTAssertEqual(decoded.crewRank, .captain)
        XCTAssertEqual(decoded.vesselId, "vessel-123")
    }

    // MARK: - Entity Type Categories

    func testCrewCategory() {
        XCTAssertEqual(KYCCheck.EntityType.seafarer.category, .crew)
    }

    func testOwnershipCategory() {
        XCTAssertEqual(KYCCheck.EntityType.owner.category, .ownership)
        XCTAssertEqual(KYCCheck.EntityType.ubo.category, .ownership)
        XCTAssertEqual(KYCCheck.EntityType.managementCompany.category, .ownership)
        XCTAssertEqual(KYCCheck.EntityType.directorOfficer.category, .ownership)
    }

    func testTrustCategories() {
        XCTAssertEqual(KYCCheck.EntityType.trustee.category, .ownership)
        XCTAssertEqual(KYCCheck.EntityType.settlor.category, .ownership)
        XCTAssertEqual(KYCCheck.EntityType.protector.category, .ownership)
        XCTAssertEqual(KYCCheck.EntityType.beneficiary.category, .ownership)
    }

    func testShoreBasedCategory() {
        XCTAssertEqual(KYCCheck.EntityType.dpa.category, .shoreBased)
        XCTAssertEqual(KYCCheck.EntityType.fleetManager.category, .shoreBased)
    }

    // MARK: - Display Name

    func testDisplayNameUsesExtractedName() {
        var check = makeCheck()
        check.extractedName = "Extracted Name"
        XCTAssertEqual(check.displayName, "Extracted Name")
    }

    func testDisplayNameFallsBackToCustomerName() {
        let check = makeCheck()
        XCTAssertEqual(check.displayName, "Test Person")
    }

    // MARK: - Review Decision

    func testReviewDecisionCodable() throws {
        var check = makeCheck()
        check.reviewDecision = .flagged
        check.reviewReason = "AML hit"
        check.reviewedAt = Date()
        check.reviewedBy = "Agent"

        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let data = try encoder.encode(check)
        let decoded = try decoder.decode(KYCCheck.self, from: data)

        XCTAssertEqual(decoded.reviewDecision, .flagged)
        XCTAssertEqual(decoded.reviewReason, "AML hit")
    }
}
