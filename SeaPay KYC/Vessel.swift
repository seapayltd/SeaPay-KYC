//
//  Vessel.swift
//  OceanCheck
//
//  Full vessel record — all fields from Certificate of Registry.
//

import Foundation

struct Vessel: Identifiable, Codable, Hashable {
    let id: String
    // Identity
    var name: String
    var imoNumber: String
    var officialNumber: String
    var callSign: String
    var flagState: String
    var portOfRegistry: String
    var vesselType: VesselType?
    var certificateNumber: String

    // Construction
    var builder: String          // "Sunseeker Boats Ltd, Poole, Dorset, UK"
    var yearBuilt: String        // "2018"
    var hullMaterial: String     // "GRP", "Steel", "Aluminium"
    var vesselDescription: String // "Pleasure Yacht", "Commercial Yacht", "Oil Tanker"

    // Dimensions (metres)
    var lengthOverall: String
    var registeredLength: String  // Per IMO: 96% of waterline at 85% moulded depth — used by Malta
    var breadth: String
    var depth: String
    var draught: String

    // Tonnage
    var grossTonnage: String
    var netTonnage: String

    // Propulsion
    var propulsionType: String   // "Motor Ship", "Sailing Vessel"
    var engineDescription: String // "Two Internal Combustion Diesel"
    var engineMaker: String      // "MAN Truck & Bus AG, Nuremberg, Germany"
    var propulsionPower: String  // "Combined KW 2835"
    var estimatedSpeed: String   // "18 knots"

    // Ownership
    var registeredOwner: String
    var ownerAddress: String

    // Dates
    var registrationDate: String
    var certificateExpiry: String

    // Photo
    var photoFilename: String?
    var ownerAccessCode: String?

    // Computed — for requirement thresholds
    var grossTonnageValue: Double? {
        Double(grossTonnage.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: " ", with: "").trimmingCharacters(in: .whitespaces))
    }

    var lengthOverallMetres: Double? {
        Double(lengthOverall.replacingOccurrences(of: "m", with: "").replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces))
    }

    var registeredLengthValue: Double? {
        Double(registeredLength.replacingOccurrences(of: "m", with: "").replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces))
    }

    /// Regulatory length: prefers registered length, falls back to LOA
    var regulatoryLength: Double? {
        registeredLengthValue ?? lengthOverallMetres
    }

    var yearBuiltValue: Int? {
        Int(yearBuilt.trimmingCharacters(in: .whitespaces))
    }

    // App data
    var documents: [CrewDocument]?
    var ownerCheckId: String?
    var managementCompanyCheckId: String?
    var ownershipStructure: OwnershipStructure?
    var historicalOwnership: [HistoricalOwnership]?
    let createdAt: Date

    init(id: String = UUID().uuidString, name: String, imoNumber: String = "", flagState: String = "", portOfRegistry: String = "", vesselType: VesselType? = nil, createdAt: Date = Date()) {
        self.id = id; self.name = name; self.imoNumber = imoNumber; self.officialNumber = ""
        self.callSign = ""; self.flagState = flagState; self.portOfRegistry = portOfRegistry
        self.vesselType = vesselType; self.certificateNumber = ""
        self.builder = ""; self.yearBuilt = ""; self.hullMaterial = ""; self.vesselDescription = ""
        self.lengthOverall = ""; self.registeredLength = ""; self.breadth = ""; self.depth = ""; self.draught = ""
        self.grossTonnage = ""; self.netTonnage = ""
        self.propulsionType = ""; self.engineDescription = ""; self.engineMaker = ""
        self.propulsionPower = ""; self.estimatedSpeed = ""
        self.registeredOwner = ""; self.ownerAddress = ""
        self.registrationDate = ""; self.certificateExpiry = ""
        self.createdAt = createdAt
    }

    // Custom decoder for backward compatibility — registeredLength may not exist in old JSON
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        imoNumber = try c.decode(String.self, forKey: .imoNumber)
        officialNumber = try c.decode(String.self, forKey: .officialNumber)
        callSign = try c.decode(String.self, forKey: .callSign)
        flagState = try c.decode(String.self, forKey: .flagState)
        portOfRegistry = try c.decode(String.self, forKey: .portOfRegistry)
        vesselType = try c.decodeIfPresent(VesselType.self, forKey: .vesselType)
        certificateNumber = try c.decode(String.self, forKey: .certificateNumber)
        builder = try c.decode(String.self, forKey: .builder)
        yearBuilt = try c.decode(String.self, forKey: .yearBuilt)
        hullMaterial = try c.decode(String.self, forKey: .hullMaterial)
        vesselDescription = try c.decode(String.self, forKey: .vesselDescription)
        lengthOverall = try c.decode(String.self, forKey: .lengthOverall)
        registeredLength = (try? c.decode(String.self, forKey: .registeredLength)) ?? ""  // New field — fallback
        breadth = try c.decode(String.self, forKey: .breadth)
        depth = try c.decode(String.self, forKey: .depth)
        draught = try c.decode(String.self, forKey: .draught)
        grossTonnage = try c.decode(String.self, forKey: .grossTonnage)
        netTonnage = try c.decode(String.self, forKey: .netTonnage)
        propulsionType = try c.decode(String.self, forKey: .propulsionType)
        engineDescription = try c.decode(String.self, forKey: .engineDescription)
        engineMaker = try c.decode(String.self, forKey: .engineMaker)
        propulsionPower = try c.decode(String.self, forKey: .propulsionPower)
        estimatedSpeed = try c.decode(String.self, forKey: .estimatedSpeed)
        registeredOwner = try c.decode(String.self, forKey: .registeredOwner)
        ownerAddress = try c.decode(String.self, forKey: .ownerAddress)
        registrationDate = try c.decode(String.self, forKey: .registrationDate)
        certificateExpiry = try c.decode(String.self, forKey: .certificateExpiry)
        photoFilename = try c.decodeIfPresent(String.self, forKey: .photoFilename)
        ownerAccessCode = try c.decodeIfPresent(String.self, forKey: .ownerAccessCode)
        documents = try c.decodeIfPresent([CrewDocument].self, forKey: .documents)
        ownerCheckId = try c.decodeIfPresent(String.self, forKey: .ownerCheckId)
        managementCompanyCheckId = try c.decodeIfPresent(String.self, forKey: .managementCompanyCheckId)
        ownershipStructure = try c.decodeIfPresent(OwnershipStructure.self, forKey: .ownershipStructure)
        historicalOwnership = try c.decodeIfPresent([HistoricalOwnership].self, forKey: .historicalOwnership)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
    }
}

// MARK: - UBO Ownership Models

enum OwnershipEntityType: String, Codable, CaseIterable, Identifiable {
    case company = "Company"
    case trust = "Trust"
    case partnership = "Partnership"
    case soleProprietorship = "Sole Proprietorship"
    case foundation = "Foundation"
    var id: String { rawValue }
}

struct OwnershipStructure: Codable, Hashable {
    var isDirectOwnership: Bool
    var entityType: OwnershipEntityType?  // nil = company (backward compat)
    var spv: SPVEntity?
    var shareholders: [Shareholder]
    var directors: [Director]
    var uboReportGenerated: Bool = false
    // Trust-specific
    var trustees: [Shareholder]?
    var settlors: [Shareholder]?
    var protectors: [Shareholder]?
    var beneficiaries: [Shareholder]?
    var beneficiaryClass: String?  // For class beneficiaries not yet determinable

    var resolvedEntityType: OwnershipEntityType { entityType ?? .company }
}

struct SPVEntity: Codable, Hashable {
    var name: String
    var jurisdiction: String
    var registrationNumber: String
    var incorporationDate: String
    var documentPaths: [String]
}

struct Shareholder: Codable, Hashable, Identifiable {
    let id: String
    var name: String
    var ownershipPercent: Double
    var isCompany: Bool
    var checkId: String?
    var subCompany: SPVEntity?
    var subShareholders: [Shareholder]?
    var isUBO: Bool { ownershipPercent >= 25.0 && !isCompany }

    init(id: String = UUID().uuidString, name: String = "", ownershipPercent: Double = 0, isCompany: Bool = false) {
        self.id = id; self.name = name; self.ownershipPercent = ownershipPercent; self.isCompany = isCompany
    }
}

struct Director: Codable, Hashable, Identifiable {
    let id: String
    var name: String
    var checkId: String?

    init(id: String = UUID().uuidString, name: String = "") {
        self.id = id; self.name = name
    }
}

// MARK: - Historical Ownership (for vessel sale/transfer records)

struct HistoricalOwnership: Codable, Hashable {
    var structure: OwnershipStructure
    var transferDate: Date
    var scenario: String
    var previousOwner: String
}
