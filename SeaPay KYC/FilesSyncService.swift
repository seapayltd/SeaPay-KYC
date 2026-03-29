//
//  FilesSyncService.swift
//  OceanCheck
//
//  Syncs document images between devices via the backend file storage.
//  Uploads missing local files on push, downloads missing remote files on pull.
//

import Foundation
import Combine
import os.log

private let fileSyncLogger = Logger(subsystem: "com.seapay.kyc", category: "FileSync")

struct RemoteFile: Codable, Sendable {
    let id: String
    let filename: String
    let originalName: String
    let mimeType: String
    let sizeBytes: Int
    let uploadedByName: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, filename
        case originalName = "original_name"
        case mimeType = "mime_type"
        case sizeBytes = "size_bytes"
        case uploadedByName = "uploaded_by_name"
        case createdAt = "created_at"
    }
}

@MainActor
class FilesSyncService: ObservableObject {
    static let shared = FilesSyncService()

    @Published var syncProgress: String?
    @Published var isSyncing = false

    private let baseURL = "https://seapay.me/oceancheck/api"

    // MARK: - Collect ALL image filenames for a vessel

    private func collectLocalFilenames(vesselId: String, vm: KYCViewModel) -> Set<String> {
        var files: Set<String> = []

        // Vessel photo
        if let vessel = vm.vessels.first(where: { $0.id == vesselId }), let photo = vessel.photoFilename {
            files.insert(photo)
        }

        // All checks for this vessel
        let checks = vm.checksForVessel(vesselId)
        for check in checks {
            // ID scan images (front/back)
            for path in check.documentImagePaths ?? [] { files.insert(path) }
            // Profile photo
            if let photo = check.profilePhoto { files.insert(photo) }
            // Crew document images (certificates, seaman's book, etc.)
            for doc in check.documents ?? [] {
                for path in doc.imagePaths { files.insert(path) }
            }
        }

        return files
    }

    // MARK: - Upload All Missing Files

    func uploadMissingFiles(vesselId: String, vm: KYCViewModel) async {
        guard let token = CollaborationService.shared.workspace?.token else {
            fileSyncLogger.warning("Upload skipped — no workspace token")
            return
        }

        let localFiles = collectLocalFilenames(vesselId: vesselId, vm: vm)
        guard !localFiles.isEmpty else { return }

        let remoteFilenames: Set<String>
        do {
            remoteFilenames = Set(try await listRemoteFiles(vesselId: vesselId).map(\.filename))
        } catch {
            fileSyncLogger.error("Upload: failed to list remote files: \(error.localizedDescription)")
            syncProgress = "Upload failed — could not reach server"
            return
        }

        let missing = localFiles.subtracting(remoteFilenames)
        guard !missing.isEmpty else { return }

        isSyncing = true
        var uploaded = 0
        var failed = 0
        let activityId = SyncActivityMonitor.shared.begin("Uploading \(missing.count) file\(missing.count == 1 ? "" : "s")", type: .upload)

        for filename in missing {
            let filePath = vm.imagesDir.appendingPathComponent(filename)
            guard let fileData = try? Data(contentsOf: filePath) else {
                fileSyncLogger.warning("Local file not found: \(filename)")
                failed += 1; continue
            }

            SyncActivityMonitor.shared.update(activityId, description: "Uploading \(uploaded + 1)/\(missing.count)")
            syncProgress = "Uploading \(uploaded + 1)/\(missing.count)..."

            if await uploadFile(filename: filename, data: fileData, vesselId: vesselId, token: token) {
                uploaded += 1
            } else { failed += 1 }
        }

        SyncActivityMonitor.shared.complete(activityId, success: uploaded > 0)
        if failed > 0 { syncProgress = "\(failed) file\(failed == 1 ? "" : "s") failed to upload" }
        else { syncProgress = nil }
        isSyncing = false
    }

    // MARK: - Download All Missing Files

    func downloadMissingFiles(vesselId: String, vm: KYCViewModel) async {
        guard let token = CollaborationService.shared.workspace?.token else {
            fileSyncLogger.warning("Download skipped — no workspace token")
            return
        }

        let remoteFiles: [RemoteFile]
        do {
            remoteFiles = try await listRemoteFiles(vesselId: vesselId)
        } catch {
            fileSyncLogger.error("Download: failed to list remote files: \(error.localizedDescription)")
            syncProgress = "Download failed — could not reach server"
            return
        }

        guard !remoteFiles.isEmpty else { return }

        let fm = FileManager.default
        let missingFiles = remoteFiles.filter { !fm.fileExists(atPath: vm.imagesDir.appendingPathComponent($0.filename).path) }
        guard !missingFiles.isEmpty else { return }

        isSyncing = true
        var downloaded = 0
        var failed = 0
        let activityId = SyncActivityMonitor.shared.begin("Downloading \(missingFiles.count) file\(missingFiles.count == 1 ? "" : "s")", type: .download)

        for remote in missingFiles {
            SyncActivityMonitor.shared.update(activityId, description: "Downloading \(downloaded + 1)/\(missingFiles.count)")
            syncProgress = "Downloading \(downloaded + 1)/\(missingFiles.count)..."

            if let data = await downloadFile(filename: remote.filename, token: token) {
                let localPath = vm.imagesDir.appendingPathComponent(remote.filename)
                do {
                    try data.write(to: localPath)
                    downloaded += 1
                } catch {
                    failed += 1
                    fileSyncLogger.error("Failed to write \(remote.filename): \(error.localizedDescription)")
                }
            } else { failed += 1 }
        }

        SyncActivityMonitor.shared.complete(activityId, success: downloaded > 0)
        for f in missingFiles { vm.invalidateImageCache(filename: f.filename) }
        if failed > 0 { syncProgress = "\(failed) file\(failed == 1 ? "" : "s") failed to download" }
        else { syncProgress = nil }
        isSyncing = false
    }

    // MARK: - List Remote Files

    func listRemoteFiles(vesselId: String) async throws -> [RemoteFile] {
        guard let token = CollaborationService.shared.workspace?.token else { return [] }
        guard let url = URL(string: "\(baseURL)/files.php?action=list&vessel_id=\(vesselId)") else { return [] }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let arr = json?["files"] as? [[String: Any]] else { return [] }
        let arrData = try JSONSerialization.data(withJSONObject: arr)
        return (try? JSONDecoder().decode([RemoteFile].self, from: arrData)) ?? []
    }

    // MARK: - Upload Single File (public for background queue)

    func uploadSingleFile(filename: String, data: Data, vesselId: String, token: String) async -> Bool {
        return await uploadFile(filename: filename, data: data, vesselId: vesselId, token: token)
    }

    private func uploadFile(filename: String, data: Data, vesselId: String, token: String) async -> Bool {
        guard let url = URL(string: "\(baseURL)/files.php?action=upload") else { return false }

        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 60  // Large files need more time

        var body = Data()

        // vessel_id
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"vessel_id\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(vesselId)\r\n".data(using: .utf8)!)

        // filename
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"filename\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(filename)\r\n".data(using: .utf8)!)

        // file
        let mime = filename.hasSuffix(".pdf") ? "application/pdf" : filename.hasSuffix(".png") ? "image/png" : "image/jpeg"
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mime)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)

        // End
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        do {
            let (respData, response) = try await URLSession.shared.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 201 { return true }
            let errMsg = (try? JSONSerialization.jsonObject(with: respData) as? [String: Any])?["error"] as? String
            fileSyncLogger.error("Upload failed (\(status)): \(errMsg ?? "unknown")")
            return false
        } catch {
            fileSyncLogger.error("Upload error: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Download Single File

    private func downloadFile(filename: String, token: String) async -> Data? {
        let encoded = filename.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? filename
        guard let url = URL(string: "\(baseURL)/files.php?action=download&filename=\(encoded)") else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 60

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                fileSyncLogger.error("Download failed for \(filename): status \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                return nil
            }
            return data
        } catch {
            fileSyncLogger.error("Download error for \(filename): \(error.localizedDescription)")
            return nil
        }
    }
}
