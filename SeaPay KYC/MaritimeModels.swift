//
//  MaritimeModels.swift
//  OceanCheck
//
//  Maritime document types, vessel types, crew ranks, flag state requirements.
//  Pure data — no behavior, no UI dependencies.
//

import Foundation
import SwiftUI

// MARK: - Document Categories

enum MaritimeDocCategory: String, Codable, CaseIterable, Identifiable {
    case universal = "Universal"
    case deckOfficer = "Deck Officer"
    case engineOfficer = "Engine Officer"
    case tanker = "Tanker"
    case rating = "Rating"
    case megayacht = "Megayacht"

    var id: String { rawValue }
}

// MARK: - Maritime Document Types (~30 types)

enum MaritimeDocType: String, Codable, CaseIterable, Identifiable, Hashable {
    // Universal
    case passport = "Passport / Travel Document"
    case seamansBook = "Seaman's Book"
    case medicalENG1 = "Medical Certificate (ENG1)"
    case medicalPEME = "Medical (PEME)"
    case yellowFever = "Yellow Fever Vaccination"
    case stcwBST = "Basic Safety Training (STCW A-VI/1)"
    case securityAwareness = "Security Awareness (STCW A-VI/6)"
    case seafarerEmployment = "Seafarer Employment Agreement"
    case drugAlcoholTest = "Drug & Alcohol Test"

    // Deck Officer
    case cocDeck = "COC — Deck Officer"
    case gmdss = "GMDSS Radio Operator"
    case ecdis = "ECDIS Type-Specific Training"
    case brm = "Bridge Resource Management"
    case flagEndorsement = "Flag State Endorsement"

    // Engine Officer
    case cocEngine = "COC — Engineer Officer"
    case erm = "Engine Room Resource Management"
    case highVoltage = "High Voltage Training"

    // Tanker
    case tankerFamOil = "Oil Tanker Familiarization"
    case tankerFamChemical = "Chemical Tanker Familiarization"
    case tankerFamGas = "Gas Tanker Familiarization"
    case tankerAdvOil = "Advanced Oil Tanker Operations"
    case tankerAdvChemical = "Advanced Chemical Tanker Operations"
    case tankerAdvGas = "Advanced Gas Tanker Operations"

    // Rating
    case abDeck = "Able Seafarer — Deck"
    case abEngine = "Able Seafarer — Engine"
    case survivalCraft = "Proficiency in Survival Craft"
    case advancedFirefighting = "Advanced Fire Fighting"
    case medicalFirstAid = "Medical First Aid"
    case medicalCare = "Medical Care"

    // Megayacht
    case stcwLargeYacht = "STCW for Large Yacht (LY2/LY3)"
    case pyaQualification = "PYA Qualification"
    case guestSafetyBriefing = "Guest Safety Briefing"

    // Corporate / UBO KYC
    case articlesOfAssociation = "Articles of Association"
    case certificateOfIncorporation = "Certificate of Incorporation"
    case companyRegistration = "Company Registration Certificate"
    case uboDeclaration = "UBO Declaration"
    case proofOfAddress = "Proof of Address"
    case directorID = "Director / Signatory ID"
    case corporateStructureChart = "Corporate Structure Chart"
    case registeredAgentCert = "Registered Agent Certificate"
    case financialStatements = "Audited Financial Statements"
    case signatoryAuthorization = "Signatory Authorization"

    // Other
    case other = "Other Document"

    var id: String { rawValue }
    var displayName: String { rawValue }

    var category: MaritimeDocCategory {
        switch self {
        case .passport, .seamansBook, .medicalENG1, .medicalPEME, .yellowFever, .stcwBST, .securityAwareness, .seafarerEmployment, .drugAlcoholTest:
            return .universal
        case .cocDeck, .gmdss, .ecdis, .brm, .flagEndorsement:
            return .deckOfficer
        case .cocEngine, .erm, .highVoltage:
            return .engineOfficer
        case .tankerFamOil, .tankerFamChemical, .tankerFamGas, .tankerAdvOil, .tankerAdvChemical, .tankerAdvGas:
            return .tanker
        case .abDeck, .abEngine, .survivalCraft, .advancedFirefighting, .medicalFirstAid, .medicalCare:
            return .rating
        case .stcwLargeYacht, .pyaQualification, .guestSafetyBriefing:
            return .megayacht
        case .articlesOfAssociation, .certificateOfIncorporation, .companyRegistration,
             .uboDeclaration, .proofOfAddress, .directorID, .corporateStructureChart,
             .registeredAgentCert, .financialStatements, .signatoryAuthorization:
            return .universal
        case .other:
            return .universal
        }
    }

    var icon: String {
        switch self {
        case .passport: return "book.closed"
        case .seamansBook: return "text.book.closed"
        case .medicalENG1, .medicalPEME: return "cross.case"
        case .yellowFever: return "syringe"
        case .stcwBST: return "lifepreserver"
        case .securityAwareness: return "shield.checkered"
        case .seafarerEmployment: return "doc.text"
        case .drugAlcoholTest: return "flask"
        case .cocDeck, .cocEngine: return "scroll"
        case .gmdss: return "antenna.radiowaves.left.and.right"
        case .ecdis: return "map"
        case .brm, .erm: return "person.3"
        case .flagEndorsement: return "flag"
        case .highVoltage: return "bolt"
        case .tankerFamOil, .tankerAdvOil: return "drop.triangle"
        case .tankerFamChemical, .tankerAdvChemical: return "testtube.2"
        case .tankerFamGas, .tankerAdvGas: return "flame"
        case .abDeck: return "helm"
        case .abEngine: return "wrench.and.screwdriver"
        case .survivalCraft: return "ferry"
        case .advancedFirefighting: return "flame.circle"
        case .medicalFirstAid, .medicalCare: return "staroflife"
        case .stcwLargeYacht: return "sailboat"
        case .pyaQualification: return "star"
        case .guestSafetyBriefing: return "person.badge.shield.checkmark"
        case .articlesOfAssociation: return "doc.text.magnifyingglass"
        case .certificateOfIncorporation: return "building.columns"
        case .companyRegistration: return "number"
        case .uboDeclaration: return "person.badge.key"
        case .proofOfAddress: return "house"
        case .directorID: return "person.text.rectangle"
        case .corporateStructureChart: return "chart.bar.doc.horizontal"
        case .registeredAgentCert: return "checkmark.seal"
        case .financialStatements: return "chart.line.uptrend.xyaxis"
        case .signatoryAuthorization: return "signature"
        case .other: return "doc"
        }
    }

    /// Typical validity in months. nil = no expiry (e.g., vaccination, some certs)
    var typicalValidityMonths: Int? {
        switch self {
        case .passport: return 120
        case .medicalENG1, .medicalPEME: return 24
        case .yellowFever: return nil
        case .stcwBST, .securityAwareness, .survivalCraft, .advancedFirefighting, .medicalFirstAid, .medicalCare: return 60
        case .cocDeck, .cocEngine: return 60
        case .gmdss: return 60
        case .flagEndorsement: return 60
        case .brm, .erm, .ecdis: return 60
        case .highVoltage: return 60
        case .tankerFamOil, .tankerFamChemical, .tankerFamGas, .tankerAdvOil, .tankerAdvChemical, .tankerAdvGas: return 60
        case .stcwLargeYacht: return 60
        case .drugAlcoholTest: return 6
        case .financialStatements: return 12
        case .proofOfAddress: return 6
        default: return nil
        }
    }

    var isFlagStateSpecific: Bool {
        switch self {
        case .cocDeck, .cocEngine, .gmdss, .flagEndorsement: return true
        default: return false
        }
    }
}

// MARK: - Vessel Type

enum VesselType: String, Codable, CaseIterable, Identifiable {
    case commercialCargo = "Commercial Cargo"
    case tankerOil = "Tanker (Oil)"
    case tankerChemical = "Tanker (Chemical)"
    case tankerGas = "Tanker (Gas/LNG)"
    case passenger = "Passenger"
    case megayachtPrivate = "Megayacht (Private)"
    case megayachtCharter = "Megayacht (Charter)"
    case offshore = "Offshore"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .commercialCargo: return "shippingbox"
        case .tankerOil: return "drop.triangle"
        case .tankerChemical: return "testtube.2"
        case .tankerGas: return "flame"
        case .passenger: return "person.2"
        case .megayachtPrivate: return "sailboat"
        case .megayachtCharter: return "sailboat.fill"
        case .offshore: return "water.waves"
        }
    }

    var isMegayacht: Bool { self == .megayachtPrivate || self == .megayachtCharter }
    var isTanker: Bool { self == .tankerOil || self == .tankerChemical || self == .tankerGas }
    var isCommercial: Bool { self != .megayachtPrivate }

    /// Additional docs required by this vessel type
    var additionalDocs: [MaritimeDocType] {
        switch self {
        case .tankerOil: return [.tankerFamOil, .tankerAdvOil]
        case .tankerChemical: return [.tankerFamChemical, .tankerAdvChemical]
        case .tankerGas: return [.tankerFamGas, .tankerAdvGas]
        case .megayachtPrivate: return [.stcwLargeYacht, .guestSafetyBriefing]
        case .megayachtCharter: return [.stcwLargeYacht, .pyaQualification, .guestSafetyBriefing]
        case .passenger: return [.advancedFirefighting, .medicalCare]
        default: return []
        }
    }
}

// MARK: - Crew Rank

enum CrewRank: String, Codable, CaseIterable, Identifiable {
    case master = "Master"
    case chiefOfficer = "Chief Officer"
    case secondOfficer = "2nd Officer"
    case thirdOfficer = "3rd Officer"
    case chiefEngineer = "Chief Engineer"
    case secondEngineer = "2nd Engineer"
    case thirdEngineer = "3rd Engineer"
    case eto = "ETO"
    case bosun = "Bosun"
    case ab = "AB"
    case os = "OS"
    case motorman = "Motorman"
    case oiler = "Oiler"
    case cook = "Cook"
    case steward = "Steward/ess"
    case deckhand = "Deckhand"

    var id: String { rawValue }

    var category: RankCategory {
        switch self {
        case .master, .chiefOfficer, .secondOfficer, .thirdOfficer: return .officerDeck
        case .chiefEngineer, .secondEngineer, .thirdEngineer, .eto: return .officerEngine
        case .bosun, .ab, .os, .deckhand: return .ratingDeck
        case .motorman, .oiler: return .ratingEngine
        case .cook, .steward: return .hospitality
        }
    }

    enum RankCategory: String, Codable {
        case officerDeck = "Deck Officer"
        case officerEngine = "Engine Officer"
        case ratingDeck = "Deck Rating"
        case ratingEngine = "Engine Rating"
        case hospitality = "Hospitality"

        /// Documents required by this rank category
        var requiredDocs: [MaritimeDocType] {
            switch self {
            case .officerDeck:
                return [.cocDeck, .gmdss, .ecdis, .brm, .flagEndorsement]
            case .officerEngine:
                return [.cocEngine, .erm, .highVoltage, .flagEndorsement]
            case .ratingDeck:
                return [.abDeck, .survivalCraft]
            case .ratingEngine:
                return [.abEngine, .survivalCraft]
            case .hospitality:
                return [.medicalFirstAid]
            }
        }
    }
}

// MARK: - Vessel Document Types

enum VesselDocType: String, Codable, CaseIterable, Identifiable, Hashable {
    case classCertificate = "Class Certificate"
    case smc = "Safety Management Certificate (SMC)"
    case ismDOC = "ISM Document of Compliance"
    case iopp = "IOPP Certificate"
    case internationalTonnage = "International Tonnage Certificate"
    case cargoShipSafety = "Cargo Ship Safety Certificate"
    case loadLine = "International Load Line Certificate"
    case radioSafety = "Radio Safety Certificate"
    case civilLiability = "Civil Liability Certificate (CLC)"
    case wreckRemoval = "Wreck Removal Certificate"
    case minimumSafeManning = "Minimum Safe Manning Document"
    case insuranceCertificate = "P&I Insurance Certificate"
    case other = "Other Vessel Certificate"

    var id: String { rawValue }
    var displayName: String { rawValue }

    var icon: String {
        switch self {
        case .classCertificate: return "checkmark.seal"
        case .smc: return "shield.checkered"
        case .ismDOC: return "doc.badge.gearshape"
        case .iopp: return "drop.triangle"
        case .internationalTonnage: return "scalemass"
        case .cargoShipSafety: return "shippingbox"
        case .loadLine: return "ruler"
        case .radioSafety: return "antenna.radiowaves.left.and.right"
        case .civilLiability: return "banknote"
        case .wreckRemoval: return "exclamationmark.triangle"
        case .minimumSafeManning: return "person.3"
        case .insuranceCertificate: return "building.columns"
        case .other: return "doc"
        }
    }

    var typicalValidityMonths: Int? {
        switch self {
        case .classCertificate: return 60
        case .smc, .ismDOC: return 60
        case .iopp, .cargoShipSafety, .loadLine, .radioSafety: return 60
        case .civilLiability, .wreckRemoval: return 12
        case .insuranceCertificate: return 12
        default: return nil
        }
    }
}

// MARK: - Crew / Vessel Document

struct CrewDocument: Identifiable, Codable, Hashable {
    let id: String
    var type: MaritimeDocType
    var vesselDocType: VesselDocType?
    var imagePaths: [String]
    var documentNumber: String?
    var issueDate: Date?
    var expiryDate: Date?
    var issuingAuthority: String?
    var notes: String?
    var previousVersionId: String?
    var renewedAt: Date?

    init(id: String = UUID().uuidString, type: MaritimeDocType = .other, vesselDocType: VesselDocType? = nil,
         imagePaths: [String] = [], documentNumber: String? = nil, issueDate: Date? = nil,
         expiryDate: Date? = nil, issuingAuthority: String? = nil, notes: String? = nil) {
        self.id = id; self.type = type; self.vesselDocType = vesselDocType; self.imagePaths = imagePaths
        self.documentNumber = documentNumber; self.issueDate = issueDate
        self.expiryDate = expiryDate; self.issuingAuthority = issuingAuthority; self.notes = notes
    }

    /// Display name: prefers vessel doc type if set
    var displayName: String { vesselDocType?.displayName ?? type.displayName }
    /// Icon: prefers vessel doc type if set
    var docIcon: String { vesselDocType?.icon ?? type.icon }

    var isArchived: Bool { renewedAt != nil }

    enum Status: String { case valid, expiringSoon, expired, missing }

    var status: Status {
        guard let exp = expiryDate else { return imagePaths.isEmpty ? .missing : .valid }
        if exp < Date() { return .expired }
        if exp < Calendar.current.date(byAdding: .day, value: 90, to: Date())! { return .expiringSoon }
        return .valid
    }

    var statusColor: Color {
        switch status {
        case .valid: return .clear_
        case .expiringSoon: return .review
        case .expired: return .flagged
        case .missing: return Color.secondary.opacity(0.4)
        }
    }

    var statusLabel: String {
        switch status {
        case .valid: return "Valid"
        case .expiringSoon: return "Expiring"
        case .expired: return "Expired"
        case .missing: return "Missing"
        }
    }
}

// MARK: - Flag State Requirements

enum FlagStateRequirements {

    /// Required documents for corporate/UBO entities
    static func requiredForEntity(_ entityType: KYCCheck.EntityType) -> [MaritimeDocType] {
        switch entityType {
        case .seafarer:
            return [] // handled by the flag/rank-based method
        case .dpa, .fleetManager, .technicalSuper, .crewingManager:
            return [.passport, .proofOfAddress] // shore-based: ID + address verification
        case .owner:
            return [.passport, .proofOfAddress, .uboDeclaration, .corporateStructureChart]
        case .ubo:
            return [.passport, .proofOfAddress, .uboDeclaration, .corporateStructureChart, .financialStatements]
        case .managementCompany:
            return [.certificateOfIncorporation, .articlesOfAssociation, .companyRegistration,
                    .directorID, .registeredAgentCert, .signatoryAuthorization, .proofOfAddress]
        case .directorOfficer:
            return [.passport, .proofOfAddress, .directorID, .signatoryAuthorization]
        }
    }

    /// Compute the full set of required documents for a crew member.
    static func required(flag: String, vesselType: VesselType?, rank: CrewRank?) -> [MaritimeDocType] {
        var docs = Set(universalDocs)

        // Rank-based
        if let rank { docs.formUnion(rank.category.requiredDocs) }

        // Vessel-type-based
        if let vt = vesselType { docs.formUnion(vt.additionalDocs) }

        // Commercial vessels require drug & alcohol testing
        if vesselType?.isCommercial == true { docs.insert(.drugAlcoholTest) }

        // Flag-specific overrides
        let f = normalize(flag)
        if let flagDocs = flagOverrides[f] { docs.formUnion(flagDocs) }

        // Marshall Islands & Panama: always flag endorsement for officers
        if ["MHL", "PAN"].contains(f), let rank, [.officerDeck, .officerEngine].contains(rank.category) {
            docs.insert(.flagEndorsement)
        }

        // UK Red Ensign: ENG1 specifically (not PEME)
        if ["GBR", "CYM", "BMU", "GIB"].contains(f) {
            docs.remove(.medicalPEME); docs.insert(.medicalENG1)
        }

        return docs.sorted(by: { $0.displayName < $1.displayName })
    }

    // MARK: - Static Data

    private static let universalDocs: [MaritimeDocType] = [
        .passport, .seamansBook, .medicalENG1, .yellowFever, .stcwBST, .securityAwareness
    ]

    private static let flagOverrides: [String: [MaritimeDocType]] = [
        "MHL": [.flagEndorsement, .drugAlcoholTest],                    // Marshall Islands
        "CYM": [.flagEndorsement, .medicalENG1, .drugAlcoholTest],      // Cayman Islands
        "GBR": [.flagEndorsement, .medicalENG1],                        // UK
        "MLT": [.flagEndorsement, .drugAlcoholTest],                    // Malta
        "PAN": [.flagEndorsement, .seamansBook, .drugAlcoholTest],      // Panama
        "BHS": [.flagEndorsement, .drugAlcoholTest],                    // Bahamas
        "SGP": [.flagEndorsement, .drugAlcoholTest],                    // Singapore
        "LBR": [.flagEndorsement, .drugAlcoholTest],                    // Liberia
        "ITA": [.flagEndorsement],                                       // Italy
        "GRC": [.flagEndorsement],                                       // Greece
    ]

    private static func normalize(_ flag: String) -> String {
        let trimmed = flag.trimmingCharacters(in: .whitespaces).uppercased()
        // Already ISO-3? Return as-is
        if trimmed.count == 3 { return trimmed }
        // ISO-2 → ISO-3 mapping for common maritime flags
        let map: [String: String] = [
            "MH": "MHL", "KY": "CYM", "GB": "GBR", "UK": "GBR", "MT": "MLT",
            "PA": "PAN", "BS": "BHS", "SG": "SGP", "LR": "LBR", "IT": "ITA",
            "GR": "GRC", "BM": "BMU", "GI": "GIB", "IM": "IMN", "VG": "VGB",
            "CY": "CYP", "NL": "NLD", "NO": "NOR", "DK": "DNK", "FR": "FRA",
            "DE": "DEU", "AG": "ATG", "VC": "VCT", "JM": "JAM", "CK": "COK",
            "VU": "VUT", "HK": "HKG", "JP": "JPN", "KR": "KOR", "PW": "PLW",
            "TV": "TUV", "TO": "TON", "US": "USA", "AU": "AUS", "BR": "BRA",
            "IN": "IND", "PH": "PHL", "AE": "ARE", "SA": "SAU", "QA": "QAT",
            "TR": "TUR", "RU": "RUS", "UA": "UKR", "CN": "CHN", "TW": "TWN",
            "ID": "IDN", "MY": "MYS", "TH": "THA", "VN": "VNM", "BD": "BGD",
            "LK": "LKA", "NZ": "NZL", "ZA": "ZAF", "NG": "NGA", "KE": "KEN",
            "EG": "EGY", "MA": "MAR", "SE": "SWE", "FI": "FIN", "EE": "EST",
            "LV": "LVA", "LT": "LTU", "PL": "POL", "HR": "HRV", "BG": "BGR",
            "RO": "ROU", "PT": "PRT", "ES": "ESP", "IE": "IRL", "BE": "BEL",
            "IS": "ISL", "BB": "BRB", "BZ": "BLZ", "DM": "DMA", "TT": "TTO",
            "MX": "MEX", "AR": "ARG", "CL": "CHL", "CO": "COL", "PE": "PER",
            "GE": "GEO", "MC": "MCO", "MN": "MNG",
        ]
        return map[trimmed] ?? trimmed
    }
}
