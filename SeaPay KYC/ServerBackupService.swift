//
//  ServerBackupService.swift
//  OceanCheck
//
//  Server-side data redundancy — pushes ALL vessels + checks to backend
//  on every save. Independent of workspaces. Recovers data on fresh install.
//

import Foundation
import os.log

private let backupLogger = Logger(subsystem: "com.seapay.kyc", category: "ServerBackup")

@MainActor
final class ServerBackupService {
    static let shared = ServerBackupService()

    private let baseURL = "https://seapay.me/oceancheck/api"
    private var backupVersion: Int {
        get { UserDefaults.standard.integer(forKey: "serverBackupVersion") }
        set { UserDefaults.standard.set(newValue, forKey: "serverBackupVersion") }
    }
    private var pendingBackup = false
    private var debounceTask: Task<Void, Never>?

    // MARK: - Push Backup (debounced — 3 second delay to batch rapid saves)

    func scheduleBackup(vessels: [Vessel], checks: [KYCCheck]) {
        guard let profile = AgentProfile.current else { return }
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            await pushBackup(agentId: profile.agentId, agentName: profile.fullName, vessels: vessels, checks: checks)
        }
    }

    private func pushBackup(agentId: String, agentName: String, vessels: [Vessel], checks: [KYCCheck]) async {
        // Don't push empty data — safety
        guard !vessels.isEmpty || !checks.isEmpty else { return }

        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        guard let vesselsObj = try? JSONSerialization.jsonObject(with: encoder.encode(vessels)),
              let checksObj = try? JSONSerialization.jsonObject(with: encoder.encode(checks)) else { return }

        let body: [String: Any] = [
            "vessels": vesselsObj,
            "checks": checksObj,
            "agent_name": agentName,
        ]

        guard let url = URL(string: "\(baseURL)/backup.php?action=push") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(agentId, forHTTPHeaderField: "X-Agent-Id")
        request.timeoutInterval = 30

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 201 else {
                backupLogger.error("Backup push failed: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                return
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let version = json["backup_version"] as? Int {
                backupVersion = version
                backupLogger.info("Backup v\(version) pushed (\(vessels.count) vessels, \(checks.count) checks)")
            }
        } catch {
            backupLogger.error("Backup push error: \(error.localizedDescription)")
        }
    }

    // MARK: - Pull Backup (restore from server)

    func pullBackup() async -> (vessels: [Vessel], checks: [KYCCheck])? {
        guard let profile = AgentProfile.current else { return nil }
        guard let url = URL(string: "\(baseURL)/backup.php?action=pull") else { return nil }

        var request = URLRequest(url: url)
        request.setValue(profile.agentId, forHTTPHeaderField: "X-Agent-Id")
        request.timeoutInterval = 30

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let backup = json["backup"] as? [String: Any] else { return nil }

            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601

            var vessels: [Vessel] = []
            var checks: [KYCCheck] = []

            if let vesselsRaw = backup["vessels"] {
                let vesselsData = try JSONSerialization.data(withJSONObject: vesselsRaw)
                vessels = (try? decoder.decode([Vessel].self, from: vesselsData)) ?? []
            }
            if let checksRaw = backup["checks"] {
                let checksData = try JSONSerialization.data(withJSONObject: checksRaw)
                checks = (try? decoder.decode([KYCCheck].self, from: checksData)) ?? []
            }

            backupLogger.info("Backup restored: \(vessels.count) vessels, \(checks.count) checks")
            return (vessels, checks)
        } catch {
            backupLogger.error("Backup pull error: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Check Status

    func hasServerBackup() async -> Bool {
        guard let profile = AgentProfile.current else { return false }
        guard let url = URL(string: "\(baseURL)/backup.php?action=status") else { return false }

        var request = URLRequest(url: url)
        request.setValue(profile.agentId, forHTTPHeaderField: "X-Agent-Id")
        request.timeoutInterval = 10

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return json["has_backup"] as? Bool ?? false
            }
        } catch {}
        return false
    }
}
