//
//  XLSXExporter.swift
//  OceanCheck
//
//  Generates .xlsx files (Open XML Spreadsheet) without external dependencies.
//  An xlsx is a ZIP of XML files following the ECMA-376 standard.
//

import Foundation

enum XLSXExporter {

    // MARK: - Public API

    /// Generate a multi-sheet XLSX workbook with crew, vessels, and documents.
    static func generateWorkbook(checks: [KYCCheck], vessels: [Vessel]) -> URL? {
        let dateFmt = DateFormatter(); dateFmt.dateFormat = "yyyy-MM-dd"

        // Build sheets
        let crewSheet = buildCrewSheet(checks: checks, vessels: vessels, dateFmt: dateFmt)
        let vesselSheet = buildVesselSheet(vessels: vessels, dateFmt: dateFmt)
        let docSheet = buildDocumentSheet(checks: checks, vessels: vessels, dateFmt: dateFmt)

        let sheets = [
            ("Crew", crewSheet),
            ("Vessels", vesselSheet),
            ("Documents", docSheet)
        ]

        return assembleXLSX(sheets: sheets)
    }

    // MARK: - Sheet Builders

    private static func buildCrewSheet(checks: [KYCCheck], vessels: [Vessel], dateFmt: DateFormatter) -> [[String]] {
        let vesselMap = Dictionary(uniqueKeysWithValues: vessels.map { ($0.id, $0.name) })
        var rows: [[String]] = []

        rows.append(["Name", "Entity Type", "Rank", "Vessel", "Status", "Nationality", "Date of Birth", "Document No.", "ID Expiry", "AML Status", "Review"])

        let sorted = checks.sorted { ($0.entityType.category == .crew ? 0 : 1) < ($1.entityType.category == .crew ? 0 : 1) }
        for check in sorted {
            rows.append([
                check.displayName,
                check.entityType.rawValue,
                check.crewRank?.rawValue ?? "",
                check.vesselId.flatMap { vesselMap[$0] } ?? "Unassigned",
                check.status.rawValue,
                check.nationality ?? "",
                check.dateOfBirth ?? "",
                check.documentNumber ?? "",
                check.expiryDate ?? "",
                check.amlStatus ?? "",
                check.reviewDecision?.rawValue ?? ""
            ])
        }
        return rows
    }

    private static func buildVesselSheet(vessels: [Vessel], dateFmt: DateFormatter) -> [[String]] {
        var rows: [[String]] = []

        rows.append(["Name", "IMO Number", "Flag State", "Port of Registry", "Type", "Gross Tonnage", "LOA (m)", "Year Built", "Owner", "Cert Count", "Cert Expiring", "Cert Expired"])

        for vessel in vessels {
            let docs = (vessel.documents ?? []).filter { !$0.isArchived }
            let now = Date()
            let cutoff = Calendar.current.date(byAdding: .day, value: 90, to: now) ?? now
            let expiring = docs.filter { ($0.expiryDate ?? .distantFuture) > now && ($0.expiryDate ?? .distantFuture) <= cutoff }.count
            let expired = docs.filter { ($0.expiryDate ?? .distantFuture) < now }.count

            rows.append([
                vessel.name,
                vessel.imoNumber,
                vessel.flagState,
                vessel.portOfRegistry,
                vessel.vesselType?.rawValue ?? "",
                vessel.grossTonnage,
                vessel.lengthOverall,
                vessel.yearBuilt,
                vessel.registeredOwner,
                "\(docs.count)",
                "\(expiring)",
                "\(expired)"
            ])
        }
        return rows
    }

    private static func buildDocumentSheet(checks: [KYCCheck], vessels: [Vessel], dateFmt: DateFormatter) -> [[String]] {
        var rows: [[String]] = []

        rows.append(["Owner", "Document Type", "Document No.", "Issue Date", "Expiry Date", "Status", "Issuing Authority"])

        // Crew documents
        for check in checks {
            for doc in check.documents ?? [] where !doc.isArchived {
                rows.append([
                    check.displayName,
                    doc.type.displayName,
                    doc.documentNumber ?? "",
                    doc.issueDate.map { dateFmt.string(from: $0) } ?? "",
                    doc.expiryDate.map { dateFmt.string(from: $0) } ?? "",
                    doc.statusLabel,
                    doc.issuingAuthority ?? ""
                ])
            }
        }

        // Vessel certificates
        for vessel in vessels {
            for doc in vessel.documents ?? [] where !doc.isArchived {
                rows.append([
                    vessel.name,
                    doc.displayName,
                    doc.documentNumber ?? "",
                    doc.issueDate.map { dateFmt.string(from: $0) } ?? "",
                    doc.expiryDate.map { dateFmt.string(from: $0) } ?? "",
                    doc.statusLabel,
                    doc.issuingAuthority ?? ""
                ])
            }
        }
        return rows
    }

    // MARK: - XLSX Assembly (Open XML)

    private static func assembleXLSX(sheets: [(name: String, rows: [[String]])]) -> URL? {
        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory.appendingPathComponent("xlsx_\(UUID().uuidString.prefix(8))")
        try? fm.removeItem(at: tmpDir)

        let xlDir = tmpDir.appendingPathComponent("xl")
        let wsDir = xlDir.appendingPathComponent("worksheets")
        let relsRoot = tmpDir.appendingPathComponent("_rels")
        let relsXL = xlDir.appendingPathComponent("_rels")

        for d in [tmpDir, xlDir, wsDir, relsRoot, relsXL] {
            try? fm.createDirectory(at: d, withIntermediateDirectories: true)
        }

        // [Content_Types].xml
        var ctOverrides = ""
        for (i, _) in sheets.enumerated() {
            ctOverrides += #"<Override PartName="/xl/worksheets/sheet\#(i+1).xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>"#
        }
        let contentTypes = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="xml" ContentType="application/xml"/>
        <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
        <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
        <Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>
        \(ctOverrides)
        </Types>
        """
        try? contentTypes.write(to: tmpDir.appendingPathComponent("[Content_Types].xml"), atomically: true, encoding: .utf8)

        // _rels/.rels
        let rootRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
        </Relationships>
        """
        try? rootRels.write(to: relsRoot.appendingPathComponent(".rels"), atomically: true, encoding: .utf8)

        // Collect shared strings
        var stringTable: [String] = []
        var stringIndex: [String: Int] = [:]
        for (_, rows) in sheets {
            for row in rows {
                for cell in row {
                    if stringIndex[cell] == nil {
                        stringIndex[cell] = stringTable.count
                        stringTable.append(cell)
                    }
                }
            }
        }

        // xl/sharedStrings.xml
        var ssXML = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="\#(stringTable.count)" uniqueCount="\#(stringTable.count)">"#
        for s in stringTable {
            ssXML += "<si><t>\(xmlEscape(s))</t></si>"
        }
        ssXML += "</sst>"
        try? ssXML.write(to: xlDir.appendingPathComponent("sharedStrings.xml"), atomically: true, encoding: .utf8)

        // xl/styles.xml (header bold + alternating row fill)
        let styles = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>
        <fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FFE8E8E8"/></patternFill></fill></fills>
        <borders count="1"><border/></borders>
        <cellStyleXfs count="1"><xf/></cellStyleXfs>
        <cellXfs count="3"><xf/><xf fontId="1" applyFont="1"/><xf fillId="2" applyFill="1"/></cellXfs>
        </styleSheet>
        """
        try? styles.write(to: xlDir.appendingPathComponent("styles.xml"), atomically: true, encoding: .utf8)

        // xl/workbook.xml
        var wbSheets = ""
        var wbRels = ""
        for (i, sheet) in sheets.enumerated() {
            wbSheets += #"<sheet name="\#(xmlEscape(sheet.name))" sheetId="\#(i+1)" r:id="rId\#(i+2)"/>"#
            wbRels += #"<Relationship Id="rId\#(i+2)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet\#(i+1).xml"/>"#
        }
        wbRels += #"<Relationship Id="rId\#(sheets.count+2)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>"#
        wbRels += #"<Relationship Id="rId\#(sheets.count+3)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/>"#

        let workbook = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <sheets>\(wbSheets)</sheets>
        </workbook>
        """
        try? workbook.write(to: xlDir.appendingPathComponent("workbook.xml"), atomically: true, encoding: .utf8)

        let xlRelsXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        \(wbRels)
        </Relationships>
        """
        try? xlRelsXML.write(to: relsXL.appendingPathComponent("workbook.xml.rels"), atomically: true, encoding: .utf8)

        // xl/worksheets/sheetN.xml
        for (i, sheet) in sheets.enumerated() {
            var xml = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>"#
            for (r, row) in sheet.rows.enumerated() {
                let rowNum = r + 1
                xml += #"<row r="\#(rowNum)">"#
                for (c, cell) in row.enumerated() {
                    let col = columnLetter(c)
                    let ref = "\(col)\(rowNum)"
                    let si = stringIndex[cell] ?? 0
                    let style = r == 0 ? #" s="1""# : (r % 2 == 0 ? #" s="2""# : "")
                    xml += #"<c r="\#(ref)" t="s"\#(style)><v>\#(si)</v></c>"#
                }
                xml += "</row>"
            }
            xml += "</sheetData></worksheet>"
            try? xml.write(to: wsDir.appendingPathComponent("sheet\(i+1).xml"), atomically: true, encoding: .utf8)
        }

        // ZIP it
        let xlsxURL = fm.temporaryDirectory.appendingPathComponent("OceanCheck_Export_\(Date().formatted(.iso8601.year().month().day())).xlsx")
        try? fm.removeItem(at: xlsxURL)
        var error: NSError?
        var success = false
        NSFileCoordinator().coordinate(readingItemAt: tmpDir, options: .forUploading, error: &error) { zipURL in
            try? fm.copyItem(at: zipURL, to: xlsxURL)
            success = true
        }
        try? fm.removeItem(at: tmpDir)
        return success ? xlsxURL : nil
    }

    // MARK: - Helpers

    private static func columnLetter(_ index: Int) -> String {
        var n = index; var result = ""
        repeat {
            result = String(UnicodeScalar(65 + n % 26)!) + result
            n = n / 26 - 1
        } while n >= 0
        return result
    }

    private static func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
