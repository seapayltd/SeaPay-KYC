//
//  VerificationModels.swift
//  SeaPay KYC
//
//  API response models for ID verification, AML screening, face match
//

import Foundation

// MARK: - ID Verification Response

struct IDVerificationResponse: Codable, Sendable {
    nonisolated let requestId: String?
    nonisolated let idVerification: IDResult?
    nonisolated let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case idVerification = "id_verification"
        case createdAt = "created_at"
    }

    nonisolated init(requestId: String? = nil, idVerification: IDResult? = nil, createdAt: String? = nil) {
        self.requestId = requestId; self.idVerification = idVerification; self.createdAt = createdAt
    }

    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        requestId = try c.decodeIfPresent(String.self, forKey: .requestId)
        idVerification = try c.decodeIfPresent(IDResult.self, forKey: .idVerification)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
    }
}

struct IDResult: Codable, Sendable {
    // Core identity
    nonisolated let status: String?
    nonisolated let firstName: String?
    nonisolated let lastName: String?
    nonisolated let fullName: String?
    nonisolated let dateOfBirth: String?
    nonisolated let age: Int?
    nonisolated let gender: String?
    nonisolated let nationality: String?
    nonisolated let placeOfBirth: String?
    nonisolated let maritalStatus: String?

    // Document data
    nonisolated let documentType: String?       // Passport, ID Card, Driver License, Residence Permit, etc.
    nonisolated let documentNumber: String?
    nonisolated let personalNumber: String?
    nonisolated let issuingState: String?
    nonisolated let issuingStateName: String?
    nonisolated let region: String?
    nonisolated let dateOfIssue: String?
    nonisolated let expirationDate: String?

    // Address
    nonisolated let address: String?
    nonisolated let formattedAddress: String?

    // Warnings
    nonisolated let warnings: [VerificationWarning]?

    enum CodingKeys: String, CodingKey {
        case status
        case firstName = "first_name"
        case lastName = "last_name"
        case fullName = "full_name"
        case dateOfBirth = "date_of_birth"
        case age, gender, nationality
        case placeOfBirth = "place_of_birth"
        case maritalStatus = "marital_status"
        case documentType = "document_type"
        case documentNumber = "document_number"
        case personalNumber = "personal_number"
        case issuingState = "issuing_state"
        case issuingStateName = "issuing_state_name"
        case region
        case dateOfIssue = "date_of_issue"
        case expirationDate = "expiration_date"
        case address
        case formattedAddress = "formatted_address"
        case warnings
    }

    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        firstName = try c.decodeIfPresent(String.self, forKey: .firstName)
        lastName = try c.decodeIfPresent(String.self, forKey: .lastName)
        fullName = try c.decodeIfPresent(String.self, forKey: .fullName)
        dateOfBirth = try c.decodeIfPresent(String.self, forKey: .dateOfBirth)
        age = try c.decodeIfPresent(Int.self, forKey: .age)
        gender = try c.decodeIfPresent(String.self, forKey: .gender)
        nationality = try c.decodeIfPresent(String.self, forKey: .nationality)
        placeOfBirth = try c.decodeIfPresent(String.self, forKey: .placeOfBirth)
        maritalStatus = try c.decodeIfPresent(String.self, forKey: .maritalStatus)
        documentType = try c.decodeIfPresent(String.self, forKey: .documentType)
        documentNumber = try c.decodeIfPresent(String.self, forKey: .documentNumber)
        personalNumber = try c.decodeIfPresent(String.self, forKey: .personalNumber)
        issuingState = try c.decodeIfPresent(String.self, forKey: .issuingState)
        issuingStateName = try c.decodeIfPresent(String.self, forKey: .issuingStateName)
        region = try c.decodeIfPresent(String.self, forKey: .region)
        dateOfIssue = try c.decodeIfPresent(String.self, forKey: .dateOfIssue)
        expirationDate = try c.decodeIfPresent(String.self, forKey: .expirationDate)
        address = try c.decodeIfPresent(String.self, forKey: .address)
        formattedAddress = try c.decodeIfPresent(String.self, forKey: .formattedAddress)
        warnings = try c.decodeIfPresent([VerificationWarning].self, forKey: .warnings)
    }

    // Back-compat: old code uses expiryDate
    var expiryDate: String? { expirationDate }
    var issuingCountry: String? { issuingStateName ?? issuingState }

    var extractedFullName: String {
        if let fn = fullName, !fn.isEmpty { return fn }
        return [firstName, lastName].compactMap { $0 }.joined(separator: " ")
    }
}

// MARK: - AML Screening Response

struct AMLScreeningResponse: Codable, Sendable {
    nonisolated let requestId: String?
    nonisolated let aml: AMLResult?
    nonisolated let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case aml
        case createdAt = "created_at"
    }

    nonisolated init(requestId: String? = nil, aml: AMLResult? = nil, createdAt: String? = nil) {
        self.requestId = requestId; self.aml = aml; self.createdAt = createdAt
    }

    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        requestId = try c.decodeIfPresent(String.self, forKey: .requestId)
        aml = try c.decodeIfPresent(AMLResult.self, forKey: .aml)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
    }
}

struct AMLResult: Codable, Sendable {
    nonisolated let status: String?
    nonisolated let entityType: String?
    nonisolated let totalHits: Int?
    nonisolated let score: Int?
    nonisolated let hits: [AMLHit]?
    nonisolated let warnings: [VerificationWarning]?

    enum CodingKeys: String, CodingKey {
        case status
        case entityType = "entity_type"
        case totalHits = "total_hits"
        case score
        case hits, warnings
    }

    nonisolated init(status: String? = nil, totalHits: Int? = nil, score: Int? = nil, hits: [AMLHit]? = nil, warnings: [VerificationWarning]? = nil) {
        self.status = status; self.entityType = nil; self.totalHits = totalHits; self.score = score; self.hits = hits; self.warnings = warnings
    }

    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        entityType = try c.decodeIfPresent(String.self, forKey: .entityType)
        totalHits = try c.decodeIfPresent(Int.self, forKey: .totalHits)
        score = try c.decodeIfPresent(Int.self, forKey: .score)
        hits = try c.decodeIfPresent([AMLHit].self, forKey: .hits)
        warnings = try c.decodeIfPresent([VerificationWarning].self, forKey: .warnings)
    }

    var riskLevel: String {
        guard let s = score else { return "Unknown" }
        if s > 70 { return "HIGH" }
        if s > 40 { return "MEDIUM" }
        return "LOW"
    }
}

struct AMLHit: Codable, Sendable {
    nonisolated let id: String?
    nonisolated let caption: String?
    nonisolated let matchScore: Int?
    nonisolated let riskScore: Double?
    nonisolated let reviewStatus: String?
    nonisolated let datasets: [String]?
    nonisolated let scoreBreakdown: AMLScoreBreakdown?
    nonisolated let pepMatches: [AMLPEPMatch]?
    nonisolated let sanctionMatches: [AMLSanctionMatch]?
    nonisolated let adverseMediaMatches: [AMLAdverseMedia]?
    nonisolated let firstSeen: String?
    nonisolated let lastSeen: String?

    enum CodingKeys: String, CodingKey {
        case id, caption, datasets
        case matchScore = "match_score"
        case riskScore = "risk_score"
        case reviewStatus = "review_status"
        case scoreBreakdown = "score_breakdown"
        case pepMatches = "pep_matches"
        case sanctionMatches = "sanction_matches"
        case adverseMediaMatches = "adverse_media_matches"
        case firstSeen = "first_seen"
        case lastSeen = "last_seen"
    }

    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id)
        caption = try c.decodeIfPresent(String.self, forKey: .caption)
        matchScore = try c.decodeIfPresent(Int.self, forKey: .matchScore)
        riskScore = try c.decodeIfPresent(Double.self, forKey: .riskScore)
        reviewStatus = try c.decodeIfPresent(String.self, forKey: .reviewStatus)
        datasets = try c.decodeIfPresent([String].self, forKey: .datasets)
        scoreBreakdown = try c.decodeIfPresent(AMLScoreBreakdown.self, forKey: .scoreBreakdown)
        pepMatches = try c.decodeIfPresent([AMLPEPMatch].self, forKey: .pepMatches)
        sanctionMatches = try c.decodeIfPresent([AMLSanctionMatch].self, forKey: .sanctionMatches)
        adverseMediaMatches = try c.decodeIfPresent([AMLAdverseMedia].self, forKey: .adverseMediaMatches)
        firstSeen = try c.decodeIfPresent(String.self, forKey: .firstSeen)
        lastSeen = try c.decodeIfPresent(String.self, forKey: .lastSeen)
    }
}

struct AMLScoreBreakdown: Codable, Sendable {
    nonisolated let nameScore: Int?
    nonisolated let dobScore: Int?
    nonisolated let countryScore: Int?
    nonisolated let totalScore: Int?

    enum CodingKeys: String, CodingKey {
        case nameScore = "name_score"
        case dobScore = "dob_score"
        case countryScore = "country_score"
        case totalScore = "total_score"
    }

    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nameScore = try c.decodeIfPresent(Int.self, forKey: .nameScore)
        dobScore = try c.decodeIfPresent(Int.self, forKey: .dobScore)
        countryScore = try c.decodeIfPresent(Int.self, forKey: .countryScore)
        totalScore = try c.decodeIfPresent(Int.self, forKey: .totalScore)
    }
}

struct AMLPEPMatch: Codable, Sendable {
    nonisolated let matchedName: String?
    nonisolated let listName: String?
    nonisolated let pepPosition: String?
    nonisolated let description: String?

    enum CodingKeys: String, CodingKey {
        case matchedName = "matched_name"
        case listName = "list_name"
        case pepPosition = "pep_position"
        case description
    }

    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        matchedName = try c.decodeIfPresent(String.self, forKey: .matchedName)
        listName = try c.decodeIfPresent(String.self, forKey: .listName)
        pepPosition = try c.decodeIfPresent(String.self, forKey: .pepPosition)
        description = try c.decodeIfPresent(String.self, forKey: .description)
    }
}

struct AMLSanctionMatch: Codable, Sendable {
    nonisolated let matchedName: String?
    nonisolated let description: String?
    nonisolated let reason: String?
    nonisolated let sourceUrl: String?

    enum CodingKeys: String, CodingKey {
        case matchedName = "matched_name"
        case description, reason
        case sourceUrl = "source_url"
    }

    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        matchedName = try c.decodeIfPresent(String.self, forKey: .matchedName)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        reason = try c.decodeIfPresent(String.self, forKey: .reason)
        sourceUrl = try c.decodeIfPresent(String.self, forKey: .sourceUrl)
    }
}

struct AMLAdverseMedia: Codable, Sendable {
    nonisolated let headline: String?
    nonisolated let summary: String?
    nonisolated let sentiment: String?
    nonisolated let sourceUrl: String?
    nonisolated let publicationDate: String?

    enum CodingKeys: String, CodingKey {
        case headline, summary, sentiment
        case sourceUrl = "source_url"
        case publicationDate = "publication_date"
    }

    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        headline = try c.decodeIfPresent(String.self, forKey: .headline)
        summary = try c.decodeIfPresent(String.self, forKey: .summary)
        sentiment = try c.decodeIfPresent(String.self, forKey: .sentiment)
        sourceUrl = try c.decodeIfPresent(String.self, forKey: .sourceUrl)
        publicationDate = try c.decodeIfPresent(String.self, forKey: .publicationDate)
    }
}

// MARK: - Face Match Response

struct FaceMatchResponse: Codable, Sendable {
    nonisolated let requestId: String?
    nonisolated let faceMatch: FaceMatchResult?
    nonisolated let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case faceMatch = "face_match"
        case createdAt = "created_at"
    }

    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        requestId = try c.decodeIfPresent(String.self, forKey: .requestId)
        faceMatch = try c.decodeIfPresent(FaceMatchResult.self, forKey: .faceMatch)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
    }
}

struct FaceMatchResult: Codable, Sendable {
    nonisolated let status: String?
    nonisolated let score: Int?

    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        score = try c.decodeIfPresent(Int.self, forKey: .score)
    }
}

// MARK: - Proof of Address Response

struct PoAResponse: Codable, Sendable {
    nonisolated let requestId: String?
    nonisolated let poa: PoAResult?
    nonisolated let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case poa
        case createdAt = "created_at"
    }

    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        requestId = try c.decodeIfPresent(String.self, forKey: .requestId)
        poa = try c.decodeIfPresent(PoAResult.self, forKey: .poa)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
    }
}

struct PoAResult: Codable, Sendable {
    nonisolated let status: String?
    nonisolated let documentType: String?
    nonisolated let issuer: String?
    nonisolated let issueDate: String?
    nonisolated let poaAddress: String?
    nonisolated let poaFormattedAddress: String?
    nonisolated let nameOnDocument: String?
    nonisolated let issuingState: String?
    nonisolated let documentLanguage: String?
    nonisolated let warnings: [VerificationWarning]?

    enum CodingKeys: String, CodingKey {
        case status
        case documentType = "document_type"
        case issuer
        case issueDate = "issue_date"
        case poaAddress = "poa_address"
        case poaFormattedAddress = "poa_formatted_address"
        case nameOnDocument = "name_on_document"
        case issuingState = "issuing_state"
        case documentLanguage = "document_language"
        case warnings
    }

    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        documentType = try c.decodeIfPresent(String.self, forKey: .documentType)
        issuer = try c.decodeIfPresent(String.self, forKey: .issuer)
        issueDate = try c.decodeIfPresent(String.self, forKey: .issueDate)
        poaAddress = try c.decodeIfPresent(String.self, forKey: .poaAddress)
        poaFormattedAddress = try c.decodeIfPresent(String.self, forKey: .poaFormattedAddress)
        nameOnDocument = try c.decodeIfPresent(String.self, forKey: .nameOnDocument)
        issuingState = try c.decodeIfPresent(String.self, forKey: .issuingState)
        documentLanguage = try c.decodeIfPresent(String.self, forKey: .documentLanguage)
        warnings = try c.decodeIfPresent([VerificationWarning].self, forKey: .warnings)
    }
}

// MARK: - Warning

struct VerificationWarning: Codable, Sendable {
    nonisolated let risk: String?
    nonisolated let logType: String?
    nonisolated let shortDescription: String?

    enum CodingKeys: String, CodingKey {
        case risk
        case logType = "log_type"
        case shortDescription = "short_description"
    }

    nonisolated init(risk: String? = nil, logType: String? = nil, shortDescription: String? = nil) {
        self.risk = risk; self.logType = logType; self.shortDescription = shortDescription
    }

    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        risk = try c.decodeIfPresent(String.self, forKey: .risk)
        logType = try c.decodeIfPresent(String.self, forKey: .logType)
        shortDescription = try c.decodeIfPresent(String.self, forKey: .shortDescription)
    }
}
