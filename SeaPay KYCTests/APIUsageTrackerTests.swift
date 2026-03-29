//
//  APIUsageTrackerTests.swift
//  SeaPay KYCTests
//
//  Tests for API call tracking and cost estimation.
//

import XCTest
@testable import SeaPay_KYC

final class APIUsageTrackerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Clear any existing tracking data
        UserDefaults.standard.removeObject(forKey: "apiUsageHistory")
    }

    func testTrackIncrementsCount() {
        APIUsageTracker.track(.idScan)
        APIUsageTracker.track(.idScan)
        APIUsageTracker.track(.amlScreening)

        let today = APIUsageTracker.todayUsage()
        XCTAssertEqual(today.idScans, 2)
        XCTAssertEqual(today.amlScreenings, 1)
        XCTAssertEqual(today.totalCalls, 3)
    }

    func testTodayUsageReturnsZeroWhenEmpty() {
        let today = APIUsageTracker.todayUsage()
        XCTAssertEqual(today.totalCalls, 0)
        XCTAssertEqual(today.estimatedCost, 0)
    }

    func testCostEstimation() {
        APIUsageTracker.track(.idScan)      // $0.50
        APIUsageTracker.track(.amlScreening) // $0.30

        let today = APIUsageTracker.todayUsage()
        XCTAssertEqual(today.estimatedCost, 0.80, accuracy: 0.01)
    }

    func testLast30DaysAggregation() {
        APIUsageTracker.track(.idScan)
        APIUsageTracker.track(.claudeOCR)

        let totals = APIUsageTracker.totalLast30Days()
        XCTAssertEqual(totals.calls, 2)
        XCTAssertGreaterThan(totals.cost, 0)
    }

    func testAllCallTypes() {
        APIUsageTracker.track(.idScan)
        APIUsageTracker.track(.amlScreening)
        APIUsageTracker.track(.poaCheck)
        APIUsageTracker.track(.claudeOCR)
        APIUsageTracker.track(.session)

        let today = APIUsageTracker.todayUsage()
        XCTAssertEqual(today.idScans, 1)
        XCTAssertEqual(today.amlScreenings, 1)
        XCTAssertEqual(today.poaChecks, 1)
        XCTAssertEqual(today.claudeOCR, 1)
        XCTAssertEqual(today.sessions, 1)
        XCTAssertEqual(today.totalCalls, 5)
    }
}
