//
//  GDPRServiceTests.swift
//  SeaPay KYCTests
//
//  Tests for GDPR compliance: consent, retention, DSAR export.
//

import XCTest
@testable import SeaPay_KYC

final class GDPRServiceTests: XCTestCase {

    // MARK: - Consent

    func testRecordConsent() {
        var records: [ConsentRecord] = []
        GDPRService.recordConsent(subjectName: "John Smith", checkId: "check-1",
            types: [.identityVerification, .amlScreening], store: &records)

        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records[0].subjectName, "John Smith")
        XCTAssertEqual(records[0].consentType, .identityVerification)
        XCTAssertTrue(records[0].isActive)
        XCTAssertEqual(records[1].consentType, .amlScreening)
    }

    func testWithdrawConsent() {
        var records: [ConsentRecord] = []
        GDPRService.recordConsent(subjectName: "John", checkId: "c1", types: [.dataProcessing], store: &records)
        let id = records[0].id

        GDPRService.withdrawConsent(recordId: id, store: &records)
        XCTAssertFalse(records[0].isActive)
        XCTAssertNotNil(records[0].withdrawnAt)
    }

    // MARK: - Retention

    func testFlaggedForRetention() {
        let oldCheck = KYCCheck(
            id: "old", customerId: "C1", customerName: "Old Person",
            agentId: "A", agentName: "Agent", checkType: .idVerification,
            status: .passed, entityType: .seafarer,
            createdAt: Calendar.current.date(byAdding: .year, value: -6, to: Date())!
        )
        let recentCheck = KYCCheck(
            id: "new", customerId: "C2", customerName: "New Person",
            agentId: "A", agentName: "Agent", checkType: .idVerification,
            status: .passed, entityType: .seafarer,
            createdAt: Date()
        )

        let policy = RetentionPolicy(retentionYears: 5, autoFlagExpired: true, autoDeleteExpired: false)
        let flagged = GDPRService.flaggedForRetention(checks: [oldCheck, recentCheck], policy: policy)

        XCTAssertEqual(flagged.count, 1)
        XCTAssertEqual(flagged[0].id, "old")
    }

    func testRetentionNotFlaggedWhenDisabled() {
        let oldCheck = KYCCheck(
            id: "old", customerId: "C1", customerName: "Old",
            agentId: "A", agentName: "Agent", checkType: .idVerification,
            status: .passed, entityType: .seafarer,
            createdAt: Calendar.current.date(byAdding: .year, value: -10, to: Date())!
        )

        let policy = RetentionPolicy(retentionYears: 5, autoFlagExpired: false, autoDeleteExpired: false)
        let flagged = GDPRService.flaggedForRetention(checks: [oldCheck], policy: policy)
        XCTAssertTrue(flagged.isEmpty, "Should not flag when autoFlagExpired is false")
    }

    // MARK: - DSAR Export

    func testDSARExportGeneratesFile() {
        let check = KYCCheck(
            id: "dsar-1", customerId: "C1", customerName: "Jane Doe",
            agentId: "A", agentName: "Agent", checkType: .idVerification,
            status: .passed, entityType: .seafarer, createdAt: Date()
        )

        let url = GDPRService.exportSubjectData(
            name: "Jane", checks: [check], vessels: [],
            consentRecords: [], auditLog: []
        )
        defer { if let u = url { try? FileManager.default.removeItem(at: u) } }

        XCTAssertNotNil(url, "Should generate export file")
        if let url {
            let data = try? Data(contentsOf: url)
            XCTAssertNotNil(data)
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            XCTAssertEqual(json?["subjectName"] as? String, "Jane")
            XCTAssertEqual(json?["exportType"] as? String, "GDPR Data Subject Access Request")
        }
    }

    func testDSARExportReturnsNilForNoMatch() {
        let check = KYCCheck(
            id: "1", customerId: "C1", customerName: "Marco Rossi",
            agentId: "A", agentName: "Agent", checkType: .idVerification,
            status: .passed, entityType: .seafarer, createdAt: Date()
        )

        let url = GDPRService.exportSubjectData(
            name: "Nonexistent Person", checks: [check], vessels: [],
            consentRecords: [], auditLog: []
        )
        XCTAssertNil(url, "Should return nil when no records match")
    }
}
