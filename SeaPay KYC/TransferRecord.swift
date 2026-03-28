//
//  TransferRecord.swift
//  OceanCheck
//
//  Transfer audit log — tracks every .oceancheck package sent or received.
//  Enables traceability, rollback, and re-export.
//

import Foundation
import CryptoKit

// MARK: - Transfer Direction

enum TransferDirection: String, Codable {
    case sent, received
}

// MARK: - Transfer Record

struct TransferRecord: Codable, Identifiable {
    let id: String
    let direction: TransferDirection
    let scenario: String
    let vesselName: String
    let vesselIMO: String
    let checksCount: Int

    // Sender
    let senderAgentName: String
    let senderAgentId: String
    let senderOrganization: String

    // Receiver (populated on import)
    let receiverAgentName: String?
    let receiverAgentId: String?

    let timestamp: Date
    let contentHash: String?        // SHA256 of vessel.json + checks.json
    let manifestJSON: String?       // Full manifest for audit trail

    // Rollback support (only for received)
    let importedVesselId: String?
    let importedCheckIds: [String]?
    let wasVesselUpdate: Bool

    init(
        direction: TransferDirection,
        scenario: String,
        vesselName: String,
        vesselIMO: String,
        checksCount: Int,
        senderAgentName: String,
        senderAgentId: String,
        senderOrganization: String,
        receiverAgentName: String? = nil,
        receiverAgentId: String? = nil,
        contentHash: String? = nil,
        manifestJSON: String? = nil,
        importedVesselId: String? = nil,
        importedCheckIds: [String]? = nil,
        wasVesselUpdate: Bool = false
    ) {
        self.id = UUID().uuidString
        self.direction = direction
        self.scenario = scenario
        self.vesselName = vesselName
        self.vesselIMO = vesselIMO
        self.checksCount = checksCount
        self.senderAgentName = senderAgentName
        self.senderAgentId = senderAgentId
        self.senderOrganization = senderOrganization
        self.receiverAgentName = receiverAgentName
        self.receiverAgentId = receiverAgentId
        self.timestamp = Date()
        self.contentHash = contentHash
        self.manifestJSON = manifestJSON
        self.importedVesselId = importedVesselId
        self.importedCheckIds = importedCheckIds
        self.wasVesselUpdate = wasVesselUpdate
    }
}

// MARK: - Transfer Import Result

struct TransferImportResult {
    let success: Bool
    let vesselId: String?
    let vesselName: String?
    let importedCheckIds: [String]
    let wasUpdate: Bool
    let error: String?
}

// MARK: - Transfer Package Preview

struct TransferPackagePreview {
    let senderName: String
    let senderOrg: String
    let senderAgentId: String
    let scenario: String
    let vesselName: String
    let vesselIMO: String
    let checksCount: Int
    let hasImages: Bool
    let hasOwnership: Bool
    let generatedAt: String
    let formatVersion: String
    let contentHash: String?
    let existsLocally: Bool
    let vesselType: String?
}

// MARK: - Content Hash Helper

enum TransferHash {
    static func compute(vesselData: Data, checksData: Data) -> String {
        let combined = vesselData + checksData
        let digest = SHA256.hash(data: combined)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
