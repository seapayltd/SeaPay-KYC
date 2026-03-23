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
        self.lengthOverall = ""; self.breadth = ""; self.depth = ""; self.draught = ""
        self.grossTonnage = ""; self.netTonnage = ""
        self.propulsionType = ""; self.engineDescription = ""; self.engineMaker = ""
        self.propulsionPower = ""; self.estimatedSpeed = ""
        self.registeredOwner = ""; self.ownerAddress = ""
        self.registrationDate = ""; self.certificateExpiry = ""
        self.createdAt = createdAt
    }
}

// MARK: - UBO Ownership Models

struct OwnershipStructure: Codable, Hashable {
    var isDirectOwnership: Bool
    var spv: SPVEntity?
    var shareholders: [Shareholder]
    var directors: [Director]
    var uboReportGenerated: Bool = false
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
