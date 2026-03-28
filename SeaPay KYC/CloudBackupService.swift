//
//  CloudBackupService.swift
//  OceanCheck
//
//  iCloud Documents backup and restore.
//  Copies JSON + images to iCloud container. Falls back gracefully if not available.
//

import Foundation
import Combine

@MainActor
class CloudBackupService: ObservableObject {
    static let shared = CloudBackupService()

    @Published var lastBackupDate: Date? = UserDefaults.standard.object(forKey: "lastCloudBackup") as? Date
    @Published var isAvailable: Bool = false

    private var containerURL: URL?

    init() {
        // Check iCloud availability on a background thread
        Task.detached {
            let url = FileManager.default.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents")
            await MainActor.run { [weak self] in
                self?.containerURL = url
                self?.isAvailable = url != nil
            }
        }
    }

    func backup(checksFile: URL, vesselsFile: URL, imagesDir: URL) {
        guard let cloud = containerURL else { return }
        try? FileManager.default.createDirectory(at: cloud, withIntermediateDirectories: true)

        // JSON files
        copyReplace(from: checksFile, to: cloud.appendingPathComponent("kyc_checks.json"))
        copyReplace(from: vesselsFile, to: cloud.appendingPathComponent("vessels.json"))
        let transferLog = checksFile.deletingLastPathComponent().appendingPathComponent("transfer_log.json")
        if FileManager.default.fileExists(atPath: transferLog.path) {
            copyReplace(from: transferLog, to: cloud.appendingPathComponent("transfer_log.json"))
        }

        // Images
        let cloudImages = cloud.appendingPathComponent("captured_documents")
        try? FileManager.default.createDirectory(at: cloudImages, withIntermediateDirectories: true)
        if let files = try? FileManager.default.contentsOfDirectory(atPath: imagesDir.path) {
            for file in files {
                copyReplace(from: imagesDir.appendingPathComponent(file), to: cloudImages.appendingPathComponent(file))
            }
        }

        // Settings — sync full agent profile
        let kvs = NSUbiquitousKeyValueStore.default
        if let profileData = UserDefaults.standard.data(forKey: "agentProfile") {
            kvs.set(profileData, forKey: "agentProfile")
        }
        kvs.set(UserDefaults.standard.string(forKey: "agentName") ?? "", forKey: "agentName")
        kvs.synchronize()

        lastBackupDate = Date()
        UserDefaults.standard.set(lastBackupDate, forKey: "lastCloudBackup")
    }

    func restore(docsDir: URL, imagesDir: URL) -> Bool {
        guard let cloud = containerURL else { return false }

        let checksSource = cloud.appendingPathComponent("kyc_checks.json")
        let vesselsSource = cloud.appendingPathComponent("vessels.json")
        guard FileManager.default.fileExists(atPath: checksSource.path) else { return false }

        copyReplace(from: checksSource, to: docsDir.appendingPathComponent("kyc_checks.json"))
        copyReplace(from: vesselsSource, to: docsDir.appendingPathComponent("vessels.json"))

        // Images
        let cloudImages = cloud.appendingPathComponent("captured_documents")
        if let files = try? FileManager.default.contentsOfDirectory(atPath: cloudImages.path) {
            try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
            for file in files {
                copyReplace(from: cloudImages.appendingPathComponent(file), to: imagesDir.appendingPathComponent(file))
            }
        }

        // Settings — restore full agent profile
        if let profileData = NSUbiquitousKeyValueStore.default.data(forKey: "agentProfile") {
            UserDefaults.standard.set(profileData, forKey: "agentProfile")
            // Also restore agentName for backward compat
            if let profile = try? JSONDecoder().decode(AgentProfile.self, from: profileData) {
                UserDefaults.standard.set(profile.fullName, forKey: "agentName")
            }
        } else if let name = NSUbiquitousKeyValueStore.default.string(forKey: "agentName"), !name.isEmpty {
            UserDefaults.standard.set(name, forKey: "agentName")
        }

        return true
    }

    private func copyReplace(from: URL, to: URL) {
        try? FileManager.default.removeItem(at: to)
        try? FileManager.default.copyItem(at: from, to: to)
    }
}
