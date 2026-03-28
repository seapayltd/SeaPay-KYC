//
//  CSVImporter.swift
//  OceanCheck
//
//  Flexible CSV parser for crew and compliance data import.
//  Matches columns case-insensitively with common aliases.
//

import Foundation

enum CSVImporter {

    // MARK: - Parsed Data

    struct ParsedRow: Identifiable {
        let id = UUID().uuidString
        var name: String
        var rank: CrewRank?
        var nationality: String?
        var dateOfBirth: String?
        var passportNumber: String?
        var passportExpiry: String?
        var entityType: KYCCheck.EntityType
        var companyName: String?
        var jurisdiction: String?
        var ownershipPercent: Double?
        var warning: String?

        var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    struct ParseResult {
        var rows: [ParsedRow]
        var errors: [String]
        var skippedCount: Int
        var crewCount: Int { rows.filter { $0.entityType == .seafarer }.count }
        var complianceCount: Int { rows.filter { $0.entityType.category == .ownership }.count }
        var shoreBasedCount: Int { rows.filter { $0.entityType.category == .shoreBased }.count }
    }

    // MARK: - Column Mapping

    private enum Column: String {
        case name, rank, nationality, dob, passportNumber, passportExpiry, entityType, company, jurisdiction, ownership
    }

    private static let columnAliases: [String: Column] = {
        var map: [String: Column] = [:]
        let aliases: [(Column, [String])] = [
            (.name, ["name", "full name", "crew name", "person", "full_name", "crew_name"]),
            (.rank, ["rank", "position", "rating", "role", "rank/rating"]),
            (.nationality, ["nationality", "nation", "country", "nat"]),
            (.dob, ["dob", "date of birth", "birth date", "birthdate", "date_of_birth"]),
            (.passportNumber, ["passport", "passport number", "doc number", "travel doc", "passport_number", "document number", "travel document no.", "travel document no"]),
            (.passportExpiry, ["expiry", "passport expiry", "doc expiry", "expiry date", "passport_expiry", "expiry_date"]),
            (.entityType, ["type", "entity type", "category", "entity_type"]),
            (.company, ["company", "company name", "organization", "organisation", "company_name"]),
            (.jurisdiction, ["jurisdiction", "country of registration", "registered country"]),
            (.ownership, ["ownership", "ownership %", "ownership%", "ownership_percent", "share", "shares"]),
        ]
        for (col, names) in aliases {
            for alias in names { map[alias] = col }
        }
        return map
    }()

    // MARK: - Rank Mapping

    private static let rankAliases: [String: CrewRank] = {
        var map: [String: CrewRank] = [:]
        // Exact matches (case-insensitive)
        for rank in CrewRank.allCases {
            map[rank.rawValue.lowercased()] = rank
        }
        // Common abbreviations
        let extras: [(String, CrewRank)] = [
            ("capt", .captain), ("captain", .captain),
            ("c/o", .chiefOfficer), ("1/o", .chiefOfficer), ("1st officer", .chiefOfficer),
            ("2/o", .secondOfficer), ("second officer", .secondOfficer),
            ("3/o", .thirdOfficer), ("third officer", .thirdOfficer),
            ("c/e", .chiefEngineer), ("chief eng", .chiefEngineer),
            ("2/e", .secondEngineer), ("second engineer", .secondEngineer),
            ("3/e", .thirdEngineer), ("third engineer", .thirdEngineer),
            ("bos'n", .bosun), ("boatswain", .bosun),
            ("o/s", .os), ("ordinary seaman", .os),
            ("a/b", .ab), ("able seaman", .ab),
            ("stew", .steward), ("stewardess", .steward), ("chief stew", .chiefStewardess),
            ("deckhand", .deckhand), ("dh", .deckhand),
        ]
        for (alias, rank) in extras { map[alias] = rank }
        return map
    }()

    // MARK: - Entity Type Mapping

    private static func mapEntityType(_ value: String) -> KYCCheck.EntityType {
        let lower = value.lowercased().trimmingCharacters(in: .whitespaces)
        switch lower {
        case "", "crew", "seafarer": return .seafarer
        case "dpa", "designated person ashore": return .dpa
        case "fleet manager": return .fleetManager
        case "technical superintendent", "tech supt": return .technicalSuper
        case "crewing manager": return .crewingManager
        case "shore-based", "shore based": return .dpa // default shore-based
        case "owner": return .owner
        case "ubo", "beneficial owner": return .ubo
        case "management company", "management": return .managementCompany
        case "director", "director/officer": return .directorOfficer
        default: return .seafarer
        }
    }

    // MARK: - Parse

    static func parse(csv: String) -> ParseResult {
        var rows: [ParsedRow] = []
        var errors: [String] = []
        var skipped = 0

        let lines = csv.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count > 1 else {
            return ParseResult(rows: [], errors: ["File is empty or has no data rows"], skippedCount: 0)
        }

        // Parse header
        let headerFields = parseCSVLine(lines[0])
        var columnMap: [Column: Int] = [:]
        for (i, field) in headerFields.enumerated() {
            let key = field.lowercased().trimmingCharacters(in: .whitespaces)
            if let col = columnAliases[key] {
                columnMap[col] = i
            }
        }

        guard columnMap[.name] != nil else {
            return ParseResult(rows: [], errors: ["No 'Name' column found. Expected columns: Name, Rank, Nationality, etc."], skippedCount: 0)
        }

        // Parse data rows
        for lineIdx in 1..<lines.count {
            let fields = parseCSVLine(lines[lineIdx])
            let rowNum = lineIdx + 1

            func field(_ col: Column) -> String? {
                guard let idx = columnMap[col], idx < fields.count else { return nil }
                let v = fields[idx].trimmingCharacters(in: .whitespaces)
                return v.isEmpty ? nil : v
            }

            guard let name = field(.name), !name.isEmpty else {
                errors.append("Row \(rowNum): missing name — skipped")
                skipped += 1
                continue
            }

            let entityType = mapEntityType(field(.entityType) ?? "")
            var warning: String?

            // Parse rank
            var rank: CrewRank?
            if let rankStr = field(.rank) {
                rank = rankAliases[rankStr.lowercased()]
                if rank == nil && entityType == .seafarer {
                    warning = "Unknown rank '\(rankStr)'"
                }
            }

            rows.append(ParsedRow(
                name: name,
                rank: rank,
                nationality: field(.nationality),
                dateOfBirth: field(.dob),
                passportNumber: field(.passportNumber),
                passportExpiry: field(.passportExpiry),
                entityType: entityType,
                companyName: field(.company),
                jurisdiction: field(.jurisdiction),
                ownershipPercent: field(.ownership).flatMap { Double($0.replacingOccurrences(of: "%", with: "")) },
                warning: warning
            ))
        }

        return ParseResult(rows: rows, errors: errors, skippedCount: skipped)
    }

    static func parse(url: URL) -> ParseResult? {
        guard url.startAccessingSecurityScopedResource() else { return nil }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let data = try? Data(contentsOf: url),
              let csv = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else { return nil }
        return parse(csv: csv)
    }

    // MARK: - Template

    static func generateTemplate() -> String {
        [
            "Name,Rank,Nationality,Date of Birth,Passport Number,Passport Expiry,Entity Type,Company,Jurisdiction,Ownership %",
            "John Smith,Master,British,1985-03-15,GB123456789,2028-06-30,Crew,,,",
            "Maria Garcia,Chief Officer,Spanish,1990-07-22,ES987654321,2027-11-15,Crew,,,",
            "Hans Mueller,Chief Engineer,German,1982-01-10,DE456789012,2029-03-20,Crew,,,",
            "Jane Doe,Steward/ess,Filipino,1995-05-18,PH111222333,2026-12-01,Crew,,,",
            "Acme Holdings Ltd,,,,,,Management Company,Acme Holdings Ltd,Marshall Islands,",
            "James Wilson,,British,1970-08-12,GB999888777,2028-01-01,Owner,,,100",
        ].joined(separator: "\n")
    }

    // MARK: - CSV Line Parser (handles quoted fields)

    private static func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false

        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        fields.append(current)
        return fields
    }
}
