//
//  KYCViewModel.swift
//  OceanCheck
//
//  Core state management. Business logic split into extensions:
//  - KYCViewModel+Verification.swift   (ID scan, AML, PoA, polling, invites)
//  - KYCViewModel+Reports.swift        (PDF, CSV, compliance packets, owner dashboard)
//  - KYCViewModel+Transfer.swift       (.oceancheck packages, import/export)
//  - KYCViewModel+Persistence.swift    (backup, restore, file helpers)
//

import Foundation
import Combine
import SwiftUI
import Network
import os.log
import WidgetKit

private let vmLogger = Logger(subsystem: "com.seapay.kyc", category: "ViewModel")

@MainActor
class KYCViewModel: ObservableObject {
    @Published var checks: [KYCCheck] = []
    @Published var vessels: [Vessel] = []
    @Published var isOnline = true {
        didSet {
            if isOnline && !oldValue {
                // Connectivity restored — flush all pending work
                Task {
                    await offlineQueue.processQueue(vm: self)
                    await MainActor.run { pushPendingVessels() }
                }
            }
        }
    }
    @Published var pollingError: String?
    @Published var transferLog: [TransferRecord] = []
    let offlineQueue = OfflineQueue.shared

    // GDPR
    @Published var consentRecords: [ConsentRecord] = []
    @Published var auditLog: [AuditEvent] = []
    var retentionPolicy: RetentionPolicy {
        get {
            guard let data = UserDefaults.standard.data(forKey: "retentionPolicy"),
                  let policy = try? JSONDecoder().decode(RetentionPolicy.self, from: data) else { return .default }
            return policy
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) { UserDefaults.standard.set(data, forKey: "retentionPolicy") }
        }
    }

    private var consentFile: URL { docsDir.appendingPathComponent("consent_records.json") }
    private var auditFile: URL { docsDir.appendingPathComponent("audit_log.json") }

    var pollTimers: [String: Timer] = [:]
    private let netMonitor = NWPathMonitor()
    private let imageCache = NSCache<NSString, NSData>()
    private var deferredBackupTask: Task<Void, Never>?
    private var didLoad = false

    // MARK: - Storage Paths

    var docsDir: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory }
    private var checksFile: URL { docsDir.appendingPathComponent("kyc_checks.json") }
    private var vesselsFile: URL { docsDir.appendingPathComponent("vessels.json") }
    private var transferLogFile: URL { docsDir.appendingPathComponent("transfer_log.json") }
    var imagesDir: URL {
        let d = docsDir.appendingPathComponent("captured_documents")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true); return d
    }
    var reportsDir: URL {
        let d = docsDir.appendingPathComponent("reports")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true); return d
    }

    let services: ServiceContainer

    init(services: ServiceContainer? = nil) {
        self.services = services ?? .shared
        netMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in self?.isOnline = path.status == .satisfied }
        }
        netMonitor.start(queue: DispatchQueue(label: "net.monitor"))
    }

    deinit {
        pollTimers.values.forEach { $0.invalidate() }
        netMonitor.cancel()
    }

    // MARK: - Load / Save (internal — used by extensions)

    func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        Task { [weak self] in
            guard let self else { return }
            let checksURL = self.checksFile
            let vesselsURL = self.vesselsFile
            let transferURL = self.transferLogFile

            EncryptionService.migrateIfNeeded(at: checksURL)
            EncryptionService.migrateIfNeeded(at: vesselsURL)
            EncryptionService.migrateIfNeeded(at: transferURL)

            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            let loadedChecks = EncryptionService.readDecrypted(from: checksURL).flatMap { try? decoder.decode([KYCCheck].self, from: $0) } ?? []
            let loadedVessels = EncryptionService.readDecrypted(from: vesselsURL).flatMap { try? decoder.decode([Vessel].self, from: $0) } ?? []
            let loadedTransfers = EncryptionService.readDecrypted(from: transferURL).flatMap { try? decoder.decode([TransferRecord].self, from: $0) } ?? []

            let consentURL = self.consentFile
            let auditURL = self.auditFile
            let loadedConsent = EncryptionService.readDecrypted(from: consentURL).flatMap { try? decoder.decode([ConsentRecord].self, from: $0) } ?? []
            EncryptionService.migrateIfNeeded(at: auditURL)
            let loadedAudit = EncryptionService.readDecrypted(from: auditURL).flatMap { try? decoder.decode([AuditEvent].self, from: $0) } ?? []

            self.checks = loadedChecks
            self.vessels = loadedVessels
            self.transferLog = loadedTransfers
            self.consentRecords = loadedConsent
            self.auditLog = loadedAudit
            self.startPollingPendingSessions()
            self.offlineQueue.startObserving(vm: self)
            self.offlineQueue.clearStale()

            // Auto-restore from server if local data is empty
            if loadedChecks.isEmpty && loadedVessels.isEmpty {
                Task {
                    if let backup = await ServerBackupService.shared.pullBackup() {
                        if !backup.vessels.isEmpty || !backup.checks.isEmpty {
                            self.vessels = backup.vessels
                            self.checks = backup.checks
                            self.saveVessels()
                            self.saveChecks()
                            Haptics.success()
                        }
                    }
                }
            }
        }
    }

    func reloadAll() {
        if let data = EncryptionService.readDecrypted(from: checksFile) {
            let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
            checks = (try? d.decode([KYCCheck].self, from: data)) ?? []
        }
        if let data = EncryptionService.readDecrypted(from: vesselsFile) {
            let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
            vessels = (try? d.decode([Vessel].self, from: data)) ?? []
        }
        if let data = EncryptionService.readDecrypted(from: transferLogFile) {
            let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
            transferLog = (try? d.decode([TransferRecord].self, from: data)) ?? []
        }
    }

    func saveChecks() {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = .prettyPrinted
        if let data = try? e.encode(checks) {
            if checks.isEmpty && FileManager.default.fileExists(atPath: checksFile.path) {
                let existing = EncryptionService.readDecrypted(from: checksFile)
                if let existing, existing.count > 10 { return }
            }
            try? EncryptionService.writeEncrypted(data, to: checksFile)
        }
        objectWillChange.send()
        deferHeavyWork()
        // Server backup — debounced, non-blocking
        ServerBackupService.shared.scheduleBackup(vessels: vessels, checks: checks)
    }

    func saveVessels() {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = .prettyPrinted
        if let data = try? e.encode(vessels) {
            if vessels.isEmpty && FileManager.default.fileExists(atPath: vesselsFile.path) {
                let existing = EncryptionService.readDecrypted(from: vesselsFile)
                if let existing, existing.count > 10 { return }
            }
            try? EncryptionService.writeEncrypted(data, to: vesselsFile)
        }
        objectWillChange.send()
        deferHeavyWork()
        ServerBackupService.shared.scheduleBackup(vessels: vessels, checks: checks)
    }

    func saveTransferLog() {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = .prettyPrinted
        if let data = try? e.encode(transferLog) { try? EncryptionService.writeEncrypted(data, to: transferLogFile) }
    }

    // MARK: - GDPR Persistence

    func saveConsentRecords() {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = .prettyPrinted
        if let data = try? e.encode(consentRecords) { try? EncryptionService.writeEncrypted(data, to: consentFile) }
    }

    func saveAuditLog() {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = .prettyPrinted
        if let data = try? e.encode(auditLog) { try? EncryptionService.writeEncrypted(data, to: auditFile) }
    }

    func logAudit(_ action: AuditEvent.AuditAction, entityId: String, entityName: String, detail: String? = nil) {
        GDPRService.logAudit(action: action, entityId: entityId, entityName: entityName,
            performedBy: AgentProfile.current?.fullName ?? "Agent", detail: detail, log: &auditLog)
        saveAuditLog()
    }

    func recordConsent(checkId: String, subjectName: String) {
        GDPRService.recordConsent(subjectName: subjectName, checkId: checkId,
            types: [.identityVerification, .amlScreening, .dataProcessing], store: &consentRecords)
        saveConsentRecords()
    }

    func exportDSAR(name: String) -> URL? {
        GDPRService.exportSubjectData(name: name, checks: checks, vessels: vessels, consentRecords: consentRecords, auditLog: auditLog)
    }

    var retentionFlaggedChecks: [KYCCheck] {
        GDPRService.flaggedForRetention(checks: checks, policy: retentionPolicy)
    }

    private func deferHeavyWork() {
        deferredBackupTask?.cancel()
        deferredBackupTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled, let self else { return }
            self.services.notifications.rescheduleAll(checks: self.checks, vessels: self.vessels)
            self.services.cloudBackup.backup(checksFile: self.checksFile, vesselsFile: self.vesselsFile, imagesDir: self.imagesDir)
            self.updateWidgetData()
            AppBadge.update(checks: self.checks, vessels: self.vessels)
        }
    }

    /// Write a lightweight expiry snapshot to the App Group container for the widget.
    private func updateWidgetData() {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.navemagna.SeaPay-KYC") else { return }

        let dateFmt = DateFormatter(); dateFmt.dateFormat = "yyyy-MM-dd"
        let displayFmt = DateFormatter(); displayFmt.dateFormat = "dd MMM yyyy"
        let now = Date()
        let cutoff = Calendar.current.date(byAdding: .day, value: 90, to: now) ?? now

        var expired = 0, expiring = 0
        var nextDate: Date?
        var nextName: String?

        for check in checks {
            if let s = check.expiryDate, let d = dateFmt.date(from: s) {
                if d < now { expired += 1 }
                else if d <= cutoff {
                    expiring += 1
                    if nextDate == nil || d < nextDate! { nextDate = d; nextName = "\(check.documentType ?? "ID") — \(check.displayName)" }
                }
            }
            for doc in check.documents ?? [] where !doc.isArchived {
                guard let d = doc.expiryDate else { continue }
                if d < now { expired += 1 }
                else if d <= cutoff {
                    expiring += 1
                    if nextDate == nil || d < nextDate! { nextDate = d; nextName = "\(doc.type.displayName) — \(check.displayName)" }
                }
            }
        }
        for vessel in vessels {
            for doc in vessel.documents ?? [] where !doc.isArchived {
                guard let d = doc.expiryDate else { continue }
                if d < now { expired += 1 }
                else if d <= cutoff {
                    expiring += 1
                    if nextDate == nil || d < nextDate! { nextDate = d; nextName = "\(doc.displayName) — \(vessel.name)" }
                }
            }
        }

        let snapshot: [String: Any] = [
            "expiredCount": expired,
            "expiringCount": expiring,
            "nextExpiryDate": nextDate.map { displayFmt.string(from: $0) } as Any,
            "nextExpiryName": nextName as Any,
            "vesselCount": vessels.count,
            "crewCount": checks.count,
            "updatedAt": ISO8601DateFormatter().string(from: now)
        ]

        let file = container.appendingPathComponent("widget_expiry.json")
        try? JSONSerialization.data(withJSONObject: snapshot, options: .prettyPrinted).write(to: file)

        // Tell WidgetKit to refresh
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Image Cache

    func loadDocumentImage(filename: String) -> Data? {
        let key = filename as NSString
        if let cached = imageCache.object(forKey: key) { return cached as Data }
        guard let data = try? Data(contentsOf: imagesDir.appendingPathComponent(filename)) else { return nil }
        imageCache.setObject(data as NSData, forKey: key)
        return data
    }

    func invalidateImageCache(filename: String) {
        imageCache.removeObject(forKey: filename as NSString)
    }

    /// Vessel IDs waiting to push when connectivity returns
    private var pendingPushVesselIds: Set<String> = []

    /// Auto-push a vessel's full data (JSON + files) to the workspace backend.
    /// If offline, queues the vessel ID and pushes when connectivity returns.
    func autoPushVessel(vesselId: String) {
        guard CollaborationService.shared.isConnected else {
            pendingPushVesselIds.insert(vesselId); return
        }
        guard isOnline else {
            pendingPushVesselIds.insert(vesselId); return
        }
        guard let vessel = vessels.first(where: { $0.id == vesselId }) else { return }
        Task {
            let activityId = SyncActivityMonitor.shared.begin("Syncing \(vessel.name)", type: .push)
            let checks = checksForVessel(vesselId)
            let ok = (try? await CollaborationService.shared.pushVessel(vessel: vessel, checks: checks)) != nil
            await FilesSyncService.shared.uploadMissingFiles(vesselId: vesselId, vm: self)
            SyncActivityMonitor.shared.complete(activityId, success: ok)
        }
    }

    /// Flush all pending vessel pushes (called when connectivity restored)
    private func pushPendingVessels() {
        let ids = pendingPushVesselIds
        pendingPushVesselIds.removeAll()
        for id in ids { autoPushVessel(vesselId: id) }
    }

    /// Queue a file for background upload to the workspace (if connected).
    /// Called after any local file save so collaborators get files automatically.
    func queueFileForSync(filename: String, vesselId: String?) {
        guard CollaborationService.shared.isConnected,
              let token = CollaborationService.shared.workspace?.token,
              let vid = vesselId else { return }
        Task {
            let filePath = imagesDir.appendingPathComponent(filename)
            guard let data = try? Data(contentsOf: filePath) else { return }
            _ = await FilesSyncService.shared.uploadSingleFile(filename: filename, data: data, vesselId: vid, token: token)
        }
    }

    // MARK: - Vessel CRUD

    @discardableResult
    func createVessel(name: String, imoNumber: String = "", flagState: String = "", portOfRegistry: String = "", vesselType: VesselType? = nil) -> Vessel {
        let v = Vessel(name: name, imoNumber: imoNumber, flagState: flagState, portOfRegistry: portOfRegistry, vesselType: vesselType)
        vessels.insert(v, at: 0); saveVessels(); return v
    }

    func updateVessel(_ vessel: Vessel) {
        guard let i = vessels.firstIndex(where: { $0.id == vessel.id }) else { return }
        vessels[i] = vessel; saveVessels()
        refreshRequirementsForVessel(vesselId: vessel.id)
        autoPushVessel(vesselId: vessel.id)
    }

    /// Recalculate required documents for all crew assigned to a vessel.
    /// Only ADDS missing placeholders — never removes existing documents.
    func refreshRequirementsForVessel(vesselId: String) {
        var changed = false
        for i in checks.indices where checks[i].vesselId == vesselId {
            let required = requiredDocuments(for: checks[i])
            let existing = Set((checks[i].documents ?? []).map(\.type))
            var docs = checks[i].documents ?? []
            for dt in required where !existing.contains(dt) {
                docs.append(CrewDocument(type: dt))
                changed = true
            }
            checks[i].documents = docs
        }
        if changed { saveChecks() }
    }

    func deleteVessel(id: String) {
        if let vessel = vessels.first(where: { $0.id == id }) {
            if let photo = vessel.photoFilename {
                invalidateImageCache(filename: photo)
                try? FileManager.default.removeItem(at: imagesDir.appendingPathComponent(photo))
            }
        }
        for i in checks.indices where checks[i].vesselId == id { checks[i].vesselId = nil }
        saveChecks()
        vessels.removeAll { $0.id == id }; saveVessels()
    }

    // MARK: - Vessel Photo

    func saveVesselPhoto(vesselId: String, imageData: Data) {
        let filename = "\(vesselId)_photo.jpg"
        let compressed: Data
        if let img = UIImage(data: imageData) {
            let maxDim: CGFloat = 1200
            let scale = min(maxDim / max(img.size.width, img.size.height), 1)
            let size = CGSize(width: img.size.width * scale, height: img.size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: size)
            compressed = renderer.jpegData(withCompressionQuality: 0.8) { ctx in img.draw(in: CGRect(origin: .zero, size: size)) }
        } else { compressed = imageData }
        try? compressed.write(to: imagesDir.appendingPathComponent(filename))
        invalidateImageCache(filename: filename)
        guard let i = vessels.firstIndex(where: { $0.id == vesselId }) else { return }
        vessels[i].photoFilename = filename
        saveVessels()
        queueFileForSync(filename: filename, vesselId: vesselId)
    }

    func deleteVesselPhoto(vesselId: String) {
        guard let i = vessels.firstIndex(where: { $0.id == vesselId }) else { return }
        if let f = vessels[i].photoFilename {
            invalidateImageCache(filename: f)
            try? FileManager.default.removeItem(at: imagesDir.appendingPathComponent(f))
        }
        vessels[i].photoFilename = nil
        saveVessels()
    }

    // MARK: - Check Queries

    func checksForVessel(_ vesselId: String) -> [KYCCheck] { checks.filter { $0.vesselId == vesselId } }
    func seafarersForVessel(_ vesselId: String) -> [KYCCheck] { checks.filter { $0.vesselId == vesselId && $0.entityType.category == .crew } }
    func complianceChecksForVessel(_ vesselId: String) -> [KYCCheck] { checks.filter { $0.vesselId == vesselId && $0.entityType.category == .ownership } }
    func shoreBasedForVessel(_ vesselId: String) -> [KYCCheck] { checks.filter { $0.vesselId == vesselId && $0.entityType.category == .shoreBased } }
    var unassignedChecks: [KYCCheck] { checks.filter { $0.vesselId == nil } }

    func assignCheckToVessel(checkId: String, vesselId: String) {
        guard let i = checkIndex(checkId) else { return }
        checks[i].vesselId = vesselId; saveChecks()
    }

    func unassignCheckFromVessel(checkId: String) {
        guard let i = checkIndex(checkId) else { return }
        checks[i].vesselId = nil; saveChecks()
    }

    func updateCheckName(checkId: String, name: String) {
        guard let i = checkIndex(checkId) else { return }
        checks[i].customerName = name
        if checks[i].extractedName != nil { checks[i].extractedName = name }
        saveChecks()
    }

    func updateEntityType(checkId: String, entityType: KYCCheck.EntityType) {
        guard let i = checkIndex(checkId) else { return }
        checks[i].entityType = entityType; saveChecks()
    }

    func updateOwnershipPercent(checkId: String, percent: Double) {
        guard let i = checkIndex(checkId) else { return }
        checks[i].ownershipPercent = percent; saveChecks()
    }

    func deleteCheckById(_ checkId: String) {
        Haptics.warning()
        stopPolling(checkId: checkId)
        guard let i = checkIndex(checkId) else { return }
        if let paths = checks[i].documentImagePaths {
            for p in paths { invalidateImageCache(filename: p); try? FileManager.default.removeItem(at: imagesDir.appendingPathComponent(p)) }
        }
        if let photo = checks[i].profilePhoto { invalidateImageCache(filename: photo) }
        checks.remove(at: i); saveChecks()
    }

    func deleteCheck(at offsets: IndexSet) {
        for i in offsets {
            if let paths = checks[i].documentImagePaths {
                for p in paths { try? FileManager.default.removeItem(at: imagesDir.appendingPathComponent(p)) }
            }
        }
        checks.remove(atOffsets: offsets); saveChecks()
    }

    // MARK: - Expiry Intelligence

    private static let expiryDateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    var expiringChecks: [KYCCheck] {
        let cutoff = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
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
        if check.entityType != .seafarer { return FlagStateRequirements.requiredForEntity(check.entityType) }
        let vessel = check.vesselId.flatMap { vid in vessels.first { $0.id == vid } }
        let flag = vessel?.flagState ?? ""
        let vt = vessel?.vesselType
        let gt = vessel?.grossTonnageValue
        let loa = vessel?.lengthOverallMetres

        // Try knowledge base first (JSON rules)
        if let result = KnowledgeBaseService.shared.crewRequirements(flag: flag, vesselType: vt, gt: gt, loa: loa, rank: check.crewRank) {
            return result.docs
        }

        // Fallback to hardcoded FlagStateRequirements
        return FlagStateRequirements.required(flag: flag, vesselType: vt, rank: check.crewRank)
    }

    struct PortfolioItem: Identifiable {
        let id = UUID().uuidString
        let type: MaritimeDocType; var document: CrewDocument?; let required: Bool
    }

    func documentPortfolio(for check: KYCCheck) -> [PortfolioItem] {
        var required = Set(requiredDocuments(for: check))
        // Always show PoA slot when a PoA verification exists or depth includes it
        if check.poaStatus != nil || check.investigationDepth == .idAmlPoa {
            required.insert(.proofOfAddress)
        }
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

    // MARK: - Crew Management Updates

    func updatePhoneNumber(checkId: String, phone: String) {
        guard let i = checkIndex(checkId) else { return }
        checks[i].phoneNumber = phone.isEmpty ? nil : phone; saveChecks()
        if let vid = checks[i].vesselId { autoPushVessel(vesselId: vid) }
    }

    func updateEmailAddress(checkId: String, email: String) {
        guard let i = checkIndex(checkId) else { return }
        checks[i].emailAddress = email.isEmpty ? nil : email; saveChecks()
        if let vid = checks[i].vesselId { autoPushVessel(vesselId: vid) }
    }

    func updateEmergencyContact(checkId: String, contact: EmergencyContact?) {
        guard let i = checkIndex(checkId) else { return }
        checks[i].emergencyContact = contact; saveChecks()
        if let vid = checks[i].vesselId { autoPushVessel(vesselId: vid) }
    }

    func updateNextOfKin(checkId: String, kin: NextOfKin?) {
        guard let i = checkIndex(checkId) else { return }
        checks[i].nextOfKin = kin; saveChecks()
        if let vid = checks[i].vesselId { autoPushVessel(vesselId: vid) }
    }

    func updateContractDates(checkId: String, start: Date?, end: Date?) {
        guard let i = checkIndex(checkId) else { return }
        checks[i].contractStartDate = start; checks[i].contractEndDate = end; saveChecks()
        if let vid = checks[i].vesselId { autoPushVessel(vesselId: vid) }
    }

    func updateAvailabilityStatus(checkId: String, status: KYCCheck.AvailabilityStatus?) {
        guard let i = checkIndex(checkId) else { return }
        checks[i].availabilityStatus = status; saveChecks()
        if let vid = checks[i].vesselId { autoPushVessel(vesselId: vid) }
    }

    func updateContractFromSEA(checkId: String, sea: ClaudeService.SEAExtraction) {
        guard let i = checkIndex(checkId) else { return }
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        if let w = sea.wages { checks[i].wages = w }
        if let c = sea.currency { checks[i].currency = c }
        if let h = sea.hoursOfWork { checks[i].hoursOfWork = h }
        if let l = sea.leaveEntitlement { checks[i].leaveEntitlement = l }
        if let p = sea.portOfEngagement { checks[i].portOfEngagement = p }
        if let m = sea.manningAgency { checks[i].manningAgency = m }
        if let c = sea.cbaReference { checks[i].cbaReference = c }
        if let m = sea.mlcCompliant { checks[i].mlcCompliant = m }
        if let r = sea.repatriationPort { checks[i].repatriationPort = r }
        let startDate = sea.contractStart.flatMap { fmt.date(from: $0) }
        let endDate = sea.contractEnd.flatMap { fmt.date(from: $0) }
        if let d = startDate { checks[i].contractStartDate = d }
        if let d = endDate { checks[i].contractEndDate = d }
        // Contact info — only fill if not already set
        if checks[i].phoneNumber == nil, let p = sea.phoneNumber, !p.isEmpty { checks[i].phoneNumber = p }
        if checks[i].emailAddress == nil, let e = sea.emailAddress, !e.isEmpty { checks[i].emailAddress = e }
        if checks[i].emergencyContact == nil, let n = sea.emergencyContactName, !n.isEmpty {
            checks[i].emergencyContact = EmergencyContact(name: n, phone: sea.emergencyContactPhone ?? "", relationship: sea.emergencyContactRelation ?? "")
        }
        if checks[i].nextOfKin == nil, let n = sea.nextOfKinName, !n.isEmpty {
            checks[i].nextOfKin = NextOfKin(name: n, relationship: sea.nextOfKinRelation ?? "")
        }

        // Update the SEA document in the portfolio with extracted dates
        if var docs = checks[i].documents,
           let di = docs.firstIndex(where: { $0.type == .seafarerEmployment }) {
            if docs[di].issueDate == nil, let d = startDate { docs[di].issueDate = d }
            if docs[di].expiryDate == nil, let d = endDate { docs[di].expiryDate = d }
            if docs[di].issuingAuthority == nil, let a = sea.manningAgency, !a.isEmpty { docs[di].issuingAuthority = a }
            checks[i].documents = docs
        }

        saveChecks()
        if let vid = checks[i].vesselId { autoPushVessel(vesselId: vid) }
    }

    /// Enrich a document with OCR-extracted data and update the check's fields
    func enrichDocumentWithOCR(checkId: String, documentId: String, extraction: ClaudeService.DocExtraction) {
        guard let ci = checkIndex(checkId) else { return }
        guard var docs = checks[ci].documents,
              let di = docs.firstIndex(where: { $0.id == documentId }) else { return }

        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"

        // Enrich the document itself
        if docs[di].documentNumber == nil, let v = extraction.documentNumber, !v.isEmpty { docs[di].documentNumber = v }
        if docs[di].issuingAuthority == nil, let v = extraction.issuingAuthority, !v.isEmpty { docs[di].issuingAuthority = v }
        if docs[di].issueDate == nil, let v = extraction.issueDate, let d = fmt.date(from: v) { docs[di].issueDate = d }
        if docs[di].expiryDate == nil, let v = extraction.expiryDate, let d = fmt.date(from: v) { docs[di].expiryDate = d }

        // Build notes from extra extracted info
        var extras: [String] = []
        if let v = extraction.certificateGrade, !v.isEmpty { extras.append("Grade: \(v)") }
        if let v = extraction.flagState, !v.isEmpty { extras.append("Flag: \(v)") }
        if let v = extraction.restrictions, !v.isEmpty { extras.append("Restrictions: \(v)") }
        if let v = extraction.notes, !v.isEmpty { extras.append(v) }
        if !extras.isEmpty { docs[di].notes = extras.joined(separator: " · ") }

        // Auto-match document type if currently .other and Claude suggests one
        if docs[di].type == .other, let suggested = extraction.suggestedDocType, !suggested.isEmpty {
            if let matched = MaritimeDocType.allCases.first(where: { $0.displayName.localizedCaseInsensitiveContains(suggested) || suggested.localizedCaseInsensitiveContains($0.displayName) }) {
                let typeExists = docs.contains(where: { $0.id != docs[di].id && $0.type == matched && !$0.imagePaths.isEmpty })
                if typeExists {
                    // Keep as additional, set AI-derived custom name
                    docs[di].customName = suggested
                } else {
                    docs[di].type = matched
                }
            } else {
                // No enum match — use Claude's suggestion as the custom display name
                docs[di].customName = suggested
            }
        }

        checks[ci].documents = docs

        // Enrich the check itself from holder info
        if let name = extraction.holderName, !name.isEmpty, checks[ci].extractedName == nil {
            checks[ci].customerName = name
        }
        if let rank = extraction.rank, !rank.isEmpty, checks[ci].crewRank == nil {
            if let matched = CrewRank.allCases.first(where: { $0.rawValue.localizedCaseInsensitiveContains(rank) || rank.localizedCaseInsensitiveContains($0.rawValue) }) {
                checks[ci].crewRank = matched
            }
        }

        saveChecks()
        if let vid = checks[ci].vesselId { autoPushVessel(vesselId: vid) }
    }

    func setCrewRank(_ rank: CrewRank, for checkId: String) {
        guard let i = checkIndex(checkId) else { return }
        checks[i].crewRank = rank
        let required = requiredDocuments(for: checks[i])
        let existing = Set((checks[i].documents ?? []).map(\.type))
        var docs = checks[i].documents ?? []
        for dt in required where !existing.contains(dt) { docs.append(CrewDocument(type: dt)) }
        checks[i].documents = docs
        saveChecks()
    }

    /// Bulk-add documents from AI analysis (Magic Upload)
    func addDocumentsFromAnalysis(checkId: String, analysis: ClaudeService.DocumentAnalysis, fileData: Data, filename: String) {
        guard let ci = checkIndex(checkId) else { return }
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"

        for analyzed in analysis.documents {
            // Match type
            let docType: MaritimeDocType = {
                if let suggested = analyzed.documentType {
                    return MaritimeDocType.allCases.first(where: {
                        $0.displayName.localizedCaseInsensitiveContains(suggested) ||
                        suggested.localizedCaseInsensitiveContains($0.displayName)
                    }) ?? .other
                }
                return .other
            }()

            let doc = CrewDocument(
                type: docType,
                customName: docType == .other ? analyzed.documentType : nil,
                imagePaths: [filename],
                documentNumber: analyzed.documentNumber,
                issueDate: analyzed.issueDate.flatMap { fmt.date(from: $0) },
                expiryDate: analyzed.expiryDate.flatMap { fmt.date(from: $0) },
                issuingAuthority: analyzed.issuingAuthority,
                notes: analyzed.notes
            )

            var docs = checks[ci].documents ?? []
            // Batch dedup: skip if same type + same doc number already in array
            let isDuplicate = docs.contains(where: {
                $0.type == docType && !$0.imagePaths.isEmpty &&
                (doc.documentNumber != nil && $0.documentNumber == doc.documentNumber)
            })
            if isDuplicate { continue }

            if let existing = docs.firstIndex(where: { $0.type == docType && $0.imagePaths.isEmpty }) {
                docs[existing] = doc
            } else { docs.append(doc) }
            checks[ci].documents = docs
        }
        saveChecks()
        if let vid = checks[ci].vesselId { autoPushVessel(vesselId: vid) }
    }

    /// Bulk-add vessel documents from AI analysis (Magic Upload)
    func addVesselDocumentsFromAnalysis(vesselId: String, analysis: ClaudeService.DocumentAnalysis, filename: String) {
        guard let vi = vessels.firstIndex(where: { $0.id == vesselId }) else { return }
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"

        for analyzed in analysis.documents {
            let vdt: VesselDocType = {
                if let suggested = analyzed.documentType {
                    return VesselDocType.allCases.first(where: {
                        $0.displayName.localizedCaseInsensitiveContains(suggested) ||
                        suggested.localizedCaseInsensitiveContains($0.displayName)
                    }) ?? .other
                }
                return .other
            }()

            let doc = CrewDocument(
                vesselDocType: vdt,
                imagePaths: [filename],
                documentNumber: analyzed.documentNumber,
                issueDate: analyzed.issueDate.flatMap { fmt.date(from: $0) },
                expiryDate: analyzed.expiryDate.flatMap { fmt.date(from: $0) },
                issuingAuthority: analyzed.issuingAuthority,
                notes: analyzed.notes
            )
            var docs = vessels[vi].documents ?? []
            docs.append(doc)
            vessels[vi].documents = docs
        }
        saveVessels()
        autoPushVessel(vesselId: vesselId)
    }

    enum AddDocResult {
        case added, replacedStub, duplicate(existing: CrewDocument)
    }

    @discardableResult
    func addDocument(to checkId: String, document: CrewDocument, force: Bool = false) -> AddDocResult {
        guard let i = checkIndex(checkId) else { return .added }
        var docs = checks[i].documents ?? []

        // Replace empty stub placeholder
        if let si = docs.firstIndex(where: { $0.type == document.type && $0.imagePaths.isEmpty }) {
            docs[si] = document
            checks[i].documents = docs; saveChecks()
            if let vid = checks[i].vesselId { autoPushVessel(vesselId: vid) }
            return .replacedStub
        }

        // Duplicate detection (same type with existing images)
        if !force, let existing = docs.first(where: { $0.type == document.type && !$0.imagePaths.isEmpty }) {
            return .duplicate(existing: existing)
        }

        docs.append(document)
        checks[i].documents = docs; saveChecks()
        if let vid = checks[i].vesselId { autoPushVessel(vesselId: vid) }
        return .added
    }

    /// Replace an existing document with a new version (for duplicate resolution)
    func replaceDocument(checkId: String, oldDocId: String, newDoc: CrewDocument) {
        guard let i = checkIndex(checkId) else { return }
        guard var docs = checks[i].documents, let di = docs.firstIndex(where: { $0.id == oldDocId }) else { return }
        var replacement = newDoc
        replacement.previousVersionId = oldDocId
        docs[di] = replacement
        checks[i].documents = docs; saveChecks()
        if let vid = checks[i].vesselId { autoPushVessel(vesselId: vid) }
    }

    func updateDocument(checkId: String, document: CrewDocument) {
        guard let i = checkIndex(checkId) else { return }
        guard var docs = checks[i].documents, let di = docs.firstIndex(where: { $0.id == document.id }) else { return }
        docs[di] = document; checks[i].documents = docs; saveChecks()
        if let vid = checks[i].vesselId { autoPushVessel(vesselId: vid) }
    }

    func removeDocument(checkId: String, documentId: String) {
        guard let i = checkIndex(checkId) else { return }
        let vid = checks[i].vesselId
        checks[i].documents?.removeAll { $0.id == documentId }; saveChecks()
        if let vid { autoPushVessel(vesselId: vid) }
    }

    var allExpiringDocuments: [(check: KYCCheck, document: CrewDocument)] {
        let cutoff = Calendar.current.date(byAdding: .day, value: 90, to: Date()) ?? Date()
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

    func removeProfilePhoto(checkId: String) {
        guard let i = checkIndex(checkId) else { return }
        if let filename = checks[i].profilePhoto {
            invalidateImageCache(filename: filename)
            try? FileManager.default.removeItem(at: imagesDir.appendingPathComponent(filename))
        }
        checks[i].profilePhoto = nil; saveChecks()
    }

    func renewDocument(checkId: String, oldDocId: String, newDoc: CrewDocument) {
        guard let i = checkIndex(checkId) else { return }
        guard var docs = checks[i].documents, let di = docs.firstIndex(where: { $0.id == oldDocId }) else { return }
        docs[di].renewedAt = Date()
        var renewed = newDoc; renewed.previousVersionId = oldDocId
        docs.append(renewed); checks[i].documents = docs; saveChecks()
        if let vid = checks[i].vesselId { autoPushVessel(vesselId: vid) }
    }

    // MARK: - Vessel Documents

    func addVesselDocument(to vesselId: String, document: CrewDocument) {
        guard let i = vessels.firstIndex(where: { $0.id == vesselId }) else { return }
        var docs = vessels[i].documents ?? []
        docs.append(document); vessels[i].documents = docs; saveVessels()
        autoPushVessel(vesselId: vesselId)
    }

    func removeVesselDocument(vesselId: String, documentId: String) {
        guard let i = vessels.firstIndex(where: { $0.id == vesselId }) else { return }
        vessels[i].documents?.removeAll { $0.id == documentId }; saveVessels()
        autoPushVessel(vesselId: vesselId)
    }

    func renewVesselDocument(vesselId: String, oldDocId: String, newDoc: CrewDocument) {
        guard let vi = vessels.firstIndex(where: { $0.id == vesselId }) else { return }
        guard var docs = vessels[vi].documents, let di = docs.firstIndex(where: { $0.id == oldDocId }) else { return }
        docs[di].renewedAt = Date()
        var renewed = newDoc; renewed.previousVersionId = oldDocId
        docs.append(renewed); vessels[vi].documents = docs
        Haptics.light(); saveVessels()
        autoPushVessel(vesselId: vesselId)
    }

    struct VesselPortfolioItem: Identifiable {
        let id = UUID().uuidString
        let type: VesselDocType; var document: CrewDocument?; let required: Bool; let reason: String?
    }

    func vesselDocumentPortfolio(for vessel: Vessel) -> [VesselPortfolioItem] {
        let requirements = FlagStateRequirements.requiredVesselDocs(flag: vessel.flagState, vesselType: vessel.vesselType, grossTonnage: vessel.grossTonnageValue, lengthOverall: vessel.lengthOverallMetres, registeredLength: vessel.registeredLengthValue, yearBuilt: vessel.yearBuiltValue)
        let existing = (vessel.documents ?? []).filter { !$0.isArchived }
        let byType: [VesselDocType: CrewDocument] = {
            var map: [VesselDocType: CrewDocument] = [:]; for doc in existing { if let vdt = doc.vesselDocType, map[vdt] == nil { map[vdt] = doc } }; return map
        }()
        let requiredTypes = Set(requirements.map(\.type))
        var items: [VesselPortfolioItem] = requirements.map { VesselPortfolioItem(type: $0.type, document: byType[$0.type], required: $0.mandatory, reason: $0.reason) }
        for doc in existing { if let vdt = doc.vesselDocType, !requiredTypes.contains(vdt) { items.append(VesselPortfolioItem(type: vdt, document: doc, required: false, reason: nil)) } }
        return items
    }

    func vesselDocReadiness(for vessel: Vessel) -> (completed: Int, total: Int, expiring: Int, expired: Int) {
        let portfolio = vesselDocumentPortfolio(for: vessel)
        let required = portfolio.filter(\.required)
        return (required.filter { $0.document?.status == .valid }.count, required.count, required.filter { $0.document?.status == .expiringSoon }.count, required.filter { $0.document?.status == .expired }.count)
    }

    var expiringVesselDocuments: [(vessel: Vessel, document: CrewDocument)] {
        let cutoff = Calendar.current.date(byAdding: .day, value: 90, to: Date()) ?? Date()
        return vessels.flatMap { vessel in (vessel.documents ?? []).compactMap { doc in guard !doc.isArchived, let exp = doc.expiryDate, exp >= Date(), exp <= cutoff else { return nil }; return (vessel, doc) } }
    }

    var expiredVesselDocuments: [(vessel: Vessel, document: CrewDocument)] {
        vessels.flatMap { vessel in (vessel.documents ?? []).compactMap { doc in guard !doc.isArchived, let exp = doc.expiryDate, exp < Date() else { return nil }; return (vessel, doc) } }
    }

    // MARK: - CSV Import

    @discardableResult
    func importCrewCSV(rows: [CSVImporter.ParsedRow], vesselId: String?) -> [KYCCheck] {
        var created: [KYCCheck] = []
        for row in rows where row.isValid {
            let check = createCheck(customerName: row.name, entityType: row.entityType, vesselId: vesselId, crewRank: row.rank, companyName: row.companyName, jurisdiction: row.jurisdiction, ownershipPercent: row.ownershipPercent)
            if let i = checkIndex(check.id) {
                if let nat = row.nationality { checks[i].nationality = nat }
                if let dob = row.dateOfBirth { checks[i].dateOfBirth = dob }
                if let pn = row.passportNumber { checks[i].documentNumber = pn }
                if let pe = row.passportExpiry { checks[i].expiryDate = pe }
            }
            created.append(check)
        }
        saveChecks(); return created
    }

    // MARK: - Profile Photo

    func setProfilePhoto(checkId: String, imageData: Data) {
        guard let i = checkIndex(checkId) else { return }
        let filename = "\(checkId)_profile.jpg"
        try? imageData.write(to: imagesDir.appendingPathComponent(filename))
        invalidateImageCache(filename: filename)
        checks[i].profilePhoto = filename; saveChecks()
        queueFileForSync(filename: filename, vesselId: checks[i].vesselId)
        if let vid = checks[i].vesselId { autoPushVessel(vesselId: vid) }
        // Auto face-crop in background — replaces with cropped version if face found
        Task { await extractAndSetFacePhoto(checkId: checkId, imageData: imageData) }
    }

    // MARK: - vCard Generation

    func generateVCard(for check: KYCCheck) -> Data? {
        guard check.phoneNumber != nil || check.emailAddress != nil else { return nil }
        let name = check.displayName
        let parts = name.split(separator: " ", maxSplits: 1)
        let first = parts.first.map(String.init) ?? name
        let last = parts.count > 1 ? String(parts[1]) : ""

        var lines = [
            "BEGIN:VCARD",
            "VERSION:3.0",
            "FN:\(name)",
            "N:\(last);\(first);;;",
        ]
        if let phone = check.phoneNumber, !phone.isEmpty {
            lines.append("TEL;TYPE=CELL:\(phone)")
        }
        if let email = check.emailAddress, !email.isEmpty {
            lines.append("EMAIL;TYPE=WORK:\(email)")
        }
        if let nat = check.nationality { lines.append("NOTE:Nationality: \(nat)") }
        if let rank = check.crewRank { lines.append("TITLE:\(rank.rawValue)") }
        if let org = check.companyName { lines.append("ORG:\(org)") }
        if let ec = check.emergencyContact {
            lines.append("X-ICE-NAME:\(ec.name)")
            lines.append("X-ICE-PHONE:\(ec.phone)")
            lines.append("X-ICE-RELATION:\(ec.relationship)")
        }
        // Profile photo as base64 JPEG
        if let photo = check.profilePhoto, let data = loadDocumentImage(filename: photo) {
            let b64 = data.base64EncodedString()
            lines.append("PHOTO;ENCODING=b;TYPE=JPEG:\(b64)")
        }
        lines.append("END:VCARD")
        return lines.joined(separator: "\r\n").data(using: .utf8)
    }

    // MARK: - Create Check

    func createCheck(customerName: String, entityType: KYCCheck.EntityType = .seafarer, vesselId: String? = nil, crewRank: CrewRank? = nil, companyName: String? = nil, registrationNumber: String? = nil, jurisdiction: String? = nil, ownershipPercent: Double? = nil, docType: KYCCheck.IDDocType? = nil) -> KYCCheck {
        var check = KYCCheck(
            id: UUID().uuidString, customerId: "", customerName: customerName,
            agentId: "", agentName: AgentProfile.current?.fullName ?? "Agent",
            checkType: .idVerification, status: .pending, entityType: entityType,
            createdAt: Date(), latitude: nil, longitude: nil,
            expectedDocType: docType
        )
        check.vesselId = vesselId; check.crewRank = crewRank; check.companyName = companyName
        check.registrationNumber = registrationNumber; check.jurisdiction = jurisdiction; check.ownershipPercent = ownershipPercent

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

        checks.insert(check, at: 0); saveChecks()
        return check
    }

    // MARK: - Images

    func saveImages(checkId: String, front: Data, back: Data?) -> [String] {
        var paths: [String] = []
        let fp = imagesDir.appendingPathComponent("\(checkId)_front.jpg"); try? front.write(to: fp); paths.append(fp.lastPathComponent)
        if let b = back { let bp = imagesDir.appendingPathComponent("\(checkId)_back.jpg"); try? b.write(to: bp); paths.append(bp.lastPathComponent) }
        if let i = checkIndex(checkId) {
            checks[i].documentImagePaths = paths; saveChecks()
            // Auto-upload to workspace
            for p in paths { queueFileForSync(filename: p, vesselId: checks[i].vesselId) }
        }
        return paths
    }

    // MARK: - Reset

    func resetAll() {
        KeychainService.deleteAll()
        AgentProfile.delete()
        try? FileManager.default.removeItem(at: checksFile)
        try? FileManager.default.removeItem(at: vesselsFile)
        try? FileManager.default.removeItem(at: transferLogFile)
        try? FileManager.default.removeItem(at: imagesDir)
        try? FileManager.default.removeItem(at: reportsDir)
        checks = []; vessels = []; transferLog = []
    }

    // MARK: - Polling (internal)

    func startPollingPendingSessions() {
        for check in checks where check.sessionId != nil && check.status == .inProgress {
            guard let sid = check.sessionId else { continue }
            startPolling(checkId: check.id, sessionId: sid)
        }
    }

    func startPolling(checkId: String, sessionId: String) {
        guard pollTimers[checkId] == nil else { return }
        #if DEBUG
        vmLogger.debug("Starting poll for \(checkId.prefix(8))")
        #endif

        // Start Live Activity
        if let check = checks.first(where: { $0.id == checkId }) {
            let vesselName = check.vesselId.flatMap { vid in vessels.first { $0.id == vid }?.name } ?? ""
            VerificationActivityManager.startActivity(checkId: checkId, subjectName: check.customerName, vesselName: vesselName)
        }

        pollTimers[checkId] = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.pollOnce(checkId: checkId, sessionId: sessionId)
            }
        }
    }

    func stopPolling(checkId: String) {
        #if DEBUG
        vmLogger.debug("Stopping poll for \(checkId.prefix(8))")
        #endif
        pollTimers[checkId]?.invalidate()
        pollTimers.removeValue(forKey: checkId)
    }

    func pollOnce(checkId: String, sessionId: String) async {
        do {
            pollingError = nil
            let decision = try await pollSessionDecision(checkId: checkId, sessionId: sessionId)

            // Update Live Activity
            let s = decision.status.lowercased()
            let stage = s == "approved" || s == "completed" ? 3 : (decision.idVerifications?.isEmpty == false ? (decision.aml?.isEmpty == false ? 2 : 1) : 0)
            let statusText = stage == 0 ? "Waiting for subject" : stage == 1 ? "ID verified, screening..." : stage == 2 ? "AML complete" : "Verification complete"
            if let check = checks.first(where: { $0.id == checkId }) {
                let elapsed = Int(Date().timeIntervalSince(check.createdAt) / 60)
                VerificationActivityManager.updateActivity(checkId: checkId, status: statusText, stage: stage, elapsedMinutes: elapsed)
            }

            if isTerminalStatus(decision.status) {
                stopPolling(checkId: checkId)
                let final = s == "approved" || s == "completed" ? "Verified" : "Failed"
                VerificationActivityManager.endActivity(checkId: checkId, finalStatus: final)
                _ = generateReport(checkId: checkId)
            }
        } catch {
            pollingError = "Verification check failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Internal Helpers

    func checkIndex(_ id: String) -> Int? { checks.firstIndex(where: { $0.id == id }) }

    func isTerminalStatus(_ status: String) -> Bool {
        ["approved", "declined", "completed", "rejected", "failed", "expired"].contains(status.lowercased())
    }

    func isExpired(_ s: String?) -> Bool {
        guard let s else { return false }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s).map { $0 < Date() } ?? false
    }

    func autoCreatePassportDoc(checkIndex i: Int, idResult: IDResult?) {
        guard let id = idResult else { return }
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        var docs = checks[i].documents ?? []
        if let pi = docs.firstIndex(where: { $0.type == .passport && $0.imagePaths.isEmpty }) {
            docs[pi].documentNumber = id.documentNumber
            docs[pi].expiryDate = id.expiryDate.flatMap { fmt.date(from: $0) }
            docs[pi].issuingAuthority = id.issuingCountry
            docs[pi].imagePaths = checks[i].documentImagePaths ?? []
        } else if !docs.contains(where: { $0.type == .passport }) {
            docs.append(CrewDocument(type: .passport, imagePaths: checks[i].documentImagePaths ?? [],
                documentNumber: id.documentNumber, expiryDate: id.expiryDate.flatMap { fmt.date(from: $0) }, issuingAuthority: id.issuingCountry))
        }
        checks[i].documents = docs

        // Auto-crop face from ID photo for profile picture (runs in background)
        // Only set profile photo from a successful face crop — never use the full passport scan
        if checks[i].profilePhoto == nil, let firstPath = checks[i].documentImagePaths?.first {
            let checkId = checks[i].id
            if let imageData = loadDocumentImage(filename: firstPath) {
                Task {
                    await extractAndSetFacePhoto(checkId: checkId, imageData: imageData)
                }
            }
        }
    }

    /// Uses Claude to detect the face region in an ID document and crops it for the profile photo
    func extractAndSetFacePhoto(checkId: String, imageData: Data) async {
        do {
            let bounds = try await ClaudeService.shared.detectFaceBounds(imageData: imageData)
            guard bounds.found,
                  let bx = bounds.x, let by = bounds.y,
                  let bw = bounds.width, let bh = bounds.height,
                  bw > 0.05, bh > 0.05,
                  let uiImage = UIImage(data: imageData),
                  let cgImage = uiImage.cgImage else { return }

            let imgW = CGFloat(cgImage.width)
            let imgH = CGFloat(cgImage.height)
            let cropRect = CGRect(
                x: max(0, bx * Double(imgW)),
                y: max(0, by * Double(imgH)),
                width: min(bw * Double(imgW), Double(imgW)),
                height: min(bh * Double(imgH), Double(imgH))
            )

            guard let cropped = cgImage.cropping(to: cropRect) else { return }
            let croppedImage = UIImage(cgImage: cropped)
            guard let jpegData = croppedImage.jpegData(compressionQuality: 0.85) else { return }

            let filename = "\(checkId)_face.jpg"
            try? jpegData.write(to: imagesDir.appendingPathComponent(filename))

            guard let i = checkIndex(checkId) else { return }
            checks[i].profilePhoto = filename
            saveChecks()
            queueFileForSync(filename: filename, vesselId: checks[i].vesselId)
        } catch {
            // Face detection failed — keep the full passport photo as fallback
        }
    }

    func toISO2(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if trimmed.count == 2, Locale.Region.isoRegions.contains(where: { $0.identifier == trimmed }) { return trimmed }
        if trimmed.count == 3, let found = alpha3Map[trimmed] { return found }
        let lower = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for region in Locale.Region.isoRegions {
            let name = Locale(identifier: "en").localizedString(forRegionCode: region.identifier)?.lowercased() ?? ""
            if name == lower || lower.contains(name) || name.contains(lower) { return region.identifier }
        }
        if trimmed.count == 2 { return trimmed }
        return nil
    }

    func nameMismatch(entered: String, extracted: String) -> (String, String)? {
        guard !extracted.isEmpty else { return nil }
        let e = Set(entered.lowercased().split(separator: " ").map(String.init))
        let x = Set(extracted.lowercased().split(separator: " ").map(String.init))
        return Double(e.intersection(x).count) / Double(max(e.count, x.count, 1)) < 0.5 ? (entered, extracted) : nil
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
}
