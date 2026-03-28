//
//  AgentProfile.swift
//  OceanCheck
//
//  Structured agent identity — replaces loose agentName string.
//  Persisted as JSON in UserDefaults; API keys remain in Keychain.
//

import Foundation
import CryptoKit

// MARK: - Agent Role

enum AgentRole: String, Codable, CaseIterable, Identifiable {
    case dpa = "Designated Person Ashore"
    case fleetManager = "Fleet Manager"
    case portAgent = "Port Agent"
    case complianceOfficer = "Compliance Officer"
    case crewManager = "Crewing Manager"
    case technicalSuperintendent = "Technical Superintendent"
    case surveyor = "Surveyor"
    case legalCounsel = "Legal Counsel"
    case other = "Other"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dpa: return "shield.checkered"
        case .fleetManager: return "building.2"
        case .portAgent: return "ferry"
        case .complianceOfficer: return "checkmark.seal"
        case .crewManager: return "person.3"
        case .technicalSuperintendent: return "wrench.and.screwdriver"
        case .surveyor: return "doc.text.magnifyingglass"
        case .legalCounsel: return "scale.3d"
        case .other: return "person.badge.key"
        }
    }

    var shortTitle: String {
        switch self {
        case .dpa: return "DPA"
        case .fleetManager: return "Fleet Mgr"
        case .portAgent: return "Port Agent"
        case .complianceOfficer: return "Compliance"
        case .crewManager: return "Crewing Mgr"
        case .technicalSuperintendent: return "Tech Supt"
        case .surveyor: return "Surveyor"
        case .legalCounsel: return "Legal"
        case .other: return "Agent"
        }
    }
}

// MARK: - Agent Profile

struct AgentProfile: Codable, Equatable {
    var firstName: String
    var lastName: String
    let agentId: String

    var companyName: String?
    var role: AgentRole?
    var customRoleTitle: String?
    var jurisdiction: String?
    var licenseNumber: String?
    var contactEmail: String?

    var profileImageData: Data?

    let createdAt: Date
    var updatedAt: Date

    // MARK: - Computed

    var fullName: String {
        "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
    }

    var shortName: String {
        let f = firstName.trimmingCharacters(in: .whitespaces)
        let l = lastName.trimmingCharacters(in: .whitespaces)
        guard !f.isEmpty else { return l }
        guard !l.isEmpty else { return f }
        return "\(f.prefix(1)). \(l)"
    }

    var initials: String {
        let f = firstName.trimmingCharacters(in: .whitespaces).prefix(1).uppercased()
        let l = lastName.trimmingCharacters(in: .whitespaces).prefix(1).uppercased()
        return "\(f)\(l)"
    }

    var displayRole: String {
        if let role, role == .other { return customRoleTitle ?? "" }
        return role?.rawValue ?? ""
    }

    var profileLine: String {
        var parts: [String] = []
        let r = displayRole
        if !r.isEmpty { parts.append(r) }
        if let co = companyName, !co.isEmpty { parts.append(co) }
        guard !parts.isEmpty else { return fullName }
        return "\(fullName), \(parts.joined(separator: " — "))"
    }

    var signatureLine: String {
        let name = shortName.isEmpty ? fullName : shortName
        let org = (companyName?.isEmpty == false) ? (companyName ?? "OceanCheck") : "OceanCheck"
        return "\(name), \(org)"
    }

    var roleAndOrg: String? {
        var parts: [String] = []
        let r = displayRole
        if !r.isEmpty { parts.append(r) }
        if let co = companyName, !co.isEmpty { parts.append(co) }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " — ")
    }

    // MARK: - ID Generation

    static func generateAgentId(firstName: String, lastName: String, company: String?, createdAt: Date) -> String {
        let input = "\(firstName)\(lastName)\(company ?? "")\(createdAt.timeIntervalSince1970)"
        let digest = SHA256.hash(data: Data(input.utf8))
        let hex = digest.prefix(4).map { String(format: "%02X", $0) }.joined()
        return "OC-\(hex.prefix(4))-\(hex.suffix(4))"
    }

    // MARK: - Persistence

    private static let storageKey = "agentProfile"

    static var current: AgentProfile? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(AgentProfile.self, from: data)
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: AgentProfile.storageKey)
        }
        // Backward compatibility — other parts of app read this
        UserDefaults.standard.set(fullName, forKey: "agentName")
    }

    static func delete() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        UserDefaults.standard.removeObject(forKey: "agentName")
    }

    // MARK: - Migration

    /// Migrate from legacy agentName string to full profile
    static func migrateIfNeeded() {
        guard UserDefaults.standard.data(forKey: storageKey) == nil,
              let name = UserDefaults.standard.string(forKey: "agentName"), !name.isEmpty else { return }

        let parts = name.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1)
        let first = String(parts.first ?? "")
        let last = parts.count > 1 ? String(parts.last ?? "") : ""
        let now = Date()

        let profile = AgentProfile(
            firstName: first,
            lastName: last,
            agentId: generateAgentId(firstName: first, lastName: last, company: nil, createdAt: now),
            createdAt: now,
            updatedAt: now
        )
        profile.save()
    }
}
