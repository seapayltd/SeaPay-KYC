//
//  Accessibility.swift
//  OceanCheck
//
//  Accessibility helpers and modifiers for VoiceOver support.
//  Core labels are inline in views; this file provides reusable helpers.
//

import SwiftUI

// MARK: - Accessible Status Description

extension KYCCheck.CheckStatus {
    var accessibilityDescription: String {
        switch self {
        case .passed: return "Verification passed"
        case .failed: return "Verification failed"
        case .requiresReview: return "Requires review"
        case .pending: return "Pending verification"
        case .inProgress: return "Verification in progress"
        case .incomplete: return "Incomplete"
        }
    }
}

extension KYCCheck {
    /// Full accessibility description for a check card
    var accessibilityDescription: String {
        var parts = [displayName, entityType.rawValue, status.accessibilityDescription]
        if let rank = crewRank { parts.insert(rank.rawValue, at: 1) }
        if let exp = expiryDate { parts.append("expires \(exp)") }
        return parts.joined(separator: ", ")
    }
}

extension Vessel {
    /// Full accessibility description for a vessel card
    func accessibilityDescription(crewCount: Int, passedCount: Int) -> String {
        var parts = [name]
        if let vt = vesselType { parts.append(vt.rawValue) }
        if !flagState.isEmpty { parts.append(flagState) }
        parts.append("\(crewCount) crew, \(passedCount) verified")
        return parts.joined(separator: ", ")
    }
}

// MARK: - Accessible Document Status

extension CrewDocument {
    var accessibilityDescription: String {
        var parts = [type.displayName]
        parts.append(statusLabel)
        if let exp = expiryDate {
            let fmt = DateFormatter(); fmt.dateStyle = .medium
            parts.append("expires \(fmt.string(from: exp))")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - View Modifiers for Common Patterns

struct AccessibleCard: ViewModifier {
    let label: String
    let hint: String?

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .combine)
            .accessibilityLabel(label)
            .accessibilityHint(hint ?? "")
    }
}

extension View {
    func accessibleCard(_ label: String, hint: String? = nil) -> some View {
        modifier(AccessibleCard(label: label, hint: hint))
    }
}

// MARK: - App Badge

enum AppBadge {
    /// Update the app icon badge with the count of expired + expiring documents
    @MainActor
    static func update(checks: [KYCCheck], vessels: [Vessel]) {
        let dateFmt = DateFormatter(); dateFmt.dateFormat = "yyyy-MM-dd"
        let now = Date()
        var urgent = 0

        // Expired IDs
        for check in checks {
            if let s = check.expiryDate, let d = dateFmt.date(from: s), d < now { urgent += 1 }
        }
        // Expired crew docs
        for check in checks {
            for doc in check.documents ?? [] where !doc.isArchived {
                if let d = doc.expiryDate, d < now { urgent += 1 }
            }
        }
        // Expired vessel certs
        for vessel in vessels {
            for doc in vessel.documents ?? [] where !doc.isArchived {
                if let d = doc.expiryDate, d < now { urgent += 1 }
            }
        }

        UNUserNotificationCenter.current().setBadgeCount(urgent)
    }
}

// MARK: - Data Migration

enum DataMigration {
    private static let currentVersion = 2
    private static let versionKey = "dataMigrationVersion"

    static func runIfNeeded() {
        let stored = UserDefaults.standard.integer(forKey: versionKey)
        guard stored < currentVersion else { return }

        // v0 → v1: AgentProfile migration (already handled by AgentProfile.migrateIfNeeded)
        // v1 → v2: Encryption migration (already handled by EncryptionService.migrateIfNeeded)

        // Mark current version
        UserDefaults.standard.set(currentVersion, forKey: versionKey)
    }

    /// Version for export metadata
    static var versionString: String { "v\(currentVersion)" }
}
