//
//  CollaborationService.swift
//  OceanCheck
//
//  Client for the OceanCheck Collaboration API on seapay.me.
//  Handles workspace management, data sync, and activity feed.
//

import Foundation
import Combine
import os.log

private let collabLogger = Logger(subsystem: "com.seapay.kyc", category: "Collaboration")

// MARK: - API Models

struct WorkspaceInfo: Codable, Sendable, Hashable {
    let workspaceId: String
    let name: String
    let code: String
    let token: String

    enum CodingKeys: String, CodingKey {
        case workspaceId = "workspace_id"
        case name, code, token
    }
}

struct WorkspaceDetail: Codable, Sendable {
    let workspace: WorkspaceMetadata
    let agents: [WorkspaceAgent]
    let latestVersion: Int

    enum CodingKeys: String, CodingKey {
        case workspace, agents
        case latestVersion = "latest_version"
    }
}

struct WorkspaceMetadata: Codable, Sendable {
    let id: String
    let name: String
    let code: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, name, code
        case createdAt = "created_at"
    }
}

struct WorkspaceAgent: Codable, Identifiable, Sendable {
    let agentId: String
    let agentName: String
    let agentOrg: String
    let agentRole: String
    let joinedAt: String
    let lastSync: String?
    let isActive: Int  // MySQL TINYINT returns 0/1, not true/false

    var id: String { agentId }
    var active: Bool { isActive != 0 }

    enum CodingKeys: String, CodingKey {
        case agentId = "agent_id"
        case agentName = "agent_name"
        case agentOrg = "agent_org"
        case agentRole = "agent_role"
        case joinedAt = "joined_at"
        case lastSync = "last_sync"
        case isActive = "is_active"
    }
}

struct SyncStatus: Codable, Sendable {
    let latestVersion: Int
    let hasUpdates: Bool
    let updatesAvailable: Int
    let activeAgents: Int

    enum CodingKeys: String, CodingKey {
        case latestVersion = "latest_version"
        case hasUpdates = "has_updates"
        case updatesAvailable = "updates_available"
        case activeAgents = "active_agents"
    }
}

struct SyncSnapshot: Codable, Sendable {
    let id: String
    let agentId: String
    let agentName: String
    let version: Int
    let vessels: [Vessel]?
    let checks: [KYCCheck]?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case agentId = "agent_id"
        case agentName = "agent_name"
        case version, vessels, checks
        case createdAt = "created_at"
    }
}

struct ActivityEvent: Codable, Identifiable, Sendable {
    let id: String
    let agentId: String
    let agentName: String
    let action: String
    let entityType: String
    let entityName: String
    let detail: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case agentId = "agent_id"
        case agentName = "agent_name"
        case action
        case entityType = "entity_type"
        case entityName = "entity_name"
        case detail
        case createdAt = "created_at"
    }
}

// MARK: - Collaboration Service

@MainActor
final class CollaborationService: ObservableObject {
    static let shared = CollaborationService()

    private let baseURL = "https://seapay.me/oceancheck/api"

    // Persisted workspace list — agent can belong to multiple workspaces
    @Published private(set) var storedWorkspaces: [WorkspaceInfo] = [] {
        didSet { saveWorkspaces() }
    }

    // Currently selected workspace (for API calls)
    private var _workspace: WorkspaceInfo? {
        didSet {
            if let ws = _workspace {
                let data = try? JSONEncoder().encode(ws)
                UserDefaults.standard.set(data, forKey: "activeWorkspace")
            } else {
                UserDefaults.standard.removeObject(forKey: "activeWorkspace")
            }
        }
    }

    var workspace: WorkspaceInfo? { _workspace }
    var isConnected: Bool { _workspace != nil }

    private var syncVersion: Int {
        get { UserDefaults.standard.integer(forKey: "syncVersion") }
        set { UserDefaults.standard.set(newValue, forKey: "syncVersion") }
    }

    init() {
        // Load stored workspaces
        if let data = UserDefaults.standard.data(forKey: "storedWorkspaces") {
            storedWorkspaces = (try? JSONDecoder().decode([WorkspaceInfo].self, from: data)) ?? []
        }
        // Load active workspace (backward compatible)
        if let data = UserDefaults.standard.data(forKey: "activeWorkspace") {
            _workspace = try? JSONDecoder().decode(WorkspaceInfo.self, from: data)
        }
        // Migration: if we have an active workspace but empty stored list, add it
        if let ws = _workspace, !storedWorkspaces.contains(where: { $0.workspaceId == ws.workspaceId }) {
            storedWorkspaces.append(ws)
        }
    }

    // MARK: - Multi-Workspace

    func selectWorkspace(_ info: WorkspaceInfo) {
        _workspace = info
        syncVersion = 0
    }

    func deselectWorkspace() {
        _workspace = nil
        syncVersion = 0
    }

    private func saveWorkspaces() {
        let data = try? JSONEncoder().encode(storedWorkspaces)
        UserDefaults.standard.set(data, forKey: "storedWorkspaces")
    }

    private func addToStored(_ info: WorkspaceInfo) {
        if let i = storedWorkspaces.firstIndex(where: { $0.workspaceId == info.workspaceId }) {
            storedWorkspaces[i] = info  // Update token/name
        } else {
            storedWorkspaces.append(info)
        }
    }

    private func removeFromStored(_ workspaceId: String) {
        storedWorkspaces.removeAll { $0.workspaceId == workspaceId }
    }

    // MARK: - Workspace Management

    func createWorkspace(name: String) async throws -> WorkspaceInfo {
        guard let profile = AgentProfile.current else { throw CollabError.noProfile }

        let body: [String: Any] = [
            "name": name,
            "agent_id": profile.agentId,
            "agent_name": profile.fullName,
            "agent_org": profile.companyName ?? "",
            "agent_role": profile.displayRole,
        ]

        let data = try await request("workspace.php?action=create", method: "POST", body: body)
        let info = try JSONDecoder().decode(WorkspaceInfo.self, from: data)
        addToStored(info)
        _workspace = info
        syncVersion = 0
        return info
    }

    func joinWorkspace(code: String) async throws -> WorkspaceInfo {
        guard let profile = AgentProfile.current else { throw CollabError.noProfile }

        let body: [String: Any] = [
            "code": code.uppercased(),
            "agent_id": profile.agentId,
            "agent_name": profile.fullName,
            "agent_org": profile.companyName ?? "",
            "agent_role": profile.displayRole,
        ]

        let data = try await request("workspace.php?action=join", method: "POST", body: body)
        let info = try JSONDecoder().decode(WorkspaceInfo.self, from: data)
        addToStored(info)
        _workspace = info
        syncVersion = 0
        return info
    }

    func getWorkspaceInfo() async throws -> WorkspaceDetail {
        let data = try await authenticatedRequest("workspace.php?action=info")
        return try JSONDecoder().decode(WorkspaceDetail.self, from: data)
    }

    func updateWorkspace(name: String, scenario: String?) async throws {
        var body: [String: Any] = ["name": name]
        if let scenario { body["scenario"] = scenario }
        _ = try await authenticatedRequest("workspace.php?action=update", method: "POST", body: body)

        // Update stored workspace with new name so list + detail stay in sync
        if let ws = _workspace {
            let updated = WorkspaceInfo(workspaceId: ws.workspaceId, name: name, code: ws.code, token: ws.token)
            _workspace = updated
            addToStored(updated)
        }
    }

    func leaveWorkspace() async throws {
        let leavingId = _workspace?.workspaceId
        _ = try await authenticatedRequest("workspace.php?action=leave", method: "POST")
        _workspace = nil
        syncVersion = 0
        if let leavingId { removeFromStored(leavingId) }
    }

    func disconnect() {
        _workspace = nil
        syncVersion = 0
    }

    // MARK: - Sync

    func pushData(vessels: [Vessel], checks: [KYCCheck]) async throws -> Int {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let vesselsArray = try JSONSerialization.jsonObject(with: encoder.encode(vessels))
        let checksArray = try JSONSerialization.jsonObject(with: encoder.encode(checks))

        let body: [String: Any] = [
            "vessels": vesselsArray,
            "checks": checksArray,
        ]

        let data = try await authenticatedRequest("sync.php?action=push", method: "POST", body: body)
        let response = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let version = response?["version"] as? Int ?? 0
        syncVersion = version

        #if DEBUG
        collabLogger.debug("Pushed sync v\(version)")
        #endif

        return version
    }

    func pullLatest() async throws -> SyncSnapshot? {
        let data = try await authenticatedRequest("sync.php?action=pull&since=\(syncVersion)")
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601

        let response = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        // Check if we got snapshots (incremental) or snapshot (latest)
        if let snapshots = response?["snapshots"] as? [[String: Any]], !snapshots.isEmpty {
            // Return the latest snapshot from the incremental set
            if let lastData = try? JSONSerialization.data(withJSONObject: snapshots.last!),
               let snapshot = try? decoder.decode(SyncSnapshot.self, from: lastData) {
                syncVersion = snapshot.version
                return snapshot
            }
        } else if let snapshotDict = response?["snapshot"] as? [String: Any] {
            let snapshotData = try JSONSerialization.data(withJSONObject: snapshotDict)
            let snapshot = try decoder.decode(SyncSnapshot.self, from: snapshotData)
            syncVersion = snapshot.version
            return snapshot
        }

        return nil
    }

    func checkForUpdates() async throws -> SyncStatus {
        let data = try await authenticatedRequest("sync.php?action=status&local_version=\(syncVersion)")
        return try JSONDecoder().decode(SyncStatus.self, from: data)
    }

    // MARK: - Per-Vessel Sync

    func pushVessel(vessel: Vessel, checks: [KYCCheck]) async throws -> Int {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let vesselObj = try JSONSerialization.jsonObject(with: encoder.encode([vessel]))
        let checksObj = try JSONSerialization.jsonObject(with: encoder.encode(checks))

        let body: [String: Any] = [
            "vessels": vesselObj,
            "checks": checksObj,
            "vessel_id": vessel.id,
        ]

        let data = try await authenticatedRequest("sync.php?action=push", method: "POST", body: body)
        let response = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let version = response?["version"] as? Int ?? 0
        syncVersion = version
        return version
    }

    func pullVessel(vesselId: String) async throws -> SyncSnapshot? {
        let data = try await authenticatedRequest("sync.php?action=pull&vessel_id=\(vesselId)")
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601

        let response = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let snapshotDict = response?["snapshot"] as? [String: Any] {
            let snapshotData = try JSONSerialization.data(withJSONObject: snapshotDict)
            let snapshot = try decoder.decode(SyncSnapshot.self, from: snapshotData)
            return snapshot
        }
        return nil
    }

    /// Returns raw snapshot dictionary for a vessel — allows callers to decode
    /// vessels and checks independently so one bad field doesn't kill the whole pull.
    func pullVesselRaw(vesselId: String) async throws -> [String: Any]? {
        let data = try await authenticatedRequest("sync.php?action=pull&vessel_id=\(vesselId)")
        let response = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return response?["snapshot"] as? [String: Any]
    }

    // MARK: - Workspace Vessel Management

    func addVesselToWorkspace(vessel: Vessel, scenario: FleetScenario) async throws {
        let body: [String: Any] = [
            "vessel_id": vessel.id,
            "vessel_name": vessel.name,
            "vessel_imo": vessel.imoNumber,
            "scenario": scenario.rawValue,
        ]
        _ = try await authenticatedRequest("workspace.php?action=add_vessel", method: "POST", body: body)
    }

    func removeVesselFromWorkspace(vesselId: String) async throws {
        _ = try await authenticatedRequest("workspace.php?action=remove_vessel", method: "POST", body: ["vessel_id": vesselId])
    }

    func listWorkspaceVessels() async throws -> [WorkspaceVessel] {
        let data = try await authenticatedRequest("workspace.php?action=list_vessels")
        let response = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let arr = response?["vessels"] as? [[String: Any]] else { return [] }
        let arrData = try JSONSerialization.data(withJSONObject: arr)
        return (try? JSONDecoder().decode([WorkspaceVessel].self, from: arrData)) ?? []
    }

    // MARK: - Audit Trail

    func getAuditTrail(vesselId: String? = nil, limit: Int = 30) async throws -> [FleetAuditEvent] {
        var endpoint = "workspace.php?action=audit&limit=\(limit)"
        if let vid = vesselId { endpoint += "&vessel_id=\(vid)" }
        let data = try await authenticatedRequest(endpoint)
        let response = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let arr = response?["events"] as? [[String: Any]] else { return [] }
        let arrData = try JSONSerialization.data(withJSONObject: arr)
        return (try? JSONDecoder().decode([FleetAuditEvent].self, from: arrData)) ?? []
    }

    // MARK: - Activity

    func getActivity(limit: Int = 30) async throws -> [ActivityEvent] {
        let data = try await authenticatedRequest("activity.php?limit=\(limit)")
        let response = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let eventsArray = response?["events"] as? [[String: Any]] else { return [] }
        let eventsData = try JSONSerialization.data(withJSONObject: eventsArray)
        return (try? JSONDecoder().decode([ActivityEvent].self, from: eventsData)) ?? []
    }

    // MARK: - Networking

    private func request(_ endpoint: String, method: String = "GET", body: [String: Any]? = nil) async throws -> Data {
        guard let url = URL(string: "\(baseURL)/\(endpoint)") else { throw CollabError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 15

        if let body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw CollabError.invalidResponse }

        if http.statusCode >= 400 {
            let errMsg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String ?? "Server error"
            throw CollabError.serverError(http.statusCode, errMsg)
        }

        return data
    }

    private func authenticatedRequest(_ endpoint: String, method: String = "GET", body: [String: Any]? = nil) async throws -> Data {
        guard let token = _workspace?.token else { throw CollabError.notConnected }
        guard let url = URL(string: "\(baseURL)/\(endpoint)") else { throw CollabError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15

        if let body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw CollabError.invalidResponse }

        if http.statusCode == 401 {
            _workspace = nil
            throw CollabError.notConnected
        }
        if http.statusCode >= 400 {
            let errMsg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String ?? "Server error"
            throw CollabError.serverError(http.statusCode, errMsg)
        }

        return data
    }
}

// MARK: - Errors

enum CollabError: LocalizedError {
    case noProfile
    case notConnected
    case invalidURL
    case invalidResponse
    case serverError(Int, String)

    var errorDescription: String? {
        switch self {
        case .noProfile: return "Set up your agent profile first."
        case .notConnected: return "Not connected to a workspace."
        case .invalidURL: return "Invalid server URL."
        case .invalidResponse: return "Invalid response from server."
        case .serverError(let code, let msg): return "Server error (\(code)): \(msg)"
        }
    }
}
