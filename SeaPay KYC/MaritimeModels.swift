//
//  MaritimeModels.swift
//  OceanCheck
//
//  Maritime document types, vessel types, crew ranks, flag state requirements.
//  Pure data — no behavior, no UI dependencies.
//

import Foundation
import SwiftUI

// MARK: - Renewal Guidance

struct RenewalInfo {
    let activity: String
    let leadTime: String
    let contactType: String
    let notes: String?

    init(_ activity: String, leadTime: String, contact: String, notes: String? = nil) {
        self.activity = activity; self.leadTime = leadTime; self.contactType = contact; self.notes = notes
    }
}

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

    // Megayacht / Yacht Crew
    case stcwLargeYacht = "STCW for Large Yacht (LY2/LY3)"
    case pyaQualification = "PYA Qualification"
    case guestSafetyBriefing = "Guest Safety Briefing"
    case yachtRatingCert = "Yacht Rating Certificate"
    case interiorCrewTraining = "Interior Crew Training Certificate"
    case ryaYachtmaster = "RYA/MCA Yachtmaster Certificate"
    case helmCert = "HELM (Human Element Leadership & Management)"
    case ssoCertificate = "Ship Security Officer (SSO) Certificate"
    case powerboatLevel2 = "Powerboat Level 2"
    case pwcProficiency = "Personal Watercraft Proficiency"
    case foodSafetyCert = "Food Safety / Ship's Cook Certificate"
    case drugAlcoholPolicy = "Drug & Alcohol Policy Acknowledgement"
    case mcaSeafarerDoc = "MCA Seafarer Documentation (SD)"

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
    // KYB — additional corporate document types
    case shareholderRegistry = "Shareholder / Member Registry"
    case uboRegistryExtract = "UBO Registry Extract"
    case certificateOfIncumbency = "Certificate of Incumbency"
    case certificateOfGoodStanding = "Certificate of Good Standing"
    case trustDeed = "Trust Deed / Agreement"
    case partnershipAgreement = "Partnership Agreement"
    case directorRegistry = "Director Registry"

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
        case .stcwLargeYacht, .pyaQualification, .guestSafetyBriefing,
             .yachtRatingCert, .interiorCrewTraining, .ryaYachtmaster, .helmCert,
             .ssoCertificate, .powerboatLevel2, .pwcProficiency, .foodSafetyCert,
             .drugAlcoholPolicy, .mcaSeafarerDoc:
            return .megayacht
        case .articlesOfAssociation, .certificateOfIncorporation, .companyRegistration,
             .uboDeclaration, .proofOfAddress, .directorID, .corporateStructureChart,
             .registeredAgentCert, .financialStatements, .signatoryAuthorization,
             .shareholderRegistry, .uboRegistryExtract, .certificateOfIncumbency,
             .certificateOfGoodStanding, .trustDeed, .partnershipAgreement, .directorRegistry:
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
        case .yachtRatingCert: return "person.badge.clock"
        case .interiorCrewTraining: return "house"
        case .ryaYachtmaster: return "helm"
        case .helmCert: return "person.3.sequence"
        case .ssoCertificate: return "lock.shield"
        case .powerboatLevel2: return "figure.sailing"
        case .pwcProficiency: return "figure.water.fitness"
        case .foodSafetyCert: return "fork.knife"
        case .drugAlcoholPolicy: return "cross.vial"
        case .mcaSeafarerDoc: return "doc.badge.gearshape"
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
        case .shareholderRegistry: return "list.bullet.rectangle"
        case .uboRegistryExtract: return "person.3"
        case .certificateOfIncumbency: return "checkmark.seal"
        case .certificateOfGoodStanding: return "checkmark.circle"
        case .trustDeed: return "doc.text.magnifyingglass"
        case .partnershipAgreement: return "person.2"
        case .directorRegistry: return "list.clipboard"
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

    var renewalInfo: RenewalInfo? {
        switch self {
        case .passport: return RenewalInfo("Apply for passport renewal", leadTime: "2-6 months", contact: "Embassy / consulate")
        case .medicalENG1: return RenewalInfo("Book ENG1 medical examination", leadTime: "2 weeks", contact: "MCA-approved medical practitioner")
        case .medicalPEME: return RenewalInfo("Book pre-employment medical exam", leadTime: "1-2 weeks", contact: "Approved medical centre")
        case .stcwBST: return RenewalInfo("Complete STCW refresher course", leadTime: "1 month", contact: "STCW training centre", notes: "Required every 5 years")
        case .securityAwareness: return RenewalInfo("Complete security awareness refresher", leadTime: "1 month", contact: "STCW training centre")
        case .cocDeck, .cocEngine: return RenewalInfo("Revalidate COC — sea service records + refresher courses", leadTime: "3-6 months", contact: "Flag state maritime authority")
        case .gmdss: return RenewalInfo("Complete GMDSS refresher course", leadTime: "1 month", contact: "Maritime training centre")
        case .flagEndorsement: return RenewalInfo("Apply to flag state for endorsement renewal", leadTime: "1-3 months", contact: "Flag state administration")
        case .drugAlcoholTest: return RenewalInfo("Schedule new drug & alcohol test", leadTime: "1 week", contact: "Approved testing facility")
        case .seamansBook: return RenewalInfo("Apply for seaman's book renewal", leadTime: "1-3 months", contact: "National maritime authority")
        case .survivalCraft: return RenewalInfo("Complete survival craft proficiency refresher", leadTime: "1 month", contact: "STCW training centre")
        case .advancedFirefighting: return RenewalInfo("Complete advanced fire fighting refresher", leadTime: "1 month", contact: "STCW training centre")
        case .foodSafetyCert: return RenewalInfo("Complete food safety / ship's cook course", leadTime: "1 week", contact: "Maritime training provider")
        case .helmCert: return RenewalInfo("Complete HELM refresher course", leadTime: "1 month", contact: "MCA-approved training centre")
        case .ryaYachtmaster: return RenewalInfo("Revalidate with sea service + first aid", leadTime: "1-2 months", contact: "RYA / MCA")
        // KYB corporate document renewals
        case .shareholderRegistry: return RenewalInfo("Request updated shareholder registry from company secretary", leadTime: "1-3 months", contact: "Company registry / secretary")
        case .uboRegistryExtract: return RenewalInfo("Request fresh UBO registry extract", leadTime: "1-2 months", contact: "National UBO registry")
        case .certificateOfIncumbency: return RenewalInfo("Request updated certificate of incumbency", leadTime: "1-2 months", contact: "Registered agent")
        case .certificateOfGoodStanding: return RenewalInfo("Request current certificate of good standing", leadTime: "1-2 months", contact: "Company registry")
        case .trustDeed: return RenewalInfo("Review trust deed for any amendments or restatements", leadTime: "1-3 months", contact: "Trustee solicitor", notes: "Trust deeds issued indefinitely — no freshness requirement")
        case .partnershipAgreement: return RenewalInfo("Review partnership agreement for amendments", leadTime: "1-3 months", contact: "Partnership solicitor", notes: "Issued indefinitely — no freshness requirement")
        case .directorRegistry: return RenewalInfo("Request updated director registry from company secretary", leadTime: "1-3 months", contact: "Company registry / secretary")
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
    // Yacht-specific
    case captain = "Captain"
    case chiefStewardess = "Chief Steward/ess"
    case purser = "Purser"
    case deckCadet = "Deck Cadet"
    case engineCadet = "Engine Cadet"

    var id: String { rawValue }

    var category: RankCategory {
        switch self {
        case .master, .chiefOfficer, .secondOfficer, .thirdOfficer, .captain: return .officerDeck
        case .chiefEngineer, .secondEngineer, .thirdEngineer, .eto: return .officerEngine
        case .bosun, .ab, .os, .deckhand, .deckCadet: return .ratingDeck
        case .motorman, .oiler, .engineCadet: return .ratingEngine
        case .cook, .steward, .chiefStewardess, .purser: return .hospitality
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

// MARK: - Vessel Document Category

enum VesselDocCategory: String, CaseIterable, Identifiable {
    case safety = "Safety (SOLAS)"
    case pollution = "Pollution (MARPOL)"
    case loadLineTonnage = "Load Line & Tonnage"
    case classification = "Classification & Survey"
    case manningLabour = "Manning & Labour"
    case insurance = "Insurance & Liability"
    case radio = "Radio & Navigation"
    case yacht = "Yacht Code"
    case other = "Other"
    var id: String { rawValue }
}

// MARK: - Vessel Document Type (38 types)

enum VesselDocType: String, Codable, CaseIterable, Identifiable, Hashable {
    // Safety (SOLAS)
    case smc = "Safety Management Certificate (SMC)"
    case ismDOC = "ISM Document of Compliance"
    case cargoShipSafety = "Cargo Ship Safety Certificate"
    case cargoShipSafetyConstruction = "Cargo Ship Safety Construction Certificate"
    case cargoShipSafetyEquipment = "Cargo Ship Safety Equipment Certificate"
    case passengerShipSafety = "Passenger Ship Safety Certificate"
    case issc = "International Ship Security Certificate (ISSC)"
    case csr = "Continuous Synopsis Record (CSR)"

    // Pollution (MARPOL)
    case iopp = "IOPP Certificate"
    case ispp = "Intl Sewage Pollution Prevention Certificate"
    case iapp = "Intl Air Pollution Prevention Certificate"
    case iee = "International Energy Efficiency Certificate"
    case ballastWater = "Ballast Water Management Certificate"

    // Load Line & Tonnage
    case loadLine = "International Load Line Certificate"
    case internationalTonnage = "International Tonnage Certificate"

    // Classification & Survey
    case classCertificate = "Class Certificate"
    case annualSurvey = "Annual Survey Report"
    case intermediateSurvey = "Intermediate Survey Report"
    case dockingSurvey = "Docking Survey Report"
    case specialSurvey = "Special Survey Report"

    // Manning & Labour
    case minimumSafeManning = "Minimum Safe Manning Document"
    case mlcCertificate = "Maritime Labour Certificate (MLC)"
    case dmlc = "Declaration of Maritime Labour Compliance"

    // Insurance & Liability
    case insuranceCertificate = "P&I Insurance Certificate"
    case hmInsurance = "Hull & Machinery Insurance Certificate"
    case civilLiability = "Civil Liability Certificate (CLC)"
    case wreckRemoval = "Wreck Removal Certificate"
    case warRisk = "War Risk Insurance Certificate"

    // Radio & Navigation
    case radioSafety = "Radio Safety Certificate"
    case shipRadioLicence = "Ship Radio Station Licence"
    case epirbRegistration = "EPIRB Registration"
    case certificateOfRegistry = "Certificate of Registry"

    // Yacht Code
    case largeYachtCode = "Large Yacht Code Compliance (LY3)"
    case commercialYachtCert = "Commercial Yacht Certificate"
    case pleasureYachtCert = "Pleasure Yacht Certificate"
    case shortRangeSafety = "Short Range Safety Certificate"

    // Yacht Safety & Stability
    case stabilityBooklet = "Stability Booklet / Inclining Experiment"
    case safetyEquipmentSurvey = "Safety Equipment Survey Certificate"
    case yachtSafetyCertificate = "Yacht Safety Certificate"

    // MARPOL Operations
    case garbageManagementPlan = "Garbage Management Plan"
    case oilRecordBook = "Oil Record Book"
    case garbageRecordBook = "Garbage Record Book"
    case sopep = "Shipboard Oil Pollution Emergency Plan (SOPEP)"

    // Navigation & Safety Equipment
    case navigationLightCert = "Navigation Light Certificate"
    case lifeRaftServiceCert = "Life Raft Service Certificate"
    case fireExtinguisherServiceCert = "Fire Extinguisher Service Certificate"
    case epirbBatteryCert = "EPIRB Battery Certificate"

    // Flag-Specific Yacht Codes
    case mcaSCVCode = "MCA Small Commercial Vessel Code (<24m)"
    case mcaLY2 = "MCA Large Yacht Code (LY2)"
    case caymanREG = "Cayman Islands REG Yacht Code Certificate"
    case maltaSYC = "Malta Superyacht Code (SYC) Certificate"
    case maltaSCV = "Malta Small Commercial Vessel Code Certificate"
    case marshallIslandsMI108 = "Marshall Islands MI-108 Yacht Code Certificate"
    case redEnsignREG = "Red Ensign Group Yacht Code (REG) Certificate"
    case passengerYachtCode = "Passenger Yacht Code (PYC) Certificate"

    case other = "Other Vessel Certificate"

    var id: String { rawValue }
    var displayName: String { rawValue }

    var category: VesselDocCategory {
        switch self {
        case .smc, .ismDOC, .cargoShipSafety, .cargoShipSafetyConstruction, .cargoShipSafetyEquipment, .passengerShipSafety, .issc, .csr,
             .stabilityBooklet, .safetyEquipmentSurvey, .navigationLightCert, .lifeRaftServiceCert, .fireExtinguisherServiceCert:
            return .safety
        case .iopp, .ispp, .iapp, .iee, .ballastWater,
             .garbageManagementPlan, .oilRecordBook, .garbageRecordBook, .sopep:
            return .pollution
        case .loadLine, .internationalTonnage:
            return .loadLineTonnage
        case .classCertificate, .annualSurvey, .intermediateSurvey, .dockingSurvey, .specialSurvey:
            return .classification
        case .minimumSafeManning, .mlcCertificate, .dmlc:
            return .manningLabour
        case .insuranceCertificate, .hmInsurance, .civilLiability, .wreckRemoval, .warRisk:
            return .insurance
        case .radioSafety, .shipRadioLicence, .epirbRegistration, .certificateOfRegistry, .epirbBatteryCert:
            return .radio
        case .largeYachtCode, .commercialYachtCert, .pleasureYachtCert, .shortRangeSafety,
             .yachtSafetyCertificate, .mcaSCVCode, .mcaLY2, .caymanREG, .maltaSYC, .maltaSCV,
             .marshallIslandsMI108, .redEnsignREG, .passengerYachtCode:
            return .yacht
        case .other:
            return .other
        }
    }

    var icon: String {
        switch self {
        // Safety
        case .smc: return "shield.checkered"
        case .ismDOC: return "doc.badge.gearshape"
        case .cargoShipSafety: return "shippingbox"
        case .cargoShipSafetyConstruction: return "building.2"
        case .cargoShipSafetyEquipment: return "wrench.and.screwdriver"
        case .passengerShipSafety: return "person.2"
        case .issc: return "lock.shield"
        case .csr: return "clock.arrow.circlepath"
        // Pollution
        case .iopp: return "drop.triangle"
        case .ispp: return "water.waves"
        case .iapp: return "wind"
        case .iee: return "leaf"
        case .ballastWater: return "drop.debit"
        // Load Line & Tonnage
        case .loadLine: return "ruler"
        case .internationalTonnage: return "scalemass"
        // Classification
        case .classCertificate: return "checkmark.seal"
        case .annualSurvey: return "magnifyingglass"
        case .intermediateSurvey: return "calendar.badge.clock"
        case .dockingSurvey: return "rectangle.dock"
        case .specialSurvey: return "calendar.badge.exclamationmark"
        // Manning
        case .minimumSafeManning: return "person.3"
        case .mlcCertificate: return "person.badge.shield.checkmark"
        case .dmlc: return "list.bullet.clipboard"
        // Insurance
        case .insuranceCertificate: return "building.columns"
        case .hmInsurance: return "ferry"
        case .civilLiability: return "banknote"
        case .wreckRemoval: return "exclamationmark.triangle"
        case .warRisk: return "shield.lefthalf.filled"
        // Radio
        case .radioSafety: return "antenna.radiowaves.left.and.right"
        case .shipRadioLicence: return "radio"
        case .epirbRegistration: return "antenna.radiowaves.left.and.right.circle"
        case .certificateOfRegistry: return "flag.badge.ellipsis"
        // Yacht codes
        case .largeYachtCode: return "sailboat"
        case .commercialYachtCert: return "sailboat.fill"
        case .pleasureYachtCert: return "sailboat.circle"
        case .shortRangeSafety: return "antenna.radiowaves.left.and.right.slash"
        // Yacht safety & stability
        case .stabilityBooklet: return "level"
        case .safetyEquipmentSurvey: return "shield.checkered"
        case .yachtSafetyCertificate: return "sailboat"
        // MARPOL operations
        case .garbageManagementPlan: return "trash"
        case .oilRecordBook: return "drop"
        case .garbageRecordBook: return "trash.circle"
        case .sopep: return "exclamationmark.bubble"
        // Navigation & safety equipment
        case .navigationLightCert: return "light.beacon.max"
        case .lifeRaftServiceCert: return "lifepreserver"
        case .fireExtinguisherServiceCert: return "flame.circle"
        case .epirbBatteryCert: return "battery.100.bolt"
        // Flag-specific yacht codes
        case .mcaSCVCode: return "ruler"
        case .mcaLY2: return "sailboat"
        case .caymanREG: return "flag"
        case .maltaSYC: return "flag.badge.ellipsis"
        case .maltaSCV: return "ruler"
        case .marshallIslandsMI108: return "flag.checkered"
        case .redEnsignREG: return "flag.2.crossed"
        case .passengerYachtCode: return "person.2.wave.2"
        case .other: return "doc"
        }
    }

    var typicalValidityMonths: Int? {
        switch self {
        // 5-year (60 months)
        case .classCertificate, .smc, .ismDOC, .issc: return 60
        case .iopp, .ispp, .iapp, .ballastWater: return 60
        case .cargoShipSafety, .cargoShipSafetyConstruction, .cargoShipSafetyEquipment, .passengerShipSafety: return 60
        case .loadLine, .radioSafety: return 60
        case .mlcCertificate, .specialSurvey: return 60
        case .largeYachtCode, .commercialYachtCert, .shortRangeSafety: return 60
        case .yachtSafetyCertificate, .mcaSCVCode, .mcaLY2: return 60
        case .caymanREG, .maltaSYC, .maltaSCV, .marshallIslandsMI108, .redEnsignREG, .passengerYachtCode: return 60
        // 1-year (12 months)
        case .civilLiability, .wreckRemoval, .insuranceCertificate, .hmInsurance, .warRisk: return 12
        case .annualSurvey, .safetyEquipmentSurvey, .lifeRaftServiceCert, .fireExtinguisherServiceCert: return 12
        // 2-year
        case .epirbBatteryCert: return 24
        // No standard expiry
        default: return nil
        }
    }

    var renewalInfo: RenewalInfo? {
        switch self {
        // Classification & Survey
        case .classCertificate: return RenewalInfo("Book special survey with classification society", leadTime: "3-6 months", contact: "Classification society", notes: "5-year cycle; annual/intermediate surveys in between")
        case .annualSurvey: return RenewalInfo("Schedule annual classification survey", leadTime: "1-2 months", contact: "Classification society surveyor", notes: "Window: 3 months before/after anniversary date")
        case .intermediateSurvey: return RenewalInfo("Schedule intermediate hull/machinery survey", leadTime: "2-3 months", contact: "Classification society")
        case .dockingSurvey: return RenewalInfo("Schedule docking survey — vessel must be dry-docked", leadTime: "3-6 months", contact: "Classification society + shipyard")
        case .specialSurvey: return RenewalInfo("Major 5-year survey — hull, machinery, equipment", leadTime: "6-12 months", contact: "Classification society", notes: "Plan well ahead — requires dry-docking and extensive inspection")
        // Safety (SOLAS)
        case .smc: return RenewalInfo("ISM audit by flag state or recognised organisation", leadTime: "2-3 months", contact: "Flag state administration")
        case .ismDOC: return RenewalInfo("ISM Document of Compliance audit", leadTime: "2-3 months", contact: "Flag state or RO")
        case .issc: return RenewalInfo("ISPS security audit and renewal survey", leadTime: "2-3 months", contact: "Flag state or RSO")
        case .radioSafety: return RenewalInfo("Radio survey and equipment inspection", leadTime: "1-2 months", contact: "Flag state or RO")
        // Pollution (MARPOL)
        case .iopp: return RenewalInfo("MARPOL Annex I survey", leadTime: "2-3 months", contact: "Classification society")
        case .ispp: return RenewalInfo("MARPOL Annex IV sewage survey", leadTime: "2-3 months", contact: "Classification society")
        case .iapp: return RenewalInfo("MARPOL Annex VI air pollution survey", leadTime: "2-3 months", contact: "Classification society")
        case .ballastWater: return RenewalInfo("Ballast water management system survey", leadTime: "2-3 months", contact: "Classification society")
        // Load Line & Tonnage
        case .loadLine: return RenewalInfo("Load line survey", leadTime: "2-3 months", contact: "Classification society")
        // Insurance
        case .insuranceCertificate: return RenewalInfo("Renew P&I insurance policy", leadTime: "1-3 months", contact: "P&I club broker", notes: "Standard renewal date: 20 February (noon)")
        case .hmInsurance: return RenewalInfo("Renew hull & machinery policy", leadTime: "1-2 months", contact: "Insurance broker")
        case .civilLiability: return RenewalInfo("Renew bunker/CLC insurance certificate", leadTime: "1-2 months", contact: "P&I club")
        case .wreckRemoval: return RenewalInfo("Renew wreck removal insurance", leadTime: "1-2 months", contact: "P&I club")
        case .warRisk: return RenewalInfo("Renew war risk insurance", leadTime: "1 month", contact: "War risk insurance broker")
        // Manning & Labour
        case .mlcCertificate: return RenewalInfo("MLC inspection by flag state", leadTime: "2-3 months", contact: "Flag state administration")
        case .minimumSafeManning: return RenewalInfo("Apply to flag state for updated manning document", leadTime: "1-2 months", contact: "Flag state administration")
        // Safety Equipment
        case .lifeRaftServiceCert: return RenewalInfo("Annual life raft service at certified station", leadTime: "1 month", contact: "Approved life raft service station")
        case .fireExtinguisherServiceCert: return RenewalInfo("Annual fire extinguisher inspection and recharge", leadTime: "2 weeks", contact: "Fire safety service provider")
        case .epirbBatteryCert: return RenewalInfo("Replace EPIRB battery or unit", leadTime: "1 month", contact: "EPIRB service dealer")
        case .safetyEquipmentSurvey: return RenewalInfo("Annual safety equipment survey", leadTime: "1-2 months", contact: "Classification society or flag state surveyor")
        // Yacht Codes
        case .largeYachtCode, .mcaLY2: return RenewalInfo("LY3/LY2 code compliance survey", leadTime: "3-6 months", contact: "MCA surveyor or flag state")
        case .maltaSYC: return RenewalInfo("Malta SYC compliance survey", leadTime: "3-6 months", contact: "Transport Malta")
        case .caymanREG: return RenewalInfo("Cayman REG code renewal survey", leadTime: "3-6 months", contact: "Cayman Islands Shipping Registry")
        case .marshallIslandsMI108: return RenewalInfo("MI-108 yacht code renewal survey", leadTime: "2-3 months", contact: "Marshall Islands Maritime Administrator")
        case .commercialYachtCert: return RenewalInfo("Commercial yacht certificate renewal survey", leadTime: "2-3 months", contact: "Flag state administration")
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

    // KYB freshness — corporate docs must be ≤12 months old
    var isCorporateDoc: Bool {
        [.certificateOfIncorporation, .companyRegistration, .shareholderRegistry,
         .uboRegistryExtract, .certificateOfIncumbency, .certificateOfGoodStanding,
         .directorRegistry].contains(type)
    }

    var isFresh: Bool {
        guard isCorporateDoc, let issue = issueDate else { return true }
        return issue > (Calendar.current.date(byAdding: .month, value: -12, to: Date()) ?? Date())
    }

    var hasNoFreshnessRequirement: Bool {
        [.trustDeed, .articlesOfAssociation, .partnershipAgreement].contains(type)
    }

    var freshnessWarning: String? {
        guard isCorporateDoc, !isFresh else { return nil }
        return "Document is older than 12 months — KYB requires a recent version"
    }

    enum Status: String { case valid, expiringSoon, expired, missing }

    var status: Status {
        guard let exp = expiryDate else { return imagePaths.isEmpty ? .missing : .valid }
        if exp < Date() { return .expired }
        if exp < Calendar.current.date(byAdding: .day, value: 90, to: Date()) ?? Date() { return .expiringSoon }
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

// MARK: - Knowledge Base Rules

struct RequirementRule: Codable, Identifiable {
    var id: String = UUID().uuidString
    var flag: String             // ISO-3 or "*" for universal
    var vesselType: String?      // VesselType.rawValue or nil for all
    var minGT: Double?
    var maxGT: Double?
    var minLOA: Double?
    var maxLOA: Double?
    var rankCategory: String?    // "officerDeck", "officerEngine", "ratingDeck", etc.
    var yearBuiltAfter: Int?
    var required: [String]       // MaritimeDocType or VesselDocType rawValues
    var source: String?          // Legislative reference

    func matches(flag f: String, vesselType vt: String?, gt: Double?, loa: Double?, rankCat: String? = nil, yearBuilt: Int? = nil) -> Bool {
        if self.flag != "*" && self.flag.lowercased() != f.lowercased() { return false }
        if let rvt = self.vesselType, rvt != "*", let vt, rvt.lowercased() != vt.lowercased() { return false }
        if let min = self.minGT, let g = gt, g < min { return false }
        if let max = self.maxGT, let g = gt, g > max { return false }
        if let min = self.minLOA, let l = loa, l < min { return false }
        if let max = self.maxLOA, let l = loa, l > max { return false }
        if let rc = self.rankCategory, let rk = rankCat, rc.lowercased() != rk.lowercased() { return false }
        if let yba = self.yearBuiltAfter, let yb = yearBuilt, yb <= yba { return false }
        return true
    }
}

struct MaritimeRulesDB: Codable {
    var version: Int
    var lastUpdated: String
    var crewRules: [RequirementRule]
    var vesselRules: [RequirementRule]
    var customRules: [RequirementRule]
}

// MARK: - Flag State Requirements

enum FlagStateRequirements {

    /// Required documents for corporate/UBO entities
    static func requiredForEntity(_ entityType: KYCCheck.EntityType) -> [MaritimeDocType] {
        switch entityType {
        case .seafarer:
            return []
        case .dpa, .fleetManager, .technicalSuper, .crewingManager:
            return [.passport, .proofOfAddress]
        case .owner:
            return [.passport, .proofOfAddress, .uboDeclaration, .corporateStructureChart]
        case .ubo:
            return [.passport, .proofOfAddress, .uboDeclaration, .corporateStructureChart, .financialStatements]
        case .managementCompany:
            return [.certificateOfIncorporation, .certificateOfGoodStanding, .articlesOfAssociation,
                    .companyRegistration, .shareholderRegistry, .directorRegistry,
                    .directorID, .registeredAgentCert, .signatoryAuthorization, .proofOfAddress]
        case .directorOfficer:
            return [.passport, .proofOfAddress, .directorID, .signatoryAuthorization]
        // Trust roles (KYB)
        case .trustee:
            return [.passport, .proofOfAddress, .trustDeed]
        case .settlor:
            return [.passport, .proofOfAddress]
        case .protector:
            return [.passport, .proofOfAddress]
        case .beneficiary:
            return [.passport, .proofOfAddress]
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

        // ── Yacht crew specifics (20-50m range) ──
        if let vt = vesselType, vt.isMegayacht {
            let isCommercial = vt == .megayachtCharter

            // All yacht crew — tender operations
            docs.insert(.powerboatLevel2)

            // Commercial yacht crew
            if isCommercial {
                docs.insert(.foodSafetyCert)

                if let rank {
                    switch rank.category {
                    case .officerDeck:
                        docs.insert(.helmCert)
                        docs.insert(.ryaYachtmaster)
                        docs.insert(.ssoCertificate)
                    case .officerEngine:
                        docs.insert(.helmCert)
                    case .ratingDeck:
                        docs.insert(.yachtRatingCert)
                        docs.insert(.pwcProficiency)
                    case .hospitality:
                        docs.insert(.interiorCrewTraining)
                    default: break
                    }
                }
            }

            // Red Ensign yacht crew: MCA SD instead of seaman's book
            if ["GBR", "CYM", "BMU", "GIB"].contains(f) {
                docs.remove(.seamansBook)
                docs.insert(.mcaSeafarerDoc)
            }

            // Marshall Islands: drug & alcohol policy mandatory
            if f == "MHL" { docs.insert(.drugAlcoholPolicy) }
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

    // ═══════════════════════════════════════════
    // MARK: - Vessel Document Requirements
    // ═══════════════════════════════════════════

    struct VesselDocRequirement: Identifiable {
        var id: String { type.rawValue }
        let type: VesselDocType
        let reason: String
        let mandatory: Bool

        init(type: VesselDocType, reason: String, mandatory: Bool = true) {
            self.type = type; self.reason = reason; self.mandatory = mandatory
        }
    }

    /// Compute required vessel certificates based on flag state, vessel type, gross tonnage, and length.
    /// If GT is unknown, assumes ≥500 GT (conservative — over-require rather than under-require).
    static func requiredVesselDocs(
        flag: String,
        vesselType: VesselType?,
        grossTonnage: Double?,
        lengthOverall: Double? = nil,
        registeredLength: Double? = nil,
        yearBuilt: Int? = nil
    ) -> [VesselDocRequirement] {
        var reqs: [VesselDocType: VesselDocRequirement] = [:]

        func add(_ type: VesselDocType, _ reason: String, mandatory: Bool = true) {
            if reqs[type] == nil { reqs[type] = VesselDocRequirement(type: type, reason: reason, mandatory: mandatory) }
        }

        // ── Step A: Universal baseline (ALL vessels) ──
        add(.certificateOfRegistry, "Flag state registration")
        add(.classCertificate, "Classification society")
        add(.minimumSafeManning, "SOLAS Reg. V/14")
        add(.insuranceCertificate, "P&I Club requirement")
        add(.hmInsurance, "Hull & Machinery coverage")
        add(.annualSurvey, "Classification society")

        // ── Step B: GT/size thresholds ──
        // If GT unknown, assume large (≥500 GT) for safety
        let gt = grossTonnage ?? 500
        let loa = lengthOverall ?? 30
        let rl = registeredLength  // nil if not set — Malta uses this for 24m threshold

        if gt >= 150 || loa >= 24 {
            add(.loadLine, "International Load Line Convention (≥150 GT / ≥24m)")
            add(.internationalTonnage, "Tonnage Convention 1969 (≥150 GT)")
        }

        if gt >= 300 {
            add(.radioSafety, "SOLAS Ch. IV (≥300 GT)")
            add(.shipRadioLicence, "SOLAS Ch. IV (≥300 GT)")
            add(.epirbRegistration, "SOLAS Ch. IV (≥300 GT)")
        }

        if gt >= 400 {
            add(.ispp, "MARPOL Annex IV (≥400 GT)")
            add(.iapp, "MARPOL Annex VI (≥400 GT)")
            add(.ballastWater, "BWM Convention (≥400 GT)")
        }

        if gt >= 500 {
            add(.smc, "SOLAS Ch. IX / ISM Code (≥500 GT)")
            add(.ismDOC, "SOLAS Ch. IX / ISM Code (≥500 GT)")
            add(.issc, "ISPS Code (≥500 GT)")
            add(.csr, "SOLAS Ch. XI-1 (≥500 GT)")
            add(.cargoShipSafetyConstruction, "SOLAS Ch. II (≥500 GT)")
            add(.cargoShipSafetyEquipment, "SOLAS Ch. II / III (≥500 GT)")
            add(.mlcCertificate, "MLC 2006 (≥500 GT)")
            add(.dmlc, "MLC 2006 (≥500 GT)")
            add(.civilLiability, "CLC Convention (≥500 GT)")
            add(.wreckRemoval, "Nairobi WRC (≥300 GT)")
        } else if gt >= 300 {
            add(.wreckRemoval, "Nairobi WRC (≥300 GT)")
        }

        // ── Step C: Vessel type rules ──
        if let vt = vesselType {
            switch vt {
            case .tankerOil, .tankerChemical, .tankerGas:
                add(.iopp, "MARPOL Annex I (all tankers)")
                add(.iee, "MARPOL Annex VI (all tankers)")

            case .passenger:
                add(.passengerShipSafety, "SOLAS Ch. I (passenger vessels)")
                reqs.removeValue(forKey: .cargoShipSafetyConstruction)
                reqs.removeValue(forKey: .cargoShipSafetyEquipment)

            case .megayachtPrivate:
                add(.pleasureYachtCert, "Flag state yacht code", mandatory: false)

            case .megayachtCharter:
                add(.commercialYachtCert, "Commercial yacht code")
                add(.smc, "ISM Code (commercial yachts)")
                add(.ismDOC, "ISM Code (commercial yachts)")

            case .offshore:
                add(.smc, "ISM Code (MODU / offshore)")
                add(.ismDOC, "ISM Code (MODU / offshore)")

            case .commercialCargo:
                break // Covered by GT thresholds
            }
        }

        // ── Step C2: Yacht-specific (20-50m range) ──
        if let vt = vesselType, vt.isMegayacht {
            let isCommercial = vt == .megayachtCharter
            let isLarge = loa >= 24

            // All yachts — safety equipment
            add(.navigationLightCert, "All vessels")
            add(.lifeRaftServiceCert, "Annual requirement")
            add(.fireExtinguisherServiceCert, "Annual requirement")
            add(.epirbBatteryCert, "EPIRB maintenance")

            // ≥24m (large yacht)
            if isLarge {
                add(.stabilityBooklet, "Required ≥24m (all codes)")
                add(.loadLine, "International Load Line (≥24m)")
                add(.internationalTonnage, "Tonnage Convention (≥24m)")
            }

            // ≥100 GT (virtually all 20-50m yachts)
            if gt >= 100 {
                add(.garbageManagementPlan, "MARPOL Annex V (≥100 GT)")
            }

            // ≥400 GT
            if gt >= 400 {
                add(.oilRecordBook, "MARPOL Annex I (≥400 GT)")
                add(.garbageRecordBook, "MARPOL Annex V (≥400 GT)")
                add(.sopep, "MARPOL I, Reg. 37 (≥400 GT)")
            }

            // Commercial yacht specifics
            if isCommercial {
                add(.safetyEquipmentSurvey, "Annual for commercial yachts")
                add(.yachtSafetyCertificate, "Commercial yacht code")

                if gt >= 500 {
                    add(.issc, "ISPS Code (≥500 GT)")
                    add(.csr, "Continuous Synopsis Record (≥500 GT)")
                    add(.mlcCertificate, "MLC 2006 (≥500 GT)")
                    add(.dmlc, "MLC 2006 (≥500 GT)")
                }
            }

            // Remove cargo ship certs from yachts (they're not cargo ships)
            reqs.removeValue(forKey: .cargoShipSafetyConstruction)
            reqs.removeValue(forKey: .cargoShipSafetyEquipment)
            reqs.removeValue(forKey: .cargoShipSafety)
        }

        // ── Step D: Flag-specific yacht code requirements (10 major registries) ──
        let f = normalize(flag)
        let isYacht = vesselType?.isMegayacht == true
        let isCommercialYacht = vesselType == .megayachtCharter
        let pre2017 = (yearBuilt ?? 2018) < 2017

        if isYacht {
            switch f {
            // 1. Cayman Islands — REG Yacht Code
            case "CYM":
                add(.caymanREG, "Cayman REG Yacht Code")
                if isCommercialYacht {
                    add(.smc, "CYM: SMC even <500 GT for commercial")
                    add(.ismDOC, "CYM: ISM even <500 GT for commercial")
                }
                add(.warRisk, "Cayman registry requirement")
                add(.annualSurvey, "CYM: Annual survey required")
                if gt >= 500 { add(.mlcCertificate, "CYM: MLC ≥500 GT") }

            // 2. UK Red Ensign — MCA
            case "GBR":
                if loa < 24 {
                    add(.mcaSCVCode, "MCA SCV Code (<24m)")
                    add(.shortRangeSafety, "MCA SRC (<24m)")
                } else if pre2017 {
                    add(.mcaLY2, "MCA LY2 (pre-2017 build, ≥24m)")
                } else {
                    add(.largeYachtCode, "MCA LY3 (post-2017 build, ≥24m)")
                }
                if isCommercialYacht {
                    add(.smc, "GBR: SMC for all commercial yachts")
                    add(.ismDOC, "GBR: ISM for all commercial")
                }

            // 3. Malta — uses REGISTERED LENGTH (RL), not LOA, for 24m threshold
            case "MLT":
                let maltaLength = rl ?? loa  // prefer RL, fall back to LOA
                let isLargeMalta = maltaLength >= 24

                if isCommercialYacht {
                    if isLargeMalta {
                        add(.maltaSYC, "Malta SYC (≥24m registered length)")
                        add(.smc, "MLT: ISM/SMC required (SYC)")
                        add(.ismDOC, "MLT: ISM required (SYC)")
                        add(.stabilityBooklet, "MLT: Stability booklet (≥24m RL)")
                        add(.loadLine, "MLT: Load Line (≥24m RL)")
                    } else {
                        add(.maltaSCV, "Malta Small Commercial Vessel Code (<24m RL)")
                        add(.smc, "MLT: ISM/SMC regardless of GT")
                        add(.ismDOC, "MLT: ISM regardless of GT")
                    }
                    add(.safetyEquipmentSurvey, "MLT: Annual safety equipment survey")
                    add(.classCertificate, "MLT: Classification required")
                } else {
                    if isLargeMalta {
                        add(.pleasureYachtCert, "MLT: Private yacht (≥24m RL)")
                        add(.stabilityBooklet, "MLT: Stability booklet (≥24m RL)")
                    } else {
                        add(.pleasureYachtCert, "MLT: Pleasure craft (<24m RL)")
                    }
                }

            // 4. Marshall Islands — MI-108
            case "MHL":
                add(.marshallIslandsMI108, "MI-108 Yacht Code")
                add(.annualSurvey, "MHL: Annual yacht survey")
                add(.specialSurvey, "MHL: Special survey (5-year)")
                if isCommercialYacht && gt >= 500 {
                    add(.smc, "MHL: ISM/SMC ≥500 GT commercial")
                    add(.ismDOC, "MHL: ISM ≥500 GT commercial")
                }

            // 5. Bahamas
            case "BHS":
                if isCommercialYacht { add(.commercialYachtCert, "Bahamas yacht code certificate") }
                if loa >= 24 { add(.stabilityBooklet, "BHS: Full SOLAS ≥24m") }

            // 6. Gibraltar — Red Ensign Group
            case "GIB":
                if loa < 24 {
                    add(.mcaSCVCode, "GIB/MCA SCV Code (<24m)")
                    add(.shortRangeSafety, "GIB/MCA SRC (<24m)")
                } else if pre2017 {
                    add(.mcaLY2, "GIB/MCA LY2 (pre-2017, ≥24m)")
                } else {
                    add(.largeYachtCode, "GIB/MCA LY3 (post-2017, ≥24m)")
                }
                if isCommercialYacht { add(.smc, "GIB: SMC for commercial") }

            // 7. Bermuda — Red Ensign Group
            case "BMU":
                if loa < 24 {
                    add(.mcaSCVCode, "BMU/MCA SCV Code (<24m)")
                } else if pre2017 {
                    add(.mcaLY2, "BMU/MCA LY2 (pre-2017, ≥24m)")
                } else {
                    add(.largeYachtCode, "BMU/MCA LY3 (post-2017, ≥24m)")
                }
                if isCommercialYacht { add(.smc, "BMU: SMC for commercial") }

            // 8. Cyprus
            case "CYP":
                if !isCommercialYacht {
                    add(.pleasureYachtCert, "CYP: Cypriot yacht licence (private)")
                } else {
                    add(.commercialYachtCert, "CYP: IMO conventions (commercial)")
                }
                if loa >= 24 { add(.stabilityBooklet, "CYP: Full SOLAS ≥24m") }

            // 9. Italy
            case "ITA":
                if !isCommercialYacht {
                    add(.pleasureYachtCert, "ITA: Atto di Nazionalita (private)")
                } else {
                    add(.commercialYachtCert, "ITA: RINA class (commercial)")
                    add(.classCertificate, "ITA: RINA classification")
                }

            // 10. France
            case "FRA":
                if !isCommercialYacht {
                    add(.pleasureYachtCert, "FRA: Francisation certificate (private)")
                } else {
                    add(.commercialYachtCert, "FRA: BV class (commercial)")
                    add(.classCertificate, "FRA: Bureau Veritas classification")
                }

            default:
                // Generic: apply REG for large yachts as advisory
                if loa >= 24 { add(.redEnsignREG, "Generic yacht code ≥24m", mandatory: false) }
            }
        } else {
            // Non-yacht flag overrides (war risk for large commercial)
            if ["MHL", "LBR", "PAN"].contains(f) && gt >= 500 {
                add(.warRisk, "\(f) registry recommendation", mandatory: false)
            }
        }

        // ── Step E: Sort by category then name ──
        return reqs.values.sorted {
            if $0.type.category != $1.type.category {
                return $0.type.category.rawValue < $1.type.category.rawValue
            }
            return $0.type.displayName < $1.type.displayName
        }
    }
}
