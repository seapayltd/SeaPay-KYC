//
//  FilesSyncService.swift
//  OceanCheck
//
//  Syncs document images between devices via the backend file storage.
//  Uploads missing local files, downloads missing remote files.
//

import Foundation
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
class FilesSyncService {
    static let shared = FilesSyncService()

    private let baseURL = "https://seapay.me/oceancheck/api"

    // MARK: - List Remote Files

    func listRemoteFiles(vesselId: String) async throws -> [RemoteFile] {
        guard let token = CollaborationService.shared.workspace?.token else { return [] }
        guard let url = URL(string: "\(baseURL)/files.php?action=list&vessel_id=\(vesselId)") else { return [] }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15

        let (data, _) = try await URLSession.shared.data(for: req)
        let response = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let arr = response?["files"] as? [[String: Any]] else { return [] }
        let arrData = try JSONSerialization.data(withJSONObject: arr)
        return (try? JSONDecoder().decode([RemoteFile].self, from: arrData)) ?? []
    }

    // MARK: - Upload Missing Files

    func uploadMissingFiles(vesselId: String, vm: KYCViewModel) async {
        guard let token = CollaborationService.shared.workspace?.token else { return }

        // Collect all local image filenames for this vessel
        var localFiles: Set<String> = []
        let checks = vm.checksForVessel(vesselId)
        for check in checks {
            for path in check.documentImagePaths ?? [] { localFiles.insert(path) }
            if let photo = check.profilePhoto { localFiles.insert(photo) }
            for doc in check.documents ?? [] {
                for path in doc.imagePaths { localFiles.insert(path) }
            }
        }
        if let vessel = vm.vessels.first(where: { $0.id == vesselId }), let photo = vessel.photoFilename {
            localFiles.insert(photo)
        }

        guard !localFiles.isEmpty else { return }

        // Get list of already-uploaded files
        let remoteFilenames: Set<String>
        do {
            remoteFilenames = Set(try await listRemoteFiles(vesselId: vesselId).map(\.filename))
        } catch { return }

        // Upload missing
        let missing = localFiles.subtracting(remoteFilenames)
        for filename in missing {
            guard let fileData = vm.loadDocumentImage(filename: filename) else { continue }
            await uploadFile(filename: filename, data: fileData, vesselId: vesselId, token: token)
        }

        #if DEBUG
        if !missing.isEmpty { fileSyncLogger.debug("Uploaded \(missing.count) files for vessel \(vesselId.prefix(8))") }
        #endif
    }

    // MARK: - Download Missing Files

    func downloadMissingFiles(vesselId: String, vm: KYCViewModel) async {
        guard let token = CollaborationService.shared.workspace?.token else { return }

        // Get remote file list
        let remoteFiles: [RemoteFile]
        do { remoteFiles = try await listRemoteFiles(vesselId: vesselId) } catch { return }

        guard !remoteFiles.isEmpty else { return }

        // Check which files we're missing locally
        let fm = FileManager.default
        var downloaded = 0

        for remote in remoteFiles {
            let localPath = vm.imagesDir.appendingPathComponent(remote.filename)
            if fm.fileExists(atPath: localPath.path) { continue }

            // Download
            if let data = await downloadFile(filename: remote.filename, token: token) {
                try? data.write(to: localPath)
                downloaded += 1
            }
        }

        #if DEBUG
        if downloaded > 0 { fileSyncLogger.debug("Downloaded \(downloaded) files for vessel \(vesselId.prefix(8))") }
        #endif
    }

    // MARK: - Upload Single File

    private func uploadFile(filename: String, data: Data, vesselId: String, token: String) async {
        guard let url = URL(string: "\(baseURL)/files.php?action=upload") else { return }

        let boundary = UUID().uuidString
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30

        var body = Data()
        // vessel_id field
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"vessel_id\"\r\n\r\n\(vesselId)\r\n".data(using: .utf8)!)
        // filename field
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"filename\"\r\n\r\n\(filename)\r\n".data(using: .utf8)!)
        // file field
        let mime = filename.hasSuffix(".pdf") ? "application/pdf" : filename.hasSuffix(".png") ? "image/png" : "image/jpeg"
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\nContent-Type: \(mime)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        _ = try? await URLSession.shared.data(for: req)
    }

    // MARK: - Download Single File

    private func downloadFile(filename: String, token: String) async -> Data? {
        let encoded = filename.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? filename
        guard let url = URL(string: "\(baseURL)/files.php?action=download&filename=\(encoded)") else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 30

        guard let (data, response) = try? await URLSession.shared.data(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }
}
