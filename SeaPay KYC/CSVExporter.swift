//
//  CSVExporter.swift
//  OceanCheck
//
//  Exports crew document status as CSV for management companies.
//

import Foundation

enum CSVExporter {

    /// Key document types to include as columns
    private static let columnTypes: [MaritimeDocType] = [
        .passport, .seamansBook, .medicalENG1, .yellowFever, .stcwBST,
        .securityAwareness, .cocDeck, .cocEngine, .gmdss, .flagEndorsement,
        .stcwLargeYacht, .survivalCraft, .advancedFirefighting, .medicalFirstAid,
        .drugAlcoholTest
    ]

    static func generateCrewCSV(checks: [KYCCheck], vessels: [Vessel]) -> String {
        let vesselMap = Dictionary(uniqueKeysWithValues: vessels.map { ($0.id, $0.name) })
        let dateFmt = DateFormatter(); dateFmt.dateFormat = "yyyy-MM-dd"

        // Header
        var header = ["Name", "Entity Type", "Rank", "Vessel", "Company", "Jurisdiction", "Ownership %", "KYC Status", "ID Expiry"]
        for dt in columnTypes {
            header.append("\(dt.displayName) Status")
            header.append("\(dt.displayName) Expiry")
        }
        var rows = [header.map { escape($0) }.joined(separator: ",")]

        // Data rows — seafarers first, then compliance
        let sorted = checks.sorted { ($0.entityType.category == .crew ? 0 : ($0.entityType.category == .shoreBased ? 1 : 2)) < ($1.entityType.category == .crew ? 0 : ($1.entityType.category == .shoreBased ? 1 : 2)) }
        for check in sorted {
            var row: [String] = [
                escape(check.displayName),
                escape(check.entityType.rawValue),
                escape(check.entityType.category == .crew ? (check.crewRank?.rawValue ?? "") : "N/A"),
                escape(check.vesselId.flatMap { vesselMap[$0] } ?? "Unassigned"),
                escape(check.companyName ?? ""),
                escape(check.jurisdiction ?? ""),
                escape(check.ownershipPercent.map { String(format: "%.0f%%", $0) } ?? ""),
                escape(check.status.rawValue),
                escape(check.expiryDate ?? "")
            ]

            let docs = check.documents ?? []
            for dt in columnTypes {
                if let doc = docs.first(where: { $0.type == dt && !$0.isArchived }) {
                    row.append(escape(doc.statusLabel))
                    row.append(escape(doc.expiryDate.map { dateFmt.string(from: $0) } ?? ""))
                } else {
                    row.append("Missing")
                    row.append("")
                }
            }
            rows.append(row.joined(separator: ","))
        }

        return rows.joined(separator: "\n")
    }

    // MARK: - IMO FAL Form 5 Crew List

    /// Generates an IMO-standard crew list (FAL Form 5 format) as CSV
    static func generateCrewList(vessel: Vessel, checks: [KYCCheck]) -> String {
        let dateFmt = DateFormatter(); dateFmt.dateFormat = "dd/MM/yyyy"
        let seafarers = checks.filter { $0.entityType.category == .crew }

        var lines: [String] = []

        // Header block — vessel information
        lines.append("IMO CREW LIST (FAL Form 5)")
        lines.append("")
        lines.append("1.1 Name of ship:,\(escape(vessel.name))")
        lines.append("1.2 IMO number:,\(escape(vessel.imoNumber))")
        lines.append("1.3 Call sign:,\(escape(vessel.callSign))")
        lines.append("1.4 Flag State:,\(escape(vessel.flagState))")
        lines.append("Port of registry:,\(escape(vessel.portOfRegistry))")
        lines.append("Gross tonnage:,\(escape(vessel.grossTonnage))")
        lines.append("Type of ship:,\(escape(vessel.vesselType?.rawValue ?? ""))")
        lines.append("Date:,\(dateFmt.string(from: Date()))")
        lines.append("")

        // Column headers per IMO FAL Form 5
        let headers = [
            "No.",
            "Family Name",
            "Given Names",
            "Rank/Rating",
            "Nationality",
            "Date of Birth",
            "Place of Birth",
            "Travel Document Type",
            "Travel Document No.",
            "Issuing Country",
            "Expiry Date"
        ]
        lines.append(headers.map { escape($0) }.joined(separator: ","))

        // Crew rows
        for (i, check) in seafarers.enumerated() {
            let nameParts = (check.extractedName ?? check.customerName).split(separator: " ", maxSplits: 1)
            let familyName = nameParts.count > 1 ? String(nameParts.last ?? "") : String(nameParts.first ?? "")
            let givenNames = nameParts.count > 1 ? String(nameParts.first ?? "") : ""

            // Find passport document for travel doc details
            let passport = (check.documents ?? []).first(where: { $0.type == .passport && !$0.isArchived })

            let row: [String] = [
                "\(i + 1)",
                escape(familyName),
                escape(givenNames),
                escape(check.crewRank?.rawValue ?? ""),
                escape(check.nationality ?? ""),
                escape(check.dateOfBirth ?? ""),
                escape(""), // place of birth — not typically extracted
                escape("Passport"),
                escape(check.documentNumber ?? passport?.documentNumber ?? ""),
                escape(passport?.issuingAuthority ?? check.nationality ?? ""),
                escape(check.expiryDate ?? (passport?.expiryDate.map { dateFmt.string(from: $0) } ?? ""))
            ]
            lines.append(row.joined(separator: ","))
        }

        // Footer
        lines.append("")
        lines.append("Total crew:,\(seafarers.count)")
        lines.append("")
        lines.append("Master's signature:,")
        lines.append("Date:,\(dateFmt.string(from: Date()))")

        return lines.joined(separator: "\n")
    }

    // MARK: - Vessel Certificate CSV

    static func generateVesselCertCSV(vessel: Vessel) -> String {
        let dateFmt = DateFormatter(); dateFmt.dateFormat = "yyyy-MM-dd"
        let docs = (vessel.documents ?? []).filter { !$0.isArchived }

        var lines: [String] = []
        lines.append("Vessel Certificate Status — \(escape(vessel.name))")
        lines.append("IMO: \(escape(vessel.imoNumber)),Flag: \(escape(vessel.flagState)),GT: \(escape(vessel.grossTonnage)),LOA: \(escape(vessel.lengthOverall)),RL: \(escape(vessel.registeredLength))")
        lines.append("")
        lines.append(["Certificate", "Category", "Status", "Document Number", "Expiry Date", "Issuing Authority"].map { escape($0) }.joined(separator: ","))

        for doc in docs {
            let row: [String] = [
                escape(doc.displayName),
                escape(doc.vesselDocType?.category.rawValue ?? "Other"),
                escape(doc.statusLabel),
                escape(doc.documentNumber ?? ""),
                escape(doc.expiryDate.map { dateFmt.string(from: $0) } ?? ""),
                escape(doc.issuingAuthority ?? "")
            ]
            lines.append(row.joined(separator: ","))
        }

        lines.append("")
        lines.append("Total certificates: \(docs.count)")
        lines.append("Valid: \(docs.filter { $0.status == .valid }.count)")
        lines.append("Expiring: \(docs.filter { $0.status == .expiringSoon }.count)")
        lines.append("Expired: \(docs.filter { $0.status == .expired }.count)")
        lines.append("Generated: \(dateFmt.string(from: Date()))")

        return lines.joined(separator: "\n")
    }

    // MARK: - Import Template

    static func generateImportTemplate() -> String {
        CSVImporter.generateTemplate()
    }

    private static func escape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
}
