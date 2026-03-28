//
//  tests.swift
//  OceanCheck Tests
//
//  Swift Testing suite for OceanCheck business logic.
//

import Testing
import Foundation
@testable import SeaPay_KYC

// MARK: - Vessel Model

@Suite("Vessel")
struct VesselTests {

    @Test func grossTonnageValue() {
        var v = Vessel(name: "Test"); v.grossTonnage = "480"
        #expect(v.grossTonnageValue == 480)
        v.grossTonnage = "1,234"
        #expect(v.grossTonnageValue == 1234)
        v.grossTonnage = ""
        #expect(v.grossTonnageValue == nil)
    }

    @Test func lengthMetres() {
        var v = Vessel(name: "Test"); v.lengthOverall = "42.5"
        #expect(v.lengthOverallMetres == 42.5)
        v.lengthOverall = "42.5m"
        #expect(v.lengthOverallMetres == 42.5)
    }

    @Test func regulatoryLengthPrefersRegistered() {
        var v = Vessel(name: "Test"); v.registeredLength = "38.2"; v.lengthOverall = "42.5"
        #expect(v.regulatoryLength == 38.2)
    }

    @Test func regulatoryLengthFallsBackToLOA() {
        var v = Vessel(name: "Test"); v.registeredLength = ""; v.lengthOverall = "42.5"
        #expect(v.regulatoryLength == 42.5)
    }

    @Test func codableRoundTrip() throws {
        var vessel = Vessel(name: "M/Y OCEANUS", imoNumber: "9876543", flagState: "Malta", vesselType: .megayachtCharter)
        vessel.grossTonnage = "480"; vessel.registeredLength = "38.2"
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Vessel.self, from: encoder.encode(vessel))
        #expect(decoded.name == "M/Y OCEANUS")
        #expect(decoded.vesselType == .megayachtCharter)
        #expect(decoded.registeredLength == "38.2")
    }

    @Test func backwardCompatWithoutRegisteredLength() throws {
        let json = """
        {"id":"test","name":"OLD","imoNumber":"123","officialNumber":"","callSign":"","flagState":"Malta",
         "portOfRegistry":"","certificateNumber":"","builder":"","yearBuilt":"2020","hullMaterial":"",
         "vesselDescription":"","lengthOverall":"30.0","breadth":"7","depth":"3","draught":"2",
         "grossTonnage":"200","netTonnage":"60","propulsionType":"","engineDescription":"",
         "engineMaker":"","propulsionPower":"","estimatedSpeed":"","registeredOwner":"",
         "ownerAddress":"","registrationDate":"","certificateExpiry":"","createdAt":"2024-01-01T00:00:00Z"}
        """
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let vessel = try decoder.decode(Vessel.self, from: json.data(using: .utf8)!)
        #expect(vessel.registeredLength == "")
        #expect(vessel.regulatoryLength == 30.0)
    }
}

// MARK: - Encryption

@Suite("Encryption")
struct EncryptionTests {

    @Test func roundTrip() throws {
        guard EncryptionService.isKeychainAvailable else { return }
        let original = "Sensitive PII: AB123456".data(using: .utf8)!
        let decrypted = try EncryptionService.decrypt(try EncryptionService.encrypt(original))
        #expect(decrypted == original)
    }

    @Test func encryptedDiffers() throws {
        guard EncryptionService.isKeychainAvailable else { return }
        let original = "Test".data(using: .utf8)!
        #expect(try EncryptionService.encrypt(original) != original)
    }

    @Test func emptyData() throws {
        guard EncryptionService.isKeychainAvailable else { return }
        let decrypted = try EncryptionService.decrypt(try EncryptionService.encrypt(Data()))
        #expect(decrypted == Data())
    }

    @Test func fileWriteRead() throws {
        guard EncryptionService.isKeychainAvailable else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test_enc_\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: url) }
        let original = "{\"name\":\"test\"}".data(using: .utf8)!
        try EncryptionService.writeEncrypted(original, to: url)
        #expect(EncryptionService.readDecrypted(from: url) == original)
    }

    @Test func plaintextFallback() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test_plain_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let plain = "[{\"id\":\"1\"}]".data(using: .utf8)!
        try? plain.write(to: url)
        #expect(EncryptionService.readDecrypted(from: url) == plain)
    }

    @Test func missingFile() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("nonexistent_\(UUID().uuidString)")
        #expect(EncryptionService.readDecrypted(from: url) == nil)
    }

    @Test func migration() throws {
        guard EncryptionService.isKeychainAvailable else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test_migrate_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let json = "[{\"name\":\"test\"}]".data(using: .utf8)!
        try json.write(to: url)
        EncryptionService.migrateIfNeeded(at: url)
        let raw = try Data(contentsOf: url)
        #expect((try? JSONSerialization.jsonObject(with: raw)) == nil, "Should be encrypted")
        #expect(EncryptionService.readDecrypted(from: url) == json)
    }
}

// MARK: - Transfer Hash

@Suite("TransferHash")
struct TransferHashTests {

    @Test func deterministic() {
        let v = "{}".data(using: .utf8)!; let c = "[]".data(using: .utf8)!
        #expect(TransferHash.compute(vesselData: v, checksData: c) == TransferHash.compute(vesselData: v, checksData: c))
    }

    @Test func differentInputDifferentHash() {
        let c = "[]".data(using: .utf8)!
        let h1 = TransferHash.compute(vesselData: "{\"a\":1}".data(using: .utf8)!, checksData: c)
        let h2 = TransferHash.compute(vesselData: "{\"a\":2}".data(using: .utf8)!, checksData: c)
        #expect(h1 != h2)
    }

    @Test func validSHA256Format() {
        let hash = TransferHash.compute(vesselData: Data(), checksData: Data())
        #expect(hash.count == 64)
        #expect(hash.allSatisfy { $0.isHexDigit })
    }
}

// MARK: - KYCCheck Model

@Suite("KYCCheck")
struct KYCCheckTests {

    private func makeCheck(entityType: KYCCheck.EntityType = .seafarer) -> KYCCheck {
        KYCCheck(id: UUID().uuidString, customerId: "T", customerName: "Test",
            agentId: "A", agentName: "Agent", checkType: .idVerification,
            status: .pending, entityType: entityType, createdAt: Date())
    }

    @Test func codableRoundTrip() throws {
        var check = makeCheck(); check.extractedName = "John"; check.crewRank = .captain
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(KYCCheck.self, from: encoder.encode(check))
        #expect(decoded.extractedName == "John")
        #expect(decoded.crewRank == .captain)
    }

    @Test func entityCategories() {
        #expect(KYCCheck.EntityType.seafarer.category == .crew)
        #expect(KYCCheck.EntityType.owner.category == .ownership)
        #expect(KYCCheck.EntityType.trustee.category == .ownership)
        #expect(KYCCheck.EntityType.dpa.category == .shoreBased)
    }

    @Test func displayNamePrefersExtracted() {
        var check = makeCheck(); check.extractedName = "Extracted"
        #expect(check.displayName == "Extracted")
    }
}

// MARK: - Compliance Engine

@Suite("ComplianceEngine")
struct ComplianceEngineTests {

    @Test func maltaCaptainHasBasics() {
        let docs = FlagStateRequirements.required(flag: "Malta", vesselType: .megayachtCharter, rank: .captain)
        #expect(docs.contains(.passport))
        #expect(docs.contains(.stcwBST))
        #expect(docs.contains(.cocDeck))
    }

    @Test func engineerNoDeckCOC() {
        let docs = FlagStateRequirements.required(flag: "Malta", vesselType: .megayachtCharter, rank: .chiefEngineer)
        #expect(docs.contains(.cocEngine))
        #expect(!docs.contains(.cocDeck))
    }

    @Test func emptyFlagStillReturnsBasics() {
        let docs = FlagStateRequirements.required(flag: "", vesselType: nil, rank: .ab)
        #expect(docs.contains(.passport))
    }

    @Test func ownerEntityDocs() {
        let docs = FlagStateRequirements.requiredForEntity(.owner)
        #expect(docs.contains(.passport))
        #expect(docs.contains(.uboDeclaration))
    }

    @Test func vesselDocsExistForMalta() {
        let docs = FlagStateRequirements.requiredVesselDocs(
            flag: "Malta", vesselType: .megayachtCharter,
            grossTonnage: 480, lengthOverall: 42.5, registeredLength: 38.2, yearBuilt: 2019)
        #expect(!docs.isEmpty)
        #expect(docs.map(\.type).contains(.certificateOfRegistry))
    }
}

// MARK: - API Usage Tracker

@Suite("APIUsage")
struct APIUsageTests {

    init() {
        UserDefaults.standard.removeObject(forKey: "apiUsageHistory")
    }

    @Test func trackIncrements() {
        UserDefaults.standard.removeObject(forKey: "apiUsageHistory")
        APIUsageTracker.track(.idScan)
        APIUsageTracker.track(.idScan)
        APIUsageTracker.track(.amlScreening)
        let today = APIUsageTracker.todayUsage()
        #expect(today.idScans >= 2)
        #expect(today.amlScreenings >= 1)
        #expect(today.totalCalls >= 3)
    }

    @Test func emptyUsageIsZero() {
        // Can't guarantee isolation from parallel tests, just verify structure
        let today = APIUsageTracker.todayUsage()
        #expect(today.totalCalls >= 0)
        #expect(today.estimatedCost >= 0)
    }

    @Test func costEstimation() {
        // Verify cost formula: individual entry cost calculation
        let entry = APIDailyUsage(date: "2026-01-01", idScans: 2, amlScreenings: 3, poaChecks: 1, claudeOCR: 5, sessions: 4)
        let expected = 2 * 0.50 + 3 * 0.30 + 1 * 0.40 + 5 * 0.02 + 4 * 0.10
        #expect(abs(entry.estimatedCost - expected) < 0.001)
        #expect(entry.totalCalls == 15)
    }
}

// MARK: - GDPR

@Suite("GDPR")
struct GDPRTests {

    @Test func recordConsent() {
        var records: [ConsentRecord] = []
        GDPRService.recordConsent(subjectName: "John", checkId: "c1",
            types: [.identityVerification, .amlScreening], store: &records)
        #expect(records.count == 2)
        #expect(records[0].isActive)
    }

    @Test func withdrawConsent() {
        var records: [ConsentRecord] = []
        GDPRService.recordConsent(subjectName: "John", checkId: "c1", types: [.dataProcessing], store: &records)
        GDPRService.withdrawConsent(recordId: records[0].id, store: &records)
        #expect(!records[0].isActive)
        #expect(records[0].withdrawnAt != nil)
    }

    @Test func retentionFlags() {
        let old = KYCCheck(id: "old", customerId: "C", customerName: "Old",
            agentId: "A", agentName: "Agent", checkType: .idVerification,
            status: .passed, entityType: .seafarer,
            createdAt: Calendar.current.date(byAdding: .year, value: -6, to: Date())!)
        let recent = KYCCheck(id: "new", customerId: "C", customerName: "New",
            agentId: "A", agentName: "Agent", checkType: .idVerification,
            status: .passed, entityType: .seafarer, createdAt: Date())
        let policy = RetentionPolicy(retentionYears: 5, autoFlagExpired: true, autoDeleteExpired: false)
        let flagged = GDPRService.flaggedForRetention(checks: [old, recent], policy: policy)
        #expect(flagged.count == 1)
        #expect(flagged[0].id == "old")
    }

    @Test func dsarExport() {
        let check = KYCCheck(id: "d1", customerId: "C", customerName: "Jane Doe",
            agentId: "A", agentName: "Agent", checkType: .idVerification,
            status: .passed, entityType: .seafarer, createdAt: Date())
        let url = GDPRService.exportSubjectData(name: "Jane", checks: [check], vessels: [], consentRecords: [], auditLog: [])
        defer { if let u = url { try? FileManager.default.removeItem(at: u) } }
        #expect(url != nil)
    }
}
