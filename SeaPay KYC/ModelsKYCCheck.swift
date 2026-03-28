//
//  KYCCheck.swift
//  SeaPay KYC
//

import Foundation

struct KYCCheck: Identifiable, Codable, Hashable {
    static func == (lhs: KYCCheck, rhs: KYCCheck) -> Bool {
        lhs.id == rhs.id && lhs.status == rhs.status && lhs.amlStatus == rhs.amlStatus && lhs.poaStatus == rhs.poaStatus && lhs.reviewDecision == rhs.reviewDecision
    }
    func hash(into hasher: inout Hasher) { hasher.combine(id); hasher.combine(status) }

    let id: String
    var customerId: String
    var customerName: String
    var agentId: String
    let agentName: String

    /// Display name: uses extracted name from verification, falls back to customerName
    var displayName: String {
        if let extracted = extractedName, !extracted.isEmpty { return extracted }
        if customerName.hasPrefix("Crew ") || customerName == "Pending" { return "Pending verification" }
        return customerName
    }
    var checkType: CheckType
    var status: CheckStatus
    var entityType: EntityType
    let createdAt: Date
    var completedAt: Date?
    var agentNotes: String?
    var sessionId: String?
    var hostedVerifyURL: String?
    var vesselId: String?
    var crewRank: CrewRank?
    var documents: [CrewDocument]?
    var profilePhoto: String?
    var documentImagePaths: [String]?
    var latitude: Double?
    var longitude: Double?

    // Corporate fields (for owners, UBOs, management companies)
    var companyName: String?
    var registrationNumber: String?
    var jurisdiction: String?
    var ownershipPercent: Double?

    enum EntityType: String, Codable, CaseIterable, Identifiable {
        // Crew (on-board)
        case seafarer = "Seafarer"

        // Shore-based
        case dpa = "DPA"
        case fleetManager = "Fleet Manager"
        case technicalSuper = "Technical Superintendent"
        case crewingManager = "Crewing Manager"

        // Ownership & compliance
        case owner = "Ship Owner"
        case ubo = "Beneficial Owner (UBO)"
        case managementCompany = "Management Company"
        case directorOfficer = "Director / Officer"
        case trustee = "Trustee"
        case settlor = "Settlor"
        case protector = "Protector"
        case beneficiary = "Beneficiary"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .seafarer: return "person.text.rectangle"
            case .dpa: return "person.badge.clock"
            case .fleetManager: return "person.crop.rectangle.stack"
            case .technicalSuper: return "wrench.and.screwdriver"
            case .crewingManager: return "person.2"
            case .owner: return "building.2"
            case .ubo: return "person.badge.key"
            case .managementCompany: return "building"
            case .directorOfficer: return "person.badge.shield.checkmark"
            case .trustee: return "shield.checkered"
            case .settlor: return "person.badge.key"
            case .protector: return "eye"
            case .beneficiary: return "gift"
            }
        }

        var category: PersonCategory {
            switch self {
            case .seafarer: return .crew
            case .dpa, .fleetManager, .technicalSuper, .crewingManager: return .shoreBased
            case .owner, .ubo, .managementCompany, .directorOfficer, .trustee, .settlor, .protector, .beneficiary: return .ownership
            }
        }

        var isIndividual: Bool { self != .managementCompany }
        var isCorporate: Bool { self == .managementCompany }
        var needsOwnership: Bool { self == .ubo }

        /// Grouped for UI pickers
        static var crewTypes: [EntityType] { [.seafarer] }
        static var shoreBasedTypes: [EntityType] { [.dpa, .fleetManager, .technicalSuper, .crewingManager] }
        static var ownershipTypes: [EntityType] { [.owner, .ubo, .managementCompany, .directorOfficer, .trustee, .settlor, .protector, .beneficiary] }
    }

    enum PersonCategory: String, Codable {
        case crew = "Crew"
        case shoreBased = "Shore-Based"
        case ownership = "Ownership & Compliance"
    }

    // Agent-selected options
    var expectedDocType: IDDocType?
    var investigationDepth: InvestigationDepth?

    // ID Verification results
    var extractedName: String?
    var documentType: String?  // API-detected
    var documentNumber: String?
    var dateOfBirth: String?
    var expiryDate: String?
    var nationality: String?
    var issuingCountry: String?
    var gender: String?
    var documentIssueDate: String?
    var placeOfBirth: String?
    var personalNumber: String?
    var extractedAddress: String?
    var idWarnings: [String]?

    // AML results
    var amlStatus: String?
    var amlScore: Int?
    var amlHitCount: Int?
    var amlMonitoring: Bool?

    // PoA results
    var poaStatus: String?
    var poaAddress: String?
    var poaIssuer: String?
    var poaWarnings: [String]?

    // Raw API responses
    var rawIDResponse: String?
    var rawAMLResponse: String?
    var rawPoAResponse: String?

    // Agent review
    var reviewDecision: ReviewDecision?
    var reviewReason: String?
    var reviewedAt: Date?
    var reviewedBy: String?

    enum InvestigationDepth: String, Codable, CaseIterable, Identifiable {
        case idOnly = "ID Only"
        case idAml = "ID + AML"
        case idAmlPoa = "ID + AML + Address"

        var id: String { rawValue }

        var includesAML: Bool { self != .idOnly }
        var includesPoA: Bool { self == .idAmlPoa }

        var icon: String {
            switch self {
            case .idOnly: return "person.text.rectangle"
            case .idAml: return "shield.checkered"
            case .idAmlPoa: return "house.and.flag"
            }
        }

        var description: String {
            switch self {
            case .idOnly: return "Document verification only"
            case .idAml: return "Document + sanctions & PEP screening"
            case .idAmlPoa: return "Full check with address verification"
            }
        }
    }

    enum ReviewDecision: String, Codable, Identifiable {
        case approved = "Approved"
        case flagged = "Flagged"
        case declined = "Declined"
        var id: String { rawValue }
    }

    enum CheckType: String, Codable, CaseIterable {
        case idVerification = "ID + AML"
        case idWithPoA = "ID + AML + Address"

        var icon: String {
            switch self {
            case .idVerification: return "person.text.rectangle"
            case .idWithPoA: return "house.and.flag"
            }
        }

        var description: String {
            switch self {
            case .idVerification:
                return "Scan ID, verify identity, run AML screening"
            case .idWithPoA:
                return "Full check: ID verification, AML, and proof of address"
            }
        }
    }

    enum CheckStatus: String, Codable {
        case pending = "Pending"
        case inProgress = "In Progress"
        case passed = "Passed"
        case failed = "Failed"
        case requiresReview = "Review"
        case incomplete = "Incomplete"

        var actionLabel: String? {
            switch self {
            case .pending: return "Start"
            case .failed: return "Retry"
            case .incomplete: return "Resume"
            case .inProgress: return nil
            case .requiresReview: return nil
            case .passed: return nil
            }
        }
    }

    enum IDDocType: String, Codable, CaseIterable, Identifiable {
        case passport = "Passport"
        case idCard = "ID Card"
        case driverLicense = "Driver License"
        case residencePermit = "Residence Permit"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .passport: return "book.closed.fill"
            case .idCard: return "person.text.rectangle.fill"
            case .driverLicense: return "car.fill"
            case .residencePermit: return "building.2.fill"
            }
        }

        var scanHint: String {
            switch self {
            case .passport: return "Open to the data page with the photo"
            case .idCard: return "Scan front side, then optionally the back"
            case .driverLicense: return "Scan the front with the photo"
            case .residencePermit: return "Scan the front with personal details"
            }
        }

        var needsBack: Bool {
            self == .idCard
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, customerId, customerName, agentId, agentName, checkType, status, entityType
        case createdAt, completedAt, agentNotes, sessionId, hostedVerifyURL, vesselId, crewRank, documents, profilePhoto, documentImagePaths
        case latitude, longitude
        case companyName, registrationNumber, jurisdiction, ownershipPercent
        case expectedDocType, investigationDepth
        case extractedName, documentType, documentNumber, dateOfBirth, expiryDate, nationality, idWarnings
        case amlStatus, amlScore, amlHitCount, amlMonitoring
        case poaStatus, poaAddress, poaIssuer, poaWarnings
        case rawIDResponse, rawAMLResponse, rawPoAResponse
        case reviewDecision, reviewReason, reviewedAt, reviewedBy
    }
}
