//
//  GDPRService.swift
//  OceanCheck
//
//  GDPR compliance: consent records, data retention, DSAR export, audit log.
//

import Foundation

// MARK: - Consent Record

struct ConsentRecord: Codable, Identifiable {
    let id: String
    let subjectName: String
    let checkId: String
    let consentType: ConsentType
    let policyVersion: String
    let grantedAt: Date
    var withdrawnAt: Date?

    var isActive: Bool { withdrawnAt == nil }

    enum ConsentType: String, Codable {
        case identityVerification = "Identity Verification"
        case amlScreening = "AML/Sanctions Screening"
        case proofOfAddress = "Proof of Address"
        case dataProcessing = "Data Processing"
        case dataTransfer = "Data Transfer to Third Party"
    }
}

// MARK: - Audit Event

struct AuditEvent: Codable, Identifiable {
    let id: String
    let timestamp: Date
    let action: AuditAction
    let entityId: String       // check ID or vessel ID
    let entityName: String
    let performedBy: String    // agent name
    let detail: String?

    enum AuditAction: String, Codable {
        case created = "Created"
        case viewed = "Viewed"
        case exported = "Exported"
        case shared = "Shared"
        case reviewed = "Reviewed"
        case deleted = "Deleted"
        case transferred = "Transferred"
        case dsarExported = "DSAR Export"
        case consentGranted = "Consent Granted"
        case consentWithdrawn = "Consent Withdrawn"
        case retentionFlagged = "Retention Flagged"
    }
}

// MARK: - Data Retention Policy

struct RetentionPolicy: Codable {
    var retentionYears: Int       // Default 5 (MLC 2006)
    var autoFlagExpired: Bool     // Show warning on records past retention
    var autoDeleteExpired: Bool   // Actually delete (off by default)

    static let `default` = RetentionPolicy(retentionYears: 5, autoFlagExpired: true, autoDeleteExpired: false)
}

// MARK: - GDPR Service

enum GDPRService {

    private static let policyVersion = "2.0"

    // MARK: - Consent

    static func recordConsent(subjectName: String, checkId: String, types: [ConsentRecord.ConsentType], store: inout [ConsentRecord]) {
        let agentName = AgentProfile.current?.fullName ?? "Agent"
        for type in types {
            let record = ConsentRecord(
                id: UUID().uuidString, subjectName: subjectName, checkId: checkId,
                consentType: type, policyVersion: policyVersion, grantedAt: Date()
            )
            store.append(record)
            logAudit(action: .consentGranted, entityId: checkId, entityName: subjectName, performedBy: agentName, detail: type.rawValue, log: &auditBuffer)
        }
    }

    static func withdrawConsent(recordId: String, store: inout [ConsentRecord]) {
        guard let i = store.firstIndex(where: { $0.id == recordId }) else { return }
        store[i].withdrawnAt = Date()
        let agentName = AgentProfile.current?.fullName ?? "Agent"
        logAudit(action: .consentWithdrawn, entityId: store[i].checkId, entityName: store[i].subjectName, performedBy: agentName, detail: store[i].consentType.rawValue, log: &auditBuffer)
    }

    // MARK: - Audit Log

    private static var auditBuffer: [AuditEvent] = []

    static func logAudit(action: AuditEvent.AuditAction, entityId: String, entityName: String, performedBy: String, detail: String? = nil, log: inout [AuditEvent]) {
        let event = AuditEvent(
            id: UUID().uuidString, timestamp: Date(), action: action,
            entityId: entityId, entityName: entityName, performedBy: performedBy, detail: detail
        )
        log.append(event)
    }

    // MARK: - Data Retention

    static func flaggedForRetention(checks: [KYCCheck], policy: RetentionPolicy) -> [KYCCheck] {
        guard policy.autoFlagExpired else { return [] }
        let cutoff = Calendar.current.date(byAdding: .year, value: -policy.retentionYears, to: Date()) ?? Date()
        return checks.filter { check in
            guard let completed = check.completedAt ?? Optional(check.createdAt) else { return false }
            return completed < cutoff
        }
    }

    static func retentionDate(for check: KYCCheck, policy: RetentionPolicy) -> Date? {
        guard let completed = check.completedAt ?? Optional(check.createdAt) else { return nil }
        return Calendar.current.date(byAdding: .year, value: policy.retentionYears, to: completed)
    }

    // MARK: - DSAR Export (Data Subject Access Request)

    /// Generate a JSON file containing all data held about a specific person.
    static func exportSubjectData(name: String, checks: [KYCCheck], vessels: [Vessel], consentRecords: [ConsentRecord], auditLog: [AuditEvent]) -> URL? {
        let matchingChecks = checks.filter {
            $0.customerName.localizedCaseInsensitiveContains(name) ||
            ($0.extractedName?.localizedCaseInsensitiveContains(name) ?? false)
        }

        guard !matchingChecks.isEmpty else { return nil }

        let checkIds = Set(matchingChecks.map(\.id))
        let matchingConsent = consentRecords.filter { checkIds.contains($0.checkId) }
        let matchingAudit = auditLog.filter { checkIds.contains($0.entityId) }
        let vesselIds = Set(matchingChecks.compactMap(\.vesselId))
        let matchingVessels = vessels.filter { vesselIds.contains($0.id) }.map { v in
            ["name": v.name, "imoNumber": v.imoNumber, "flagState": v.flagState]
        }

        let dateFmt = ISO8601DateFormatter()

        let exportData: [String: Any] = [
            "exportType": "GDPR Data Subject Access Request",
            "exportDate": dateFmt.string(from: Date()),
            "dataController": AgentProfile.current?.companyName ?? "OceanCheck Agent",
            "subjectName": name,
            "policyVersion": policyVersion,
            "personalData": matchingChecks.map { check -> [String: Any] in
                var data: [String: Any] = [
                    "id": check.id,
                    "name": check.customerName,
                    "entityType": check.entityType.rawValue,
                    "status": check.status.rawValue,
                    "createdAt": dateFmt.string(from: check.createdAt),
                ]
                if let v = check.extractedName { data["extractedName"] = v }
                if let v = check.documentType { data["documentType"] = v }
                if let v = check.documentNumber { data["documentNumber"] = v }
                if let v = check.dateOfBirth { data["dateOfBirth"] = v }
                if let v = check.nationality { data["nationality"] = v }
                if let v = check.expiryDate { data["documentExpiry"] = v }
                if let v = check.gender { data["gender"] = v }
                if let v = check.placeOfBirth { data["placeOfBirth"] = v }
                if let v = check.extractedAddress { data["address"] = v }
                if let v = check.amlStatus { data["amlStatus"] = v }
                if let v = check.amlScore { data["amlScore"] = v }
                if let v = check.poaAddress { data["poaAddress"] = v }
                if let v = check.reviewDecision { data["reviewDecision"] = v.rawValue }
                if let v = check.reviewReason { data["reviewReason"] = v }
                if let v = check.completedAt { data["completedAt"] = dateFmt.string(from: v) }
                return data
            },
            "associatedVessels": matchingVessels,
            "consentRecords": matchingConsent.map { c -> [String: Any] in
                var r: [String: Any] = [
                    "type": c.consentType.rawValue,
                    "policyVersion": c.policyVersion,
                    "grantedAt": dateFmt.string(from: c.grantedAt),
                    "active": c.isActive
                ]
                if let w = c.withdrawnAt { r["withdrawnAt"] = dateFmt.string(from: w) }
                return r
            },
            "auditTrail": matchingAudit.map { e -> [String: Any] in
                var r: [String: Any] = [
                    "action": e.action.rawValue,
                    "timestamp": dateFmt.string(from: e.timestamp),
                    "performedBy": e.performedBy
                ]
                if let d = e.detail { r["detail"] = d }
                return r
            }
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: exportData, options: [.prettyPrinted, .sortedKeys]) else { return nil }
        let safeName = name.replacingOccurrences(of: " ", with: "_")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("DSAR_\(safeName)_\(Date().formatted(.iso8601.year().month().day())).json")
        try? FileManager.default.removeItem(at: url)
        try? jsonData.write(to: url)
        return url
    }
}
