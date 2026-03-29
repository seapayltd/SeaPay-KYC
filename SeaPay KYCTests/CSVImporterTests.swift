//
//  CSVImporterTests.swift
//  SeaPay KYCTests
//
//  Tests for CSV parsing, column alias matching, and crew creation.
//

import XCTest
@testable import SeaPay_KYC

final class CSVImporterTests: XCTestCase {

    // MARK: - Basic Parsing

    func testParseSimpleCSV() {
        let csv = """
        Name,Rank,Nationality
        Marco Rossi,Master,Italian
        Elena Papadopoulos,Chief Officer,Greek
        """
        let rows = CSVImporter.parse(csv: csv)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].name, "Marco Rossi")
        XCTAssertEqual(rows[1].name, "Elena Papadopoulos")
    }

    func testParseWithQuotedFields() {
        let csv = """
        "Full Name","Rank","Nationality"
        "Wilson, James",Master,British
        """
        let rows = CSVImporter.parse(csv: csv)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].name, "Wilson, James")
    }

    func testParseEmptyCSV() {
        let rows = CSVImporter.parse(csv: "")
        XCTAssertTrue(rows.isEmpty)
    }

    func testParseHeaderOnly() {
        let csv = "Name,Rank,Nationality\n"
        let rows = CSVImporter.parse(csv: csv)
        XCTAssertTrue(rows.isEmpty)
    }

    // MARK: - Column Aliases

    func testRecognizesVariousNameColumns() {
        let csv1 = "Full Name,Rank\nJohn Smith,AB\n"
        let csv2 = "Crew Name,Rank\nJohn Smith,AB\n"
        let csv3 = "Seafarer,Rank\nJohn Smith,AB\n"

        XCTAssertEqual(CSVImporter.parse(csv: csv1).first?.name, "John Smith")
        XCTAssertEqual(CSVImporter.parse(csv: csv2).first?.name, "John Smith")
        XCTAssertEqual(CSVImporter.parse(csv: csv3).first?.name, "John Smith")
    }

    // MARK: - Rank Mapping

    func testMapsRankStrings() {
        let csv = "Name,Rank\nTest,Master\nTest2,Chief Engineer\nTest3,AB\n"
        let rows = CSVImporter.parse(csv: csv)
        XCTAssertEqual(rows[0].rank, .captain)
        XCTAssertEqual(rows[1].rank, .chiefEngineer)
        XCTAssertEqual(rows[2].rank, .ab)
    }

    // MARK: - Validity

    func testRowWithNoNameIsInvalid() {
        let csv = "Name,Rank\n,AB\n"
        let rows = CSVImporter.parse(csv: csv)
        XCTAssertTrue(rows.isEmpty || !rows[0].isValid)
    }

    // MARK: - Template

    func testGenerateTemplateHasHeaders() {
        let template = CSVImporter.generateTemplate()
        XCTAssertTrue(template.hasPrefix("Name,"))
        XCTAssertTrue(template.contains("Rank"))
        XCTAssertTrue(template.contains("Nationality"))
    }
}
