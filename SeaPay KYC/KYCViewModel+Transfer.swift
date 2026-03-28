//
//  KYCViewModel+Transfer.swift
//  OceanCheck
//
//  .oceancheck package creation, import, preview, rollback.
//

import Foundation

extension KYCViewModel {

    // MARK: - Transfer Package Generation

    func generateTransferPackage(vesselId: String, scenario: VesselShareScenario) -> URL? {
        guard let vessel = vessels.first(where: { $0.id == vesselId }) else { return nil }
        let allChecks = checksForVessel(vesselId)
        let scope = scenario.scope
        let fm = FileManager.default

        let tempDir = fm.temporaryDirectory.appendingPathComponent("OceanCheck_Transfer_\(UUID().uuidString.prefix(8))")
        try? fm.removeItem(at: tempDir)
        try? fm.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = .prettyPrinted

        let manifest: [String: Any] = [
            "formatVersion": "1.0", "scenario": scenario.rawValue,
            "generatedAt": ISO8601DateFormatter().string(from: Date()),
            "generatedBy": AgentProfile.current?.fullName ?? "Agent",
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0",
            "vesselName": vessel.name, "imoNumber": vessel.imoNumber, "checksCount": allChecks.count
        ]
        try? JSONSerialization.data(withJSONObject: manifest, options: .prettyPrinted).write(to: tempDir.appendingPathComponent("manifest.json"))
        try? encoder.encode(vessel).write(to: tempDir.appendingPathComponent("vessel.json"))

        var filteredChecks = allChecks
        if !scope.shoreBased { filteredChecks = filteredChecks.filter { $0.entityType.category != .shoreBased } }
        if !scope.crewRecords { filteredChecks = filteredChecks.filter { $0.entityType.category != .crew } }
        if !scope.ownership { filteredChecks = filteredChecks.filter { $0.entityType.category != .ownership } }
        try? encoder.encode(filteredChecks).write(to: tempDir.appendingPathComponent("checks.json"))

        if scope.images {
            let imgDir = tempDir.appendingPathComponent("images")
            try? fm.createDirectory(at: imgDir, withIntermediateDirectories: true)
            for check in filteredChecks {
                for path in check.documentImagePaths ?? [] {
                    try? fm.copyItem(at: imagesDir.appendingPathComponent(path), to: imgDir.appendingPathComponent(path))
                }
                for doc in check.documents ?? [] {
                    for path in doc.imagePaths {
                        try? fm.copyItem(at: imagesDir.appendingPathComponent(path), to: imgDir.appendingPathComponent(path))
                    }
                }
            }
        }

        let safeName = vessel.name.replacingOccurrences(of: " ", with: "_")
        let zipURL = fm.temporaryDirectory.appendingPathComponent("VesselTransfer_\(safeName).oceancheck")
        try? fm.removeItem(at: zipURL)
        var error: NSError?
        var success = false
        NSFileCoordinator().coordinate(readingItemAt: tempDir, options: .forUploading, error: &error) { tempZipURL in
            try? fm.copyItem(at: tempZipURL, to: zipURL)
            success = true
        }
        try? fm.removeItem(at: tempDir)
        return success && fm.fileExists(atPath: zipURL.path) ? zipURL : nil
    }

    // MARK: - Transfer Import

    func importTransferPackage(from url: URL) -> Bool {
        guard url.startAccessingSecurityScopedResource() else { return false }
        defer { url.stopAccessingSecurityScopedResource() }

        let fm = FileManager.default
        let tempDir = docsDir.appendingPathComponent("_transfer_import")
        try? fm.removeItem(at: tempDir)
        try? fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try? fm.copyItem(at: url, to: tempDir.appendingPathComponent(url.lastPathComponent))

        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601

        guard let vesselFile = findFile("vessel.json", in: tempDir),
              let vesselData = try? Data(contentsOf: vesselFile),
              let importedVessel = try? decoder.decode(Vessel.self, from: vesselData) else {
            try? fm.removeItem(at: tempDir); return false
        }

        if let existingIdx = vessels.firstIndex(where: { $0.imoNumber == importedVessel.imoNumber && !$0.imoNumber.isEmpty }) {
            var v = vessels[existingIdx]
            if let oldOS = v.ownershipStructure {
                var history = v.historicalOwnership ?? []
                history.append(HistoricalOwnership(structure: oldOS, transferDate: Date(), scenario: "import", previousOwner: v.registeredOwner))
                v.historicalOwnership = history
            }
            v.documents = importedVessel.documents
            v.ownershipStructure = importedVessel.ownershipStructure
            vessels[existingIdx] = v
        } else {
            vessels.insert(importedVessel, at: 0)
        }

        if let checksFile = findFile("checks.json", in: tempDir),
           let checksData = try? Data(contentsOf: checksFile),
           let importedChecks = try? decoder.decode([KYCCheck].self, from: checksData) {
            for var check in importedChecks {
                check.vesselId = importedVessel.id
                if !checks.contains(where: { $0.id == check.id }) { checks.append(check) }
            }
        }

        if let imgDir = findDirectory("images", in: tempDir),
           let files = try? fm.contentsOfDirectory(atPath: imgDir.path) {
            for f in files {
                let dest = imagesDir.appendingPathComponent(f)
                if !fm.fileExists(atPath: dest.path) { try? fm.copyItem(at: imgDir.appendingPathComponent(f), to: dest) }
            }
        }

        try? fm.removeItem(at: tempDir)
        saveChecks(); saveVessels()
        return true
    }

    // MARK: - Transfer Preview

    func previewTransferPackage(from url: URL) -> TransferPackagePreview? {
        guard url.startAccessingSecurityScopedResource() else { return nil }
        defer { url.stopAccessingSecurityScopedResource() }
        let fm = FileManager.default
        let tempDir = docsDir.appendingPathComponent("_transfer_preview")
        try? fm.removeItem(at: tempDir)
        try? fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try? fm.copyItem(at: url, to: tempDir.appendingPathComponent(url.lastPathComponent))
        defer { try? fm.removeItem(at: tempDir) }
        guard let manifestFile = findFile("manifest.json", in: tempDir),
              let manifestData = try? Data(contentsOf: manifestFile),
              let manifest = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any] else { return nil }
        let vesselName = manifest["vesselName"] as? String ?? "Unknown"
        let vesselIMO = manifest["imoNumber"] as? String ?? ""
        let hasImages = findDirectory("images", in: tempDir) != nil
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let vf = findFile("vessel.json", in: tempDir)
        let iv = vf.flatMap { try? Data(contentsOf: $0) }.flatMap { try? decoder.decode(Vessel.self, from: $0) }
        return TransferPackagePreview(senderName: manifest["generatedBy"] as? String ?? "Unknown", senderOrg: manifest["organization"] as? String ?? "", senderAgentId: manifest["agentId"] as? String ?? "",
            scenario: manifest["scenario"] as? String ?? "", vesselName: vesselName, vesselIMO: vesselIMO,
            checksCount: manifest["checksCount"] as? Int ?? 0, hasImages: hasImages, hasOwnership: iv?.ownershipStructure != nil,
            generatedAt: manifest["generatedAt"] as? String ?? "", formatVersion: manifest["formatVersion"] as? String ?? "1.0",
            contentHash: manifest["contentHash"] as? String, existsLocally: !vesselIMO.isEmpty && vessels.contains(where: { $0.imoNumber == vesselIMO }),
            vesselType: manifest["vesselType"] as? String ?? iv?.vesselType?.rawValue)
    }

    func importTransferPackageEnhanced(from url: URL) -> TransferImportResult {
        guard url.startAccessingSecurityScopedResource() else {
            return TransferImportResult(success: false, vesselId: nil, vesselName: nil, importedCheckIds: [], wasUpdate: false, error: "Cannot access file")
        }
        defer { url.stopAccessingSecurityScopedResource() }

        let fm = FileManager.default
        let tempDir = docsDir.appendingPathComponent("_transfer_import")
        try? fm.removeItem(at: tempDir)
        try? fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try? fm.copyItem(at: url, to: tempDir.appendingPathComponent(url.lastPathComponent))

        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601

        guard let vesselFile = findFile("vessel.json", in: tempDir),
              let vesselData = try? Data(contentsOf: vesselFile),
              let importedVessel = try? decoder.decode(Vessel.self, from: vesselData) else {
            try? fm.removeItem(at: tempDir)
            return TransferImportResult(success: false, vesselId: nil, vesselName: nil, importedCheckIds: [], wasUpdate: false, error: "Invalid package — no vessel data")
        }

        let wasUpdate = vessels.contains(where: { $0.imoNumber == importedVessel.imoNumber && !$0.imoNumber.isEmpty })

        if let existingIdx = vessels.firstIndex(where: { $0.imoNumber == importedVessel.imoNumber && !$0.imoNumber.isEmpty }) {
            var v = vessels[existingIdx]
            if let oldOS = v.ownershipStructure {
                var history = v.historicalOwnership ?? []
                history.append(HistoricalOwnership(structure: oldOS, transferDate: Date(), scenario: "import", previousOwner: v.registeredOwner))
                v.historicalOwnership = history
            }
            v.documents = importedVessel.documents
            v.ownershipStructure = importedVessel.ownershipStructure
            vessels[existingIdx] = v
        } else {
            vessels.insert(importedVessel, at: 0)
        }

        var importedCheckIds: [String] = []
        if let checksFile = findFile("checks.json", in: tempDir),
           let checksData = try? Data(contentsOf: checksFile),
           let importedChecks = try? decoder.decode([KYCCheck].self, from: checksData) {
            for var check in importedChecks {
                check.vesselId = importedVessel.id
                if !checks.contains(where: { $0.id == check.id }) {
                    checks.append(check)
                    importedCheckIds.append(check.id)
                }
            }
        }

        if let imgDir = findDirectory("images", in: tempDir),
           let files = try? fm.contentsOfDirectory(atPath: imgDir.path) {
            for f in files {
                let dest = imagesDir.appendingPathComponent(f)
                if !fm.fileExists(atPath: dest.path) { try? fm.copyItem(at: imgDir.appendingPathComponent(f), to: dest) }
            }
        }

        try? fm.removeItem(at: tempDir)
        saveChecks(); saveVessels()

        // Record in transfer log
        let record = TransferRecord(
            direction: .received, scenario: "import", vesselName: importedVessel.name,
            vesselIMO: importedVessel.imoNumber, checksCount: importedCheckIds.count,
            senderAgentName: "External", senderAgentId: "", senderOrganization: "",
            receiverAgentName: AgentProfile.current?.fullName, receiverAgentId: AgentProfile.current?.agentId,
            importedVesselId: importedVessel.id, importedCheckIds: importedCheckIds, wasVesselUpdate: wasUpdate
        )
        transferLog.insert(record, at: 0)
        saveTransferLog()

        return TransferImportResult(
            success: true, vesselId: importedVessel.id, vesselName: importedVessel.name,
            importedCheckIds: importedCheckIds, wasUpdate: wasUpdate, error: nil
        )
    }

    func rollbackImport(transferId: String) -> Bool {
        guard let record = transferLog.first(where: { $0.id == transferId }),
              record.direction == .received else { return false }

        // Remove imported checks
        if let checkIds = record.importedCheckIds {
            for cid in checkIds {
                if let i = checks.firstIndex(where: { $0.id == cid }) {
                    if let paths = checks[i].documentImagePaths {
                        for p in paths { try? FileManager.default.removeItem(at: imagesDir.appendingPathComponent(p)) }
                    }
                    checks.remove(at: i)
                }
            }
        }

        // Remove vessel if it was newly created (not an update)
        if !record.wasVesselUpdate, let vid = record.importedVesselId {
            vessels.removeAll { $0.id == vid }
        }

        saveChecks(); saveVessels()
        return true
    }

    func reExportTransfer(transferId: String) -> URL? {
        guard let record = transferLog.first(where: { $0.id == transferId }),
              let vid = record.importedVesselId,
              vessels.contains(where: { $0.id == vid }) else { return nil }
        return generateTransferPackage(vesselId: vid, scenario: .vesselSale)
    }
}
