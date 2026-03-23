//
//  KYCViewModel.swift
//  SeaPay KYC
//
//  Pipeline: Scan ID → AML → optional PoA → PDF
//

import Foundation
import Combine
import SwiftUI
import CoreLocation
import Network

@MainActor
class KYCViewModel: ObservableObject {
    @Published var checks: [KYCCheck] = []
    @Published var vessels: [Vessel] = []
    @Published var isOnline = true

    private let api = VerificationAPIService.shared
    private let netMonitor = NWPathMonitor()

    // MARK: - Storage

    var docsDir: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first! }
    private var checksFile: URL { docsDir.appendingPathComponent("kyc_checks.json") }
    private var vesselsFile: URL { docsDir.appendingPathComponent("vessels.json") }
    var imagesDir: URL {
        let d = docsDir.appendingPathComponent("captured_documents")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true); return d
    }
    var reportsDir: URL {
        let d = docsDir.appendingPathComponent("reports")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true); return d
    }

    private var pollTimers: [String: Timer] = [:]

    init() {
        load(); loadVessels(); startPollingPendingSessions()
        netMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in self?.isOnline = path.status == .satisfied }
        }
        netMonitor.start(queue: DispatchQueue(label: "net.monitor"))
    }

    private func load() {
        guard let data = try? Data(contentsOf: checksFile) else { return }
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        checks = (try? d.decode([KYCCheck].self, from: data)) ?? []
    }

    private func save() {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = .prettyPrinted
        try? e.encode(checks).write(to: checksFile)
        objectWillChange.send()
        NotificationService.shared.rescheduleAll(checks: checks, vessels: vessels)
        CloudBackupService.shared.backup(checksFile: checksFile, vesselsFile: vesselsFile, imagesDir: imagesDir)
    }

    // MARK: - Vessels

    private func loadVessels() {
        guard let data = try? Data(contentsOf: vesselsFile) else { return }
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        vessels = (try? d.decode([Vessel].self, from: data)) ?? []
    }

    private func saveVessels() {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = .prettyPrinted
        try? e.encode(vessels).write(to: vesselsFile)
        objectWillChange.send()
    }

    @discardableResult
    func createVessel(name: String, imoNumber: String = "", flagState: String = "", portOfRegistry: String = "", vesselType: VesselType? = nil) -> Vessel {
        let v = Vessel(name: name, imoNumber: imoNumber, flagState: flagState, portOfRegistry: portOfRegistry, vesselType: vesselType)
        vessels.insert(v, at: 0); saveVessels(); return v
    }

    func updateVessel(_ vessel: Vessel) {
        guard let i = vessels.firstIndex(where: { $0.id == vessel.id }) else { return }
        vessels[i] = vessel; saveVessels()
    }

    func deleteVessel(id: String) {
        // Unlink checks from this vessel
        for i in checks.indices where checks[i].vesselId == id { checks[i].vesselId = nil }
        save()
        vessels.removeAll { $0.id == id }; saveVessels()
    }

    func checksForVessel(_ vesselId: String) -> [KYCCheck] {
        checks.filter { $0.vesselId == vesselId }
    }

    func seafarersForVessel(_ vesselId: String) -> [KYCCheck] {
        checks.filter { $0.vesselId == vesselId && $0.entityType.category == .crew }
    }

    func complianceChecksForVessel(_ vesselId: String) -> [KYCCheck] {
        checks.filter { $0.vesselId == vesselId && $0.entityType.category == .ownership }
    }

    func shoreBasedForVessel(_ vesselId: String) -> [KYCCheck] {
        checks.filter { $0.vesselId == vesselId && $0.entityType.category == .shoreBased }
    }

    var unassignedChecks: [KYCCheck] { checks.filter { $0.vesselId == nil } }

    func assignCheckToVessel(checkId: String, vesselId: String) {
        guard let i = idx(checkId) else { return }
        checks[i].vesselId = vesselId; save()
    }

    func unassignCheckFromVessel(checkId: String) {
        guard let i = idx(checkId) else { return }
        checks[i].vesselId = nil; save()
    }

    func updateCheckName(checkId: String, name: String) {
        guard let i = idx(checkId) else { return }
        checks[i].customerName = name
        if checks[i].extractedName != nil { checks[i].extractedName = name }
        save()
    }

    func updateEntityType(checkId: String, entityType: KYCCheck.EntityType) {
        guard let i = idx(checkId) else { return }
        checks[i].entityType = entityType; save()
    }

    func deleteCheckById(_ checkId: String) {
        guard let i = idx(checkId) else { return }
        if let paths = checks[i].documentImagePaths {
            for p in paths { try? FileManager.default.removeItem(at: imagesDir.appendingPathComponent(p)) }
        }
        checks.remove(at: i); save()
    }

    // MARK: - Expiry Intelligence

    private static let expiryDateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    var expiringChecks: [KYCCheck] {
        let cutoff = Calendar.current.date(byAdding: .day, value: 30, to: Date())!
        return checks.filter { check in
            guard let s = check.expiryDate, let d = Self.expiryDateFmt.date(from: s) else { return false }
            return d >= Date() && d <= cutoff
        }
    }

    var expiredChecks: [KYCCheck] {
        checks.filter { check in
            guard let s = check.expiryDate, let d = Self.expiryDateFmt.date(from: s) else { return false }
            return d < Date()
        }
    }

    // MARK: - Document Portfolio

    func requiredDocuments(for check: KYCCheck) -> [MaritimeDocType] {
        if check.entityType != .seafarer {
            return FlagStateRequirements.requiredForEntity(check.entityType)
        }
        let vessel = check.vesselId.flatMap { vid in vessels.first { $0.id == vid } }
        return FlagStateRequirements.required(
            flag: vessel?.flagState ?? "",
            vesselType: vessel?.vesselType,
            rank: check.crewRank
        )
    }

    struct PortfolioItem: Identifiable {
        var id: String { type.rawValue }
        let type: MaritimeDocType
        var document: CrewDocument?
        let required: Bool
    }

    func documentPortfolio(for check: KYCCheck) -> [PortfolioItem] {
        let required = Set(requiredDocuments(for: check))
        let active = (check.documents ?? []).filter { !$0.isArchived }
        let byType = Dictionary(grouping: active, by: \.type).compactMapValues(\.first)

        var items: [PortfolioItem] = []
        for dt in required.sorted(by: { $0.displayName < $1.displayName }) {
            items.append(PortfolioItem(type: dt, document: byType[dt], required: true))
        }
        for doc in active where !required.contains(doc.type) {
            items.append(PortfolioItem(type: doc.type, document: doc, required: false))
        }
        return items
    }

    func setCrewRank(_ rank: CrewRank, for checkId: String) {
        guard let i = idx(checkId) else { return }
        checks[i].crewRank = rank
        // Auto-populate required document placeholders
        let required = requiredDocuments(for: checks[i])
        let existing = Set((checks[i].documents ?? []).map(\.type))
        var docs = checks[i].documents ?? []
        for dt in required where !existing.contains(dt) {
            docs.append(CrewDocument(type: dt))
        }
        checks[i].documents = docs
        save()
    }

    func addDocument(to checkId: String, document: CrewDocument) {
        guard let i = idx(checkId) else { return }
        var docs = checks[i].documents ?? []
        // Replace placeholder if same type exists with no images
        if let existing = docs.firstIndex(where: { $0.type == document.type && $0.imagePaths.isEmpty }) {
            docs[existing] = document
        } else {
            docs.append(document)
        }
        checks[i].documents = docs; save()
    }

    func updateDocument(checkId: String, document: CrewDocument) {
        guard let i = idx(checkId) else { return }
        guard var docs = checks[i].documents, let di = docs.firstIndex(where: { $0.id == document.id }) else { return }
        docs[di] = document; checks[i].documents = docs; save()
    }

    func removeDocument(checkId: String, documentId: String) {
        guard let i = idx(checkId) else { return }
        checks[i].documents?.removeAll { $0.id == documentId }; save()
    }

    /// All documents across all checks that are expiring within 90 days
    var allExpiringDocuments: [(check: KYCCheck, document: CrewDocument)] {
        let cutoff = Calendar.current.date(byAdding: .day, value: 90, to: Date())!
        return checks.flatMap { check in
            (check.documents ?? []).compactMap { doc in
                guard let exp = doc.expiryDate, exp >= Date(), exp <= cutoff else { return nil }
                return (check, doc)
            }
        }
    }

    var allExpiredDocuments: [(check: KYCCheck, document: CrewDocument)] {
        checks.flatMap { check in
            (check.documents ?? []).compactMap { doc in
                guard let exp = doc.expiryDate, exp < Date() else { return nil }
                return (check, doc)
            }
        }
    }

    // MARK: - Document Renewal

    func renewDocument(checkId: String, oldDocId: String, newDoc: CrewDocument) {
        guard let i = idx(checkId) else { return }
        guard var docs = checks[i].documents, let di = docs.firstIndex(where: { $0.id == oldDocId }) else { return }
        docs[di].renewedAt = Date()
        var renewed = newDoc
        renewed.previousVersionId = oldDocId
        docs.append(renewed)
        checks[i].documents = docs; save()
    }

    // MARK: - Vessel Documents

    func addVesselDocument(to vesselId: String, document: CrewDocument) {
        guard let i = vessels.firstIndex(where: { $0.id == vesselId }) else { return }
        var docs = vessels[i].documents ?? []
        docs.append(document); vessels[i].documents = docs; saveVessels()
    }

    func removeVesselDocument(vesselId: String, documentId: String) {
        guard let i = vessels.firstIndex(where: { $0.id == vesselId }) else { return }
        vessels[i].documents?.removeAll { $0.id == documentId }; saveVessels()
    }

    // MARK: - Profile Photo

    func setProfilePhoto(checkId: String, imageData: Data) {
        guard let i = idx(checkId) else { return }
        let filename = "\(checkId)_profile.jpg"
        try? imageData.write(to: imagesDir.appendingPathComponent(filename))
        checks[i].profilePhoto = filename; save()
    }

    // MARK: - CSV Export

    func generateCSV(vesselId: String?) -> URL? {
        let target = vesselId.map { checksForVessel($0) } ?? checks
        let csv = CSVExporter.generateCrewCSV(checks: target, vessels: vessels)
        let name = "OceanCheck_CrewData_\(Date().formatted(.iso8601.year().month().day())).csv"
        let url = reportsDir.appendingPathComponent(name)
        try? csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func generateCrewList(vesselId: String) -> URL? {
        guard let vessel = vessels.first(where: { $0.id == vesselId }) else { return nil }
        let crew = checksForVessel(vesselId)
        let data = ReportGenerator.generateCrewListPDF(vessel: vessel, checks: crew)
        let safeName = vessel.name.replacingOccurrences(of: " ", with: "_")
        let name = "CrewList_FAL5_\(safeName)_\(Date().formatted(.iso8601.year().month().day())).pdf"
        let url = reportsDir.appendingPathComponent(name)
        try? data.write(to: url)
        return url
    }

    func generateUBOReport(vesselId: String) -> Data? {
        guard let i = vessels.firstIndex(where: { $0.id == vesselId }),
              let structure = vessels[i].ownershipStructure else { return nil }
        let checkIds = structure.shareholders.compactMap(\.checkId) + structure.directors.compactMap(\.checkId)
            + structure.shareholders.flatMap { $0.subShareholders?.compactMap(\.checkId) ?? [] }
        let linkedChecks = checks.filter { checkIds.contains($0.id) }
        let data = ReportGenerator.generateUBOReport(vessel: vessels[i], structure: structure, checks: linkedChecks)
        vessels[i].ownershipStructure?.uboReportGenerated = true
        saveVessels()
        return data
    }

    // MARK: - Scenario-Based Sharing

    func generateShareExport(vesselId: String, scenario: VesselShareScenario) -> URL? {
        guard let vessel = vessels.first(where: { $0.id == vesselId }) else { return nil }
        let allChecks = checksForVessel(vesselId)
        let scope = scenario.scope

        let data: Data
        switch scenario {
        case .portRequest:
            data = ReportGenerator.generateAuthorityPacket(vessel: vessel, checks: allChecks, title: "PORT AUTHORITY DOCUMENTATION")
        case .classSociety:
            data = ReportGenerator.generateCertificateSummary(vessel: vessel)
        case .flagStateRequest:
            data = ReportGenerator.generateAuthorityPacket(vessel: vessel, checks: allChecks, title: "FLAG STATE COMPLIANCE REPORT", includeAML: scope.aml)
        case .insuranceRequest:
            data = ReportGenerator.generateAuthorityPacket(vessel: vessel, checks: allChecks, title: "P&I COMPLIANCE EVIDENCE", includeAML: true, includeUBO: true)
        case .charterDueDiligence:
            data = ReportGenerator.generateSanitizedCrewSummary(vessel: vessel, checks: allChecks)
        default:
            return nil
        }

        let safeName = vessel.name.replacingOccurrences(of: " ", with: "_")
        let scenarioTag = scenario.rawValue.replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "/", with: "")
        let name = "\(safeName)_\(scenarioTag)_\(Date().formatted(.iso8601.year().month().day())).pdf"
        let url = reportsDir.appendingPathComponent(name)
        try? data.write(to: url)
        return url
    }

    func generateTransferPackage(vesselId: String, scenario: VesselShareScenario) -> URL? {
        guard let vessel = vessels.first(where: { $0.id == vesselId }) else { return nil }
        let allChecks = checksForVessel(vesselId)
        let scope = scenario.scope
        let fm = FileManager.default

        // Create temp directory
        let tempDir = fm.temporaryDirectory.appendingPathComponent("OceanCheck_Transfer_\(UUID().uuidString.prefix(8))")
        try? fm.removeItem(at: tempDir)
        try? fm.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = .prettyPrinted

        // Manifest
        let manifest: [String: Any] = [
            "formatVersion": "1.0",
            "scenario": scenario.rawValue,
            "generatedAt": ISO8601DateFormatter().string(from: Date()),
            "generatedBy": UserDefaults.standard.string(forKey: "agentName") ?? "Agent",
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0",
            "vesselName": vessel.name,
            "imoNumber": vessel.imoNumber,
            "checksCount": allChecks.count
        ]
        try? JSONSerialization.data(withJSONObject: manifest, options: .prettyPrinted).write(to: tempDir.appendingPathComponent("manifest.json"))

        // Vessel
        try? encoder.encode(vessel).write(to: tempDir.appendingPathComponent("vessel.json"))

        // Checks (filtered by scope)
        var filteredChecks = allChecks
        if !scope.shoreBased { filteredChecks = filteredChecks.filter { $0.entityType.category != .shoreBased } }
        if !scope.crewRecords { filteredChecks = filteredChecks.filter { $0.entityType.category != .crew } }
        if !scope.ownership { filteredChecks = filteredChecks.filter { $0.entityType.category != .ownership } }
        try? encoder.encode(filteredChecks).write(to: tempDir.appendingPathComponent("checks.json"))

        // Images
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

        // ZIP
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

    func importTransferPackage(from url: URL) -> Bool {
        guard url.startAccessingSecurityScopedResource() else { return false }
        defer { url.stopAccessingSecurityScopedResource() }

        let fm = FileManager.default
        let tempDir = docsDir.appendingPathComponent("_transfer_import")
        try? fm.removeItem(at: tempDir)
        try? fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try? fm.copyItem(at: url, to: tempDir.appendingPathComponent(url.lastPathComponent))

        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601

        // Find vessel.json
        guard let vesselFile = findFile("vessel.json", in: tempDir),
              let vesselData = try? Data(contentsOf: vesselFile),
              let importedVessel = try? decoder.decode(Vessel.self, from: vesselData) else {
            try? fm.removeItem(at: tempDir); return false
        }

        // Check if vessel already exists by IMO
        if let existingIdx = vessels.firstIndex(where: { $0.imoNumber == importedVessel.imoNumber && !$0.imoNumber.isEmpty }) {
            // Update existing vessel
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

        // Import checks
        if let checksFile = findFile("checks.json", in: tempDir),
           let checksData = try? Data(contentsOf: checksFile),
           let importedChecks = try? decoder.decode([KYCCheck].self, from: checksData) {
            for var check in importedChecks {
                check.vesselId = importedVessel.id
                if !checks.contains(where: { $0.id == check.id }) { checks.append(check) }
            }
        }

        // Import images
        if let imgDir = findDirectory("images", in: tempDir),
           let files = try? fm.contentsOfDirectory(atPath: imgDir.path) {
            for f in files {
                let dest = imagesDir.appendingPathComponent(f)
                if !fm.fileExists(atPath: dest.path) { try? fm.copyItem(at: imgDir.appendingPathComponent(f), to: dest) }
            }
        }

        try? fm.removeItem(at: tempDir)
        save(); saveVessels()
        return true
    }

    // MARK: - Backup Export / Import

    func exportBackup() -> URL? {
        let fm = FileManager.default
        let backupDir = fm.temporaryDirectory.appendingPathComponent("OceanCheck_Backup_\(UUID().uuidString.prefix(8))")
        try? fm.removeItem(at: backupDir)
        try? fm.createDirectory(at: backupDir, withIntermediateDirectories: true)

        try? fm.copyItem(at: checksFile, to: backupDir.appendingPathComponent("kyc_checks.json"))
        try? fm.copyItem(at: vesselsFile, to: backupDir.appendingPathComponent("vessels.json"))

        // Copy images
        let imgsBackup = backupDir.appendingPathComponent("images")
        try? fm.createDirectory(at: imgsBackup, withIntermediateDirectories: true)
        if let files = try? fm.contentsOfDirectory(atPath: imagesDir.path) {
            for f in files { try? fm.copyItem(at: imagesDir.appendingPathComponent(f), to: imgsBackup.appendingPathComponent(f)) }
        }

        // Create zip using NSFileCoordinator
        let zipName = "OceanCheck_Backup.zip"
        let zipURL = fm.temporaryDirectory.appendingPathComponent(zipName)
        try? fm.removeItem(at: zipURL)

        var error: NSError?
        var success = false
        NSFileCoordinator().coordinate(readingItemAt: backupDir, options: .forUploading, error: &error) { tempURL in
            try? fm.copyItem(at: tempURL, to: zipURL)
            success = true
        }
        try? fm.removeItem(at: backupDir)

        print("[Backup] ZIP created: \(success), file exists: \(fm.fileExists(atPath: zipURL.path))")
        if success && fm.fileExists(atPath: zipURL.path) {
            return zipURL
        }

        // Fallback: share the JSON file directly
        return fm.fileExists(atPath: checksFile.path) ? checksFile : nil
    }

    func importBackup(from url: URL) -> Bool {
        guard url.startAccessingSecurityScopedResource() else { return false }
        defer { url.stopAccessingSecurityScopedResource() }

        let fm = FileManager.default
        let tempDir = docsDir.appendingPathComponent("_import_temp")
        try? fm.removeItem(at: tempDir)

        try? fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        // Copy the imported file to temp
        let dest = tempDir.appendingPathComponent(url.lastPathComponent)
        try? fm.copyItem(at: url, to: dest)

        // Find and restore JSON files
        let checksSource = findFile("kyc_checks.json", in: tempDir)
        let vesselsSource = findFile("vessels.json", in: tempDir)

        if let src = checksSource {
            try? fm.removeItem(at: checksFile)
            try? fm.copyItem(at: src, to: checksFile)
        }
        if let src = vesselsSource {
            try? fm.removeItem(at: vesselsFile)
            try? fm.copyItem(at: src, to: vesselsFile)
        }

        // Restore images
        let imgsSource = findDirectory("images", in: tempDir)
        if let src = imgsSource, let files = try? fm.contentsOfDirectory(atPath: src.path) {
            try? fm.createDirectory(at: imagesDir, withIntermediateDirectories: true)
            for f in files {
                let dest = imagesDir.appendingPathComponent(f)
                try? fm.removeItem(at: dest)
                try? fm.copyItem(at: src.appendingPathComponent(f), to: dest)
            }
        }

        try? fm.removeItem(at: tempDir)
        load(); loadVessels()
        return checksSource != nil
    }

    private func findFile(_ name: String, in dir: URL) -> URL? {
        let fm = FileManager.default
        let direct = dir.appendingPathComponent(name)
        if fm.fileExists(atPath: direct.path) { return direct }
        if let contents = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for item in contents {
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue {
                    if let found = findFile(name, in: item) { return found }
                }
                if item.lastPathComponent == name { return item }
            }
        }
        return nil
    }

    private func findDirectory(_ name: String, in dir: URL) -> URL? {
        let fm = FileManager.default
        let direct = dir.appendingPathComponent(name)
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: direct.path, isDirectory: &isDir), isDir.boolValue { return direct }
        if let contents = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for item in contents {
                if fm.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue {
                    if item.lastPathComponent == name { return item }
                    if let found = findDirectory(name, in: item) { return found }
                }
            }
        }
        return nil
    }

    // MARK: - Batch Invite

    struct BatchProgress {
        var total: Int; var completed: Int
        var results: [(name: String, url: String?, error: String?)]
    }

    func createBatchInvites(names: [String], vesselId: String?) -> AsyncStream<BatchProgress> {
        AsyncStream { continuation in
            Task {
                var progress = BatchProgress(total: names.count, completed: 0, results: [])
                for name in names {
                    let check = createCheck(customerName: name)
                    if let vid = vesselId { assignCheckToVessel(checkId: check.id, vesselId: vid) }
                    do {
                        let r = try await createInviteSession(checkId: check.id)
                        progress.results.append((name, r.verifyURL, nil))
                    } catch {
                        progress.results.append((name, nil, error.localizedDescription))
                    }
                    progress.completed += 1
                    continuation.yield(progress)
                }
                continuation.finish()
            }
        }
    }

    // MARK: - Compliance Packet

    func generateCompliancePacket(vesselId: String?) -> URL? {
        let target = vesselId.map { checksForVessel($0) } ?? checks
        let vessel = vesselId.flatMap { vid in vessels.first { $0.id == vid } }
        guard !target.isEmpty else { return nil }

        // Generate individual PDFs, combine into one
        var allData: [Data] = []
        // Cover page
        allData.append(ReportGenerator.generateCoverSheet(
            vesselName: vessel?.name ?? "All Crew",
            imoNumber: vessel?.imoNumber ?? "",
            flagState: vessel?.flagState ?? "",
            checks: target
        ))
        // Individual reports — seafarers first, then compliance entities
        let sorted = target.sorted { ($0.entityType == .seafarer ? 0 : 1) < ($1.entityType == .seafarer ? 0 : 1) }
        for check in sorted {
            var docImages: [UIImage] = []
            if let paths = check.documentImagePaths {
                for p in paths { if let d = loadDocumentImage(filename: p), let img = UIImage(data: d) { docImages.append(img) } }
            }
            allData.append(ReportGenerator.generatePDF(for: check, documentImages: docImages))
        }

        // Merge PDFs
        let merged = mergePDFs(allData)
        let name = "OceanCheck_Compliance_\(vessel?.name.replacingOccurrences(of: " ", with: "_") ?? "All")_\(Date().formatted(.iso8601.year().month().day())).pdf"
        let url = reportsDir.appendingPathComponent(name)
        try? merged.write(to: url)
        return url
    }

    private func mergePDFs(_ pdfs: [Data]) -> Data {
        let merged = NSMutableData()
        UIGraphicsBeginPDFContextToData(merged, .zero, nil)
        for pdf in pdfs {
            guard let provider = CGDataProvider(data: pdf as CFData),
                  let doc = CGPDFDocument(provider) else { continue }
            for i in 1...doc.numberOfPages {
                guard let page = doc.page(at: i) else { continue }
                let box = page.getBoxRect(.mediaBox)
                UIGraphicsBeginPDFPageWithInfo(box, nil)
                guard let ctx = UIGraphicsGetCurrentContext() else { continue }
                ctx.translateBy(x: 0, y: box.height)
                ctx.scaleBy(x: 1, y: -1)
                ctx.drawPDFPage(page)
            }
        }
        UIGraphicsEndPDFContext()
        return merged as Data
    }

    // MARK: - Create

    func createCheck(customerName: String, entityType: KYCCheck.EntityType = .seafarer, vesselId: String? = nil, crewRank: CrewRank? = nil, companyName: String? = nil, registrationNumber: String? = nil, jurisdiction: String? = nil, ownershipPercent: Double? = nil, docType: KYCCheck.IDDocType? = nil) -> KYCCheck {
        let lm = CLLocationManager()
        lm.requestWhenInUseAuthorization()
        let loc = lm.location

        var check = KYCCheck(
            id: UUID().uuidString,
            customerId: "",
            customerName: customerName,
            agentId: "",
            agentName: UserDefaults.standard.string(forKey: "agentName") ?? "Agent",
            checkType: .idVerification,
            status: .pending,
            entityType: entityType,
            createdAt: Date(),
            latitude: loc?.coordinate.latitude,
            longitude: loc?.coordinate.longitude,
            expectedDocType: docType
        )
        check.vesselId = vesselId
        check.crewRank = crewRank
        check.companyName = companyName
        check.registrationNumber = registrationNumber
        check.jurisdiction = jurisdiction
        check.ownershipPercent = ownershipPercent

        // Auto-populate required documents based on entity type
        if entityType == .seafarer {
            if crewRank != nil || vesselId != nil {
                let vessel = vesselId.flatMap({ vid in vessels.first { $0.id == vid } })
                let required = FlagStateRequirements.required(flag: vessel?.flagState ?? "", vesselType: vessel?.vesselType, rank: crewRank)
                check.documents = required.map { CrewDocument(type: $0) }
            }
        } else {
            let required = FlagStateRequirements.requiredForEntity(entityType)
            check.documents = required.map { CrewDocument(type: $0) }
        }

        checks.insert(check, at: 0); save()
        return check
    }

    // MARK: - Invite Flow (session-based)

    struct InviteResult {
        let sessionId: String
        let verifyURL: String
    }

    func createInviteSession(checkId: String) async throws -> InviteResult {
        guard let i = idx(checkId) else { throw AppError.verificationFailed("Check not found") }
        let wf = AppConfiguration.workflowID
        guard !wf.isEmpty else { throw AppError.missingRequiredField("Workflow ID — configure it in Settings") }

        let session = try await api.createSession(workflowID: wf, vendorData: checks[i].customerName)

        checks[i].status = .inProgress
        checks[i].sessionId = session.sessionId
        checks[i].hostedVerifyURL = session.url
        save()

        startPolling(checkId: checkId, sessionId: session.sessionId)

        return InviteResult(
            sessionId: session.sessionId,
            verifyURL: session.url ?? ""
        )
    }

    /// Whether a session decision status means "finished" (no more polling needed)
    private func isTerminalStatus(_ status: String) -> Bool {
        let s = status.lowercased()
        return ["approved", "declined", "completed", "rejected", "failed", "expired"].contains(s)
    }

    func pollSessionDecision(checkId: String, sessionId: String) async throws -> SessionDecision {
        let (decision, rawData) = try await api.getSessionDecision(sessionId: sessionId)
        let rawString = String(data: rawData, encoding: .utf8)

        print("[OceanCheck] Poll \(checkId.prefix(8)): status=\(decision.status), idResults=\(decision.idVerifications?.count ?? 0), aml=\(decision.aml?.count ?? 0), rawBytes=\(rawData.count)")

        if let i = idx(checkId) {
            let s = decision.status.lowercased()
            if s == "approved" || s == "completed" {
                checks[i].status = .passed
            } else if s == "declined" || s == "rejected" || s == "failed" {
                checks[i].status = .failed
            }

            // Extract data from decision
            if let idResult = decision.idVerifications?.first {
                checks[i].extractedName = idResult.extractedFullName
                if !idResult.extractedFullName.isEmpty {
                    checks[i].customerName = idResult.extractedFullName
                }
                checks[i].documentType = idResult.documentType
                checks[i].documentNumber = idResult.documentNumber
                checks[i].dateOfBirth = idResult.dateOfBirth
                checks[i].nationality = idResult.nationality
                if let dn = idResult.documentNumber { checks[i].customerId = dn }
            }
            if let amlResult = decision.aml?.first {
                checks[i].amlStatus = amlResult.status
                checks[i].amlScore = amlResult.score
                checks[i].amlHitCount = amlResult.totalHits
            }

            if isTerminalStatus(decision.status) {
                checks[i].completedAt = Date()
                // Store the raw API response directly
                if checks[i].rawIDResponse == nil {
                    checks[i].rawIDResponse = rawString
                    print("[OceanCheck] Stored rawIDResponse for \(checkId.prefix(8)): \(rawString?.prefix(200) ?? "nil")")
                }
            }
            save()
        }

        return decision
    }

    // MARK: - Background Polling

    private func startPollingPendingSessions() {
        for check in checks where check.sessionId != nil && check.status == .inProgress {
            startPolling(checkId: check.id, sessionId: check.sessionId!)
        }
    }

    func startPolling(checkId: String, sessionId: String) {
        guard pollTimers[checkId] == nil else { return }
        print("[OceanCheck] Starting poll for \(checkId.prefix(8))")
        pollTimers[checkId] = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.pollOnce(checkId: checkId, sessionId: sessionId)
            }
        }
    }

    func stopPolling(checkId: String) {
        print("[OceanCheck] Stopping poll for \(checkId.prefix(8))")
        pollTimers[checkId]?.invalidate()
        pollTimers.removeValue(forKey: checkId)
    }

    private func pollOnce(checkId: String, sessionId: String) async {
        do {
            let decision = try await pollSessionDecision(checkId: checkId, sessionId: sessionId)
            if isTerminalStatus(decision.status) {
                stopPolling(checkId: checkId)
                let pdfURL = generateReport(checkId: checkId)
                print("[OceanCheck] Poll complete. PDF generated: \(pdfURL?.absoluteString ?? "FAILED")")
            }
        } catch {
            print("[OceanCheck] Poll error for \(checkId.prefix(8)): \(error.localizedDescription)")
        }
    }

    func configureCheck(checkId: String, docType: KYCCheck.IDDocType, depth: KYCCheck.InvestigationDepth) {
        guard let i = idx(checkId) else { return }
        checks[i].expectedDocType = docType
        checks[i].investigationDepth = depth
        save()
    }

    // MARK: - Pipeline: ID + AML

    struct IDScanResult {
        let idResult: IDResult?
        let nameMismatch: (entered: String, extracted: String)?
        let isExpired: Bool
    }

    /// Step 1: ID scan only. Sets status to inProgress, stores results, does NOT set final status.
    func runIDScan(checkId: String, frontImage: Data, backImage: Data?) async throws -> IDScanResult {
        guard let i = idx(checkId) else { throw AppError.verificationFailed("Check not found") }

        checks[i].status = .inProgress; save()
        _ = saveImages(checkId: checkId, front: frontImage, back: backImage)

        let (idResp, idRaw) = try await api.verifyID(frontImage: frontImage, backImage: backImage, vendorData: checkId)
        let id = idResp.idVerification

        checks[i].extractedName = id?.extractedFullName
        // Auto-promote name from verification
        if let fullName = id?.extractedFullName, !fullName.isEmpty {
            checks[i].customerName = fullName
        }
        checks[i].documentType = id?.documentType
        checks[i].documentNumber = id?.documentNumber
        checks[i].dateOfBirth = id?.dateOfBirth
        checks[i].expiryDate = id?.expiryDate
        checks[i].nationality = id?.nationality
        checks[i].idWarnings = id?.warnings?.compactMap { $0.shortDescription ?? $0.risk }
        checks[i].rawIDResponse = String(data: idRaw, encoding: .utf8)
        if let dn = id?.documentNumber { checks[i].customerId = dn }

        // Auto-create passport document in the portfolio from verification results
        autoCreatePassportDoc(checkIndex: i, idResult: id)
        save() // triggers list update — still inProgress

        let exp = isExp(id?.expiryDate)
        return IDScanResult(
            idResult: id,
            nameMismatch: nameMismatch(entered: checks[i].customerName, extracted: id?.extractedFullName ?? ""),
            isExpired: exp
        )
    }

    /// Step 2: AML screening. Updates status to final based on combined ID+AML results.
    func runAMLScreening(checkId: String, monitoring: Bool = false) async throws -> AMLResult? {
        guard let i = idx(checkId) else { throw AppError.verificationFailed("Check not found") }

        let name = checks[i].extractedName ?? ""
        guard !name.isEmpty else { return nil }

        // Mark AML as in-progress (check stays inProgress)
        checks[i].amlStatus = "Screening..."; save()

        let iso2 = toISO2(checks[i].nationality) ?? toISO2(checks[i].documentType)
        let opts = VerificationAPIService.AMLOptions(includeAdverseMedia: true, includeMonitoring: monitoring)
        let (amlResp, amlRaw) = try await api.screenAML(
            fullName: name, dateOfBirth: checks[i].dateOfBirth,
            nationality: iso2, documentNumber: checks[i].documentNumber, vendorData: checkId,
            options: opts
        )
        let aml = amlResp.aml

        checks[i].amlStatus = aml?.status
        checks[i].amlScore = aml?.score
        checks[i].amlHitCount = aml?.totalHits
        checks[i].amlMonitoring = monitoring
        checks[i].rawAMLResponse = String(data: amlRaw, encoding: .utf8)

        // Now compute final status
        let exp = isExp(checks[i].expiryDate)
        let idWarn = checks[i].idWarnings?.isEmpty == false
        let amlFail = aml?.status == "Declined"
        let amlReview = aml?.status == "In Review"

        if amlFail || exp { checks[i].status = .failed }
        else if idWarn || amlReview { checks[i].status = .requiresReview }
        else { checks[i].status = .passed }
        checks[i].completedAt = Date()
        save() // triggers list update — now shows final status

        return aml
    }

    /// For ID-only depth (no AML). Finalizes status based on ID results alone.
    func finalizeIDOnly(checkId: String) {
        guard let i = idx(checkId) else { return }
        let exp = isExp(checks[i].expiryDate)
        let warn = checks[i].idWarnings?.isEmpty == false
        if exp { checks[i].status = .failed }
        else if warn { checks[i].status = .requiresReview }
        else { checks[i].status = .passed }
        checks[i].completedAt = Date(); save()
    }

    // MARK: - PoA

    struct PoAResult_ { let poaResult: PoAResult?; let rawJSON: String }

    func runPoA(checkId: String, documentImage: Data, expectedName: String?, expectedAddress: String?, onProgress: @escaping (String) -> Void) async throws -> PoAResult_ {
        guard let i = idx(checkId) else { throw AppError.verificationFailed("Check not found") }

        let fp = imagesDir.appendingPathComponent("\(checkId)_poa.jpg")
        try? documentImage.write(to: fp)
        checks[i].documentImagePaths = (checks[i].documentImagePaths ?? []) + [fp.lastPathComponent]

        onProgress("Verifying address...")
        let (resp, raw) = try await api.verifyAddress(document: documentImage, expectedName: expectedName, expectedAddress: expectedAddress, vendorData: checkId)
        let json = String(data: raw, encoding: .utf8) ?? ""
        let poa = resp.poa

        checks[i].poaStatus = poa?.status
        checks[i].poaAddress = poa?.poaFormattedAddress ?? poa?.poaAddress
        checks[i].poaIssuer = poa?.issuer
        checks[i].poaWarnings = poa?.warnings?.compactMap { $0.shortDescription ?? $0.risk }
        checks[i].rawPoAResponse = json
        checks[i].checkType = .idWithPoA
        if poa?.status == "Declined" { checks[i].status = .failed }
        else if poa?.warnings?.isEmpty == false && checks[i].status == .passed { checks[i].status = .requiresReview }
        checks[i].completedAt = Date(); save()

        return PoAResult_(poaResult: poa, rawJSON: json)
    }

    // MARK: - AML Re-run

    func updateAML(checkId: String, result: AMLResult?, rawJSON: String) {
        guard let i = idx(checkId) else { return }
        checks[i].amlStatus = result?.status
        checks[i].amlScore = result?.score
        checks[i].amlHitCount = result?.totalHits
        checks[i].rawAMLResponse = rawJSON

        // Re-evaluate
        let amlFail = result?.status == "Declined"
        let amlReview = result?.status == "In Review"
        let exp = isExp(checks[i].expiryDate)
        let warn = checks[i].idWarnings?.isEmpty == false

        if amlFail || exp { checks[i].status = .failed }
        else if warn || amlReview { checks[i].status = .requiresReview }
        else { checks[i].status = .passed }
        save()
    }

    // MARK: - Notes

    // MARK: - Agent Review

    func submitReview(checkId: String, decision: KYCCheck.ReviewDecision, reason: String) {
        guard let i = idx(checkId) else { return }
        checks[i].reviewDecision = decision
        checks[i].reviewReason = reason
        checks[i].reviewedAt = Date()
        checks[i].reviewedBy = UserDefaults.standard.string(forKey: "agentName") ?? "Agent"

        // Override status based on review
        switch decision {
        case .approved: checks[i].status = .passed
        case .flagged: checks[i].status = .requiresReview
        case .declined: checks[i].status = .failed
        }
        save()
    }

    func updateAgentNotes(checkId: String, notes: String) {
        guard let i = idx(checkId) else { return }
        checks[i].agentNotes = notes; save()
    }

    // MARK: - Images

    func saveImages(checkId: String, front: Data, back: Data?) -> [String] {
        var paths: [String] = []
        let fp = imagesDir.appendingPathComponent("\(checkId)_front.jpg"); try? front.write(to: fp); paths.append(fp.lastPathComponent)
        if let b = back { let bp = imagesDir.appendingPathComponent("\(checkId)_back.jpg"); try? b.write(to: bp); paths.append(bp.lastPathComponent) }
        if let i = idx(checkId) { checks[i].documentImagePaths = paths; save() }
        return paths
    }

    func loadDocumentImage(filename: String) -> Data? {
        try? Data(contentsOf: imagesDir.appendingPathComponent(filename))
    }

    // MARK: - Delete

    func deleteCheck(at offsets: IndexSet) {
        for i in offsets {
            if let paths = checks[i].documentImagePaths {
                for p in paths { try? FileManager.default.removeItem(at: imagesDir.appendingPathComponent(p)) }
            }
        }
        checks.remove(atOffsets: offsets); save()
    }

    // MARK: - Reset

    func resetAll() {
        KeychainService.deleteAll()
        UserDefaults.standard.removeObject(forKey: "agentName")
        try? FileManager.default.removeItem(at: checksFile)
        try? FileManager.default.removeItem(at: vesselsFile)
        try? FileManager.default.removeItem(at: imagesDir)
        try? FileManager.default.removeItem(at: reportsDir)
        checks = []; vessels = []
    }

    // MARK: - PDF

    func generateReport(checkId: String) -> URL? {
        guard let check = checks.first(where: { $0.id == checkId }) else {
            print("[OceanCheck] generateReport: check not found for \(checkId.prefix(8))")
            return nil
        }
        // Load captured images for embedding
        var docImages: [UIImage] = []
        if let paths = check.documentImagePaths {
            for p in paths {
                if let d = loadDocumentImage(filename: p), let img = UIImage(data: d) { docImages.append(img) }
            }
        }
        print("[OceanCheck] generateReport: \(check.customerName), status=\(check.status.rawValue), extractedName=\(check.extractedName ?? "nil"), docType=\(check.documentType ?? "nil"), hasRawID=\(check.rawIDResponse != nil)")
        let data = ReportGenerator.generatePDF(for: check, documentImages: docImages)
        print("[OceanCheck] generateReport: PDF data size = \(data.count) bytes")
        let name = "OceanCheck_Report_\(check.customerName.replacingOccurrences(of: " ", with: "_"))_\(check.id.prefix(8)).pdf"
        let url = reportsDir.appendingPathComponent(name)
        do {
            try data.write(to: url)
            print("[OceanCheck] generateReport: written to \(url.path)")
            return url
        } catch {
            print("[OceanCheck] generateReport: WRITE FAILED — \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Auto-populate passport from verification

    private func autoCreatePassportDoc(checkIndex i: Int, idResult: IDResult?) {
        guard let id = idResult else { return }
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        var docs = checks[i].documents ?? []
        // Replace placeholder passport or add new
        if let pi = docs.firstIndex(where: { $0.type == .passport && $0.imagePaths.isEmpty }) {
            docs[pi].documentNumber = id.documentNumber
            docs[pi].expiryDate = id.expiryDate.flatMap { fmt.date(from: $0) }
            docs[pi].issuingAuthority = id.issuingCountry
            docs[pi].imagePaths = checks[i].documentImagePaths ?? []
        } else if !docs.contains(where: { $0.type == .passport }) {
            docs.append(CrewDocument(
                type: .passport,
                imagePaths: checks[i].documentImagePaths ?? [],
                documentNumber: id.documentNumber,
                expiryDate: id.expiryDate.flatMap { fmt.date(from: $0) },
                issuingAuthority: id.issuingCountry
            ))
        }
        checks[i].documents = docs
        // Auto-set profile photo from passport front image
        if checks[i].profilePhoto == nil, let firstPath = checks[i].documentImagePaths?.first {
            checks[i].profilePhoto = firstPath
        }
    }

    // MARK: - Helpers

    private func idx(_ id: String) -> Int? { checks.firstIndex(where: { $0.id == id }) }

    private func isExp(_ s: String?) -> Bool {
        guard let s else { return false }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s).map { $0 < Date() } ?? false
    }

    /// Converts any country representation to ISO 3166-1 alpha-2.
    func toISO2(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        // Already alpha-2
        if trimmed.count == 2, Locale.Region.isoRegions.contains(where: { $0.identifier == trimmed }) {
            return trimmed
        }

        // Try alpha-3 → alpha-2 via Locale
        if trimmed.count == 3 {
            // Look up using Foundation
            for region in Locale.Region.isoRegions {
                let locale = Locale(identifier: "en_\(region.identifier)")
                if let code3 = locale.region?.identifier, code3.count == 2 {
                    // Check via Locale's identifier mapping
                }
            }
            // Manual common alpha-3 lookup
            if let found = alpha3Map[trimmed] { return found }
        }

        // Try matching by country name
        let lower = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for region in Locale.Region.isoRegions {
            let name = Locale(identifier: "en").localizedString(forRegionCode: region.identifier)?.lowercased() ?? ""
            if name == lower || lower.contains(name) || name.contains(lower) {
                return region.identifier
            }
        }

        // If it's already 2 chars, try it anyway
        if trimmed.count == 2 { return trimmed }

        return nil
    }

    private let alpha3Map: [String: String] = [
        "AFG": "AF", "ALB": "AL", "DZA": "DZ", "AND": "AD", "AGO": "AO",
        "ARG": "AR", "ARM": "AM", "AUS": "AU", "AUT": "AT", "AZE": "AZ",
        "BHS": "BS", "BHR": "BH", "BGD": "BD", "BRB": "BB", "BLR": "BY",
        "BEL": "BE", "BLZ": "BZ", "BEN": "BJ", "BTN": "BT", "BOL": "BO",
        "BIH": "BA", "BWA": "BW", "BRA": "BR", "BRN": "BN", "BGR": "BG",
        "BFA": "BF", "BDI": "BI", "KHM": "KH", "CMR": "CM", "CAN": "CA",
        "CPV": "CV", "CAF": "CF", "TCD": "TD", "CHL": "CL", "CHN": "CN",
        "COL": "CO", "COM": "KM", "COG": "CG", "COD": "CD", "CRI": "CR",
        "CIV": "CI", "HRV": "HR", "CUB": "CU", "CYP": "CY", "CZE": "CZ",
        "DNK": "DK", "DJI": "DJ", "DMA": "DM", "DOM": "DO", "ECU": "EC",
        "EGY": "EG", "SLV": "SV", "GNQ": "GQ", "ERI": "ER", "EST": "EE",
        "ETH": "ET", "FJI": "FJ", "FIN": "FI", "FRA": "FR", "GAB": "GA",
        "GMB": "GM", "GEO": "GE", "DEU": "DE", "GHA": "GH", "GRC": "GR",
        "GTM": "GT", "GIN": "GN", "GNB": "GW", "GUY": "GY", "HTI": "HT",
        "HND": "HN", "HUN": "HU", "ISL": "IS", "IND": "IN", "IDN": "ID",
        "IRN": "IR", "IRQ": "IQ", "IRL": "IE", "ISR": "IL", "ITA": "IT",
        "JAM": "JM", "JPN": "JP", "JOR": "JO", "KAZ": "KZ", "KEN": "KE",
        "KWT": "KW", "KGZ": "KG", "LAO": "LA", "LVA": "LV", "LBN": "LB",
        "LSO": "LS", "LBR": "LR", "LBY": "LY", "LIE": "LI", "LTU": "LT",
        "LUX": "LU", "MKD": "MK", "MDG": "MG", "MWI": "MW", "MYS": "MY",
        "MDV": "MV", "MLI": "ML", "MLT": "MT", "MRT": "MR", "MUS": "MU",
        "MEX": "MX", "MDA": "MD", "MCO": "MC", "MNG": "MN", "MNE": "ME",
        "MAR": "MA", "MOZ": "MZ", "MMR": "MM", "NAM": "NA", "NPL": "NP",
        "NLD": "NL", "NZL": "NZ", "NIC": "NI", "NER": "NE", "NGA": "NG",
        "NOR": "NO", "OMN": "OM", "PAK": "PK", "PAN": "PA", "PNG": "PG",
        "PRY": "PY", "PER": "PE", "PHL": "PH", "POL": "PL", "PRT": "PT",
        "QAT": "QA", "ROU": "RO", "RUS": "RU", "RWA": "RW", "SAU": "SA",
        "SEN": "SN", "SRB": "RS", "SGP": "SG", "SVK": "SK", "SVN": "SI",
        "SOM": "SO", "ZAF": "ZA", "KOR": "KR", "ESP": "ES", "LKA": "LK",
        "SDN": "SD", "SUR": "SR", "SWZ": "SZ", "SWE": "SE", "CHE": "CH",
        "SYR": "SY", "TWN": "TW", "TJK": "TJ", "TZA": "TZ", "THA": "TH",
        "TLS": "TL", "TGO": "TG", "TTO": "TT", "TUN": "TN", "TUR": "TR",
        "TKM": "TM", "UGA": "UG", "UKR": "UA", "ARE": "AE", "GBR": "GB",
        "USA": "US", "URY": "UY", "UZB": "UZ", "VEN": "VE", "VNM": "VN",
        "YEM": "YE", "ZMB": "ZM", "ZWE": "ZW", "PSE": "PS", "XKX": "XK",
        "SSD": "SS", "D": "DE", "F": "FR", "GB": "GB"
    ]

    private func nameMismatch(entered: String, extracted: String) -> (String, String)? {
        guard !extracted.isEmpty else { return nil }
        let e = Set(entered.lowercased().split(separator: " ").map(String.init))
        let x = Set(extracted.lowercased().split(separator: " ").map(String.init))
        return Double(e.intersection(x).count) / Double(max(e.count, x.count, 1)) < 0.5 ? (entered, extracted) : nil
    }
}
