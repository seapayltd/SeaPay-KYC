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
    let customerName: String
    var agentId: String
    let agentName: String
    var checkType: CheckType
    var status: CheckStatus
    let createdAt: Date
    var completedAt: Date?
    var agentNotes: String?
    var documentImagePaths: [String]?
    var latitude: Double?
    var longitude: Double?

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

    enum ReviewDecision: String, Codable {
        case approved = "Approved"
        case flagged = "Flagged"
        case declined = "Declined"
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
        case id, customerId, customerName, agentId, agentName, checkType, status
        case createdAt, completedAt, agentNotes, documentImagePaths
        case latitude, longitude
        case expectedDocType, investigationDepth
        case extractedName, documentType, documentNumber, dateOfBirth, expiryDate, nationality, idWarnings
        case amlStatus, amlScore, amlHitCount, amlMonitoring
        case poaStatus, poaAddress, poaIssuer, poaWarnings
        case rawIDResponse, rawAMLResponse, rawPoAResponse
        case reviewDecision, reviewReason, reviewedAt, reviewedBy
    }
}
