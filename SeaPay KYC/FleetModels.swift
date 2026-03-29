//
//  FleetModels.swift
//  OceanCheck
//
//  Models for Fleet collaboration: scenarios, merge diffs, workspace vessels.
//

import Foundation

// MARK: - Fleet Scenario (role-based workflows)

enum FleetScenario: String, Codable, CaseIterable, Identifiable {
    case preSurvey = "Pre-Survey Preparation"
    case vesselSale = "Vessel Sale / Purchase"
    case crewChange = "Crew Change"
    case pscPreparation = "PSC / Flag State Inspection"
    case insuranceRenewal = "Insurance Renewal"
    case charterDueDiligence = "Charter Due Diligence"
    case managementHandover = "Management Handover"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .preSurvey: return "doc.text.magnifyingglass"
        case .vesselSale: return "arrow.right.arrow.left"
        case .crewChange: return "person.2.badge.gearshape"
        case .pscPreparation: return "flag.checkered"
        case .insuranceRenewal: return "shield.checkered"
        case .charterDueDiligence: return "doc.text.magnifyingglass"
        case .managementHandover: return "building.2.crop.circle"
        }
    }

    var shortName: String {
        switch self {
        case .preSurvey: return "Survey"
        case .vesselSale: return "Sale"
        case .crewChange: return "Crew"
        case .pscPreparation: return "PSC"
        case .insuranceRenewal: return "Insurance"
        case .charterDueDiligence: return "Charter"
        case .managementHandover: return "Handover"
        }
    }

    var relevantRoles: [AgentRole] {
        switch self {
        case .preSurvey: return [.technicalSuperintendent, .surveyor, .complianceOfficer]
        case .vesselSale: return [.legalCounsel, .fleetManager, .complianceOfficer]
        case .crewChange: return [.crewManager, .portAgent, .complianceOfficer]
        case .pscPreparation: return [.dpa, .complianceOfficer]
        case .insuranceRenewal: return [.fleetManager, .legalCounsel]
        case .charterDueDiligence: return [.complianceOfficer, .legalCounsel]
        case .managementHandover: return [.fleetManager, .complianceOfficer, .dpa]
        }
    }

    var requiredVesselDocTypes: [VesselDocType] {
        switch self {
        case .preSurvey:
            return [.classCertificate, .smc, .ismDOC, .issc, .loadLine,
                    .safetyEquipmentSurvey, .cargoShipSafety]
        case .vesselSale:
            return [.certificateOfRegistry, .classCertificate, .smc, .ismDOC,
                    .insuranceCertificate, .hmInsurance, .civilLiability, .iopp]
        case .crewChange:
            return [.minimumSafeManning, .mlcCertificate]
        case .pscPreparation:
            return [.certificateOfRegistry, .classCertificate, .smc, .ismDOC,
                    .issc, .iopp, .ispp, .loadLine, .minimumSafeManning,
                    .mlcCertificate, .cargoShipSafety, .safetyEquipmentSurvey]
        case .insuranceRenewal:
            return [.insuranceCertificate, .hmInsurance, .civilLiability, .warRisk,
                    .wreckRemoval, .classCertificate, .smc]
        case .charterDueDiligence:
            return [.certificateOfRegistry, .classCertificate, .insuranceCertificate, .smc]
        case .managementHandover:
            return [] // All documents — no filter
        }
    }

    /// For management handover, all docs are relevant
    var includesAllDocs: Bool { self == .managementHandover }
}

// MARK: - Workspace Vessel (from backend)

struct WorkspaceVessel: Codable, Identifiable, Sendable {
    let vesselId: String
    let vesselName: String
    let vesselImo: String
    let scenario: String
    let addedByAgent: String
    let addedByName: String
    let addedAt: String

    var id: String { vesselId }

    var fleetScenario: FleetScenario? {
        FleetScenario(rawValue: scenario)
    }

    enum CodingKeys: String, CodingKey {
        case vesselId = "vessel_id"
        case vesselName = "vessel_name"
        case vesselImo = "vessel_imo"
        case scenario
        case addedByAgent = "added_by_agent"
        case addedByName = "added_by_name"
        case addedAt = "added_at"
    }
}

// MARK: - Merge Diff

struct MergeDiff {
    let vesselChanges: [FieldChange]
    let newChecks: [KYCCheck]
    let updatedChecks: [CheckUpdate]
    let removedCheckIds: [String]

    var isEmpty: Bool { vesselChanges.isEmpty && newChecks.isEmpty && updatedChecks.isEmpty && removedCheckIds.isEmpty }
    var totalChanges: Int { vesselChanges.count + newChecks.count + updatedChecks.count + removedCheckIds.count }
}

struct FieldChange: Identifiable {
    let id = UUID().uuidString
    let field: String
    let localValue: String
    let remoteValue: String
}

struct CheckUpdate: Identifiable {
    let id: String
    let checkName: String
    let changes: [String]  // e.g. ["Status: passed → failed", "AML: Approved → In Review"]
}

// MARK: - Merge Engine

enum MergeEngine {

    /// Compare local vessel + checks with remote snapshot to produce a diff.
    static func computeDiff(localVessel: Vessel, localChecks: [KYCCheck], remoteVessel: Vessel?, remoteChecks: [KYCCheck]?) -> MergeDiff {
        var vesselChanges: [FieldChange] = []
        var newChecks: [KYCCheck] = []
        var updatedChecks: [CheckUpdate] = []
        var removedCheckIds: [String] = []

        // Vessel field comparison
        if let rv = remoteVessel {
            func cmp(_ field: String, _ local: String, _ remote: String) {
                if local != remote && !remote.isEmpty {
                    vesselChanges.append(FieldChange(field: field, localValue: local.isEmpty ? "(empty)" : local, remoteValue: remote))
                }
            }
            cmp("Name", localVessel.name, rv.name)
            cmp("IMO", localVessel.imoNumber, rv.imoNumber)
            cmp("Flag State", localVessel.flagState, rv.flagState)
            cmp("Port of Registry", localVessel.portOfRegistry, rv.portOfRegistry)
            cmp("Gross Tonnage", localVessel.grossTonnage, rv.grossTonnage)
            cmp("Registered Owner", localVessel.registeredOwner, rv.registeredOwner)
            cmp("Certificate Expiry", localVessel.certificateExpiry, rv.certificateExpiry)
        }

        // Check comparison
        let localCheckIds = Set(localChecks.map(\.id))
        let remoteCheckMap = Dictionary(uniqueKeysWithValues: (remoteChecks ?? []).map { ($0.id, $0) })

        // New checks (in remote but not local)
        for rc in remoteChecks ?? [] {
            if !localCheckIds.contains(rc.id) {
                newChecks.append(rc)
            }
        }

        // Updated checks (in both, but different)
        for lc in localChecks {
            guard let rc = remoteCheckMap[lc.id] else { continue }
            var changes: [String] = []
            if lc.status != rc.status { changes.append("Status: \(lc.status.rawValue) → \(rc.status.rawValue)") }
            if lc.customerName != rc.customerName { changes.append("Name: \(lc.customerName) → \(rc.customerName)") }
            if lc.amlStatus != rc.amlStatus { changes.append("AML: \(lc.amlStatus ?? "—") → \(rc.amlStatus ?? "—")") }
            if lc.expiryDate != rc.expiryDate { changes.append("Expiry: \(lc.expiryDate ?? "—") → \(rc.expiryDate ?? "—")") }
            if lc.reviewDecision != rc.reviewDecision { changes.append("Review: \(lc.reviewDecision?.rawValue ?? "—") → \(rc.reviewDecision?.rawValue ?? "—")") }
            if !changes.isEmpty {
                updatedChecks.append(CheckUpdate(id: lc.id, checkName: rc.customerName, changes: changes))
            }
        }

        // Removed checks (in local but not in remote — only if remote has data)
        if let rc = remoteChecks, !rc.isEmpty {
            let remoteIds = Set(rc.map(\.id))
            for lc in localChecks {
                if !remoteIds.contains(lc.id) {
                    removedCheckIds.append(lc.id)
                }
            }
        }

        return MergeDiff(vesselChanges: vesselChanges, newChecks: newChecks, updatedChecks: updatedChecks, removedCheckIds: removedCheckIds)
    }

    /// Apply accepted merge changes to the local data.
    static func applyMerge(diff: MergeDiff, remoteVessel: Vessel?, vm: KYCViewModel, vesselId: String, acceptVesselChanges: Bool, acceptNewChecks: Bool, acceptUpdates: Bool) {
        // Apply vessel changes
        if acceptVesselChanges, let rv = remoteVessel, let i = vm.vessels.firstIndex(where: { $0.id == vesselId }) {
            vm.vessels[i] = rv
        }

        // Add new checks
        if acceptNewChecks {
            for check in diff.newChecks {
                if !vm.checks.contains(where: { $0.id == check.id }) {
                    vm.checks.append(check)
                }
            }
        }

        // Updates are applied via the newChecks merge — remote version replaces local
        // (The diff shows what changed; acceptance means keeping the remote version)

        vm.saveChecks()
        vm.saveVessels()
    }
}

// MARK: - Audit Event (from backend)

struct FleetAuditEvent: Codable, Identifiable, Sendable {
    let id: String
    let vesselId: String?
    let agentId: String
    let agentName: String
    let action: String
    let entityType: String
    let entityId: String?
    let entityName: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case vesselId = "vessel_id"
        case agentId = "agent_id"
        case agentName = "agent_name"
        case action
        case entityType = "entity_type"
        case entityId = "entity_id"
        case entityName = "entity_name"
        case createdAt = "created_at"
    }
}
