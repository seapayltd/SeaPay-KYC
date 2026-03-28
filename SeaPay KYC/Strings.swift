//
//  Strings.swift
//  OceanCheck
//
//  Centralized user-facing strings for localization.
//  SwiftUI Text() views auto-lookup from Localizable.xcstrings.
//  This file provides String constants for non-SwiftUI contexts
//  (alerts, reports, API messages) using String(localized:).
//

import Foundation

enum L10n {

    // MARK: - App

    enum App {
        static let name = String(localized: "OceanCheck")
        static let tagline = String(localized: "Maritime Compliance")
        static let locked = String(localized: "OceanCheck Locked")
        static let unlockPrompt = String(localized: "Authenticate to access compliance data")
    }

    // MARK: - Tabs & Navigation

    enum Nav {
        static let vessels = String(localized: "Vessels")
        static let people = String(localized: "People")
        static let settings = String(localized: "Settings")
        static let search = String(localized: "Search crew or vessels")
    }

    // MARK: - Status

    enum Status {
        static let clear = String(localized: "Clear")
        static let flagged = String(localized: "Flagged")
        static let review = String(localized: "Review")
        static let pending = String(localized: "Pending")
        static let active = String(localized: "Active")
        static let draft = String(localized: "Draft")
        static let valid = String(localized: "Valid")
        static let expiring = String(localized: "Expiring")
        static let expired = String(localized: "Expired")
        static let missing = String(localized: "Missing")
        static let offline = String(localized: "Offline")
    }

    // MARK: - Actions

    enum Action {
        static let addVessel = String(localized: "Add Vessel")
        static let addCrew = String(localized: "Add Crew")
        static let batchInvite = String(localized: "Batch Invite")
        static let importCSV = String(localized: "Import Crew CSV")
        static let exportCSV = String(localized: "Export CSV")
        static let exportXLSX = String(localized: "Export XLSX")
        static let exportBackup = String(localized: "Export Backup")
        static let importBackup = String(localized: "Import Backup")
        static let beginVerification = String(localized: "Begin Verification")
        static let cancel = String(localized: "Cancel")
        static let done = String(localized: "Done")
        static let delete = String(localized: "Delete")
        static let save = String(localized: "Save")
        static let next = String(localized: "Next")
        static let skip = String(localized: "Skip")
        static let getStarted = String(localized: "Get Started")
        static let approve = String(localized: "Approve")
        static let decline = String(localized: "Decline")
        static let flag = String(localized: "Flag for Review")
        static let resetAll = String(localized: "Reset All Data")
    }

    // MARK: - Verification

    enum Verify {
        static let idVerification = String(localized: "Identity Verification")
        static let amlScreening = String(localized: "AML/Sanctions Screening")
        static let proofOfAddress = String(localized: "Proof of Address")
        static let importComplete = String(localized: "Import Complete")
        static let importFailed = String(localized: "Import Failed")
        static let consentPrompt = String(localized: "I consent to identity verification")
    }

    // MARK: - Settings Sections

    enum Settings {
        static let identity = String(localized: "Identity")
        static let connections = String(localized: "Connections")
        static let appearance = String(localized: "Appearance")
        static let data = String(localized: "Data")
        static let privacy = String(localized: "Privacy & Compliance")
        static let apiUsage = String(localized: "API Usage")
        static let transferHistory = String(localized: "Transfer History")
        static let dataRetention = String(localized: "Data Retention")
        static let subjectDataRequest = String(localized: "Subject Data Request")
        static let auditLog = String(localized: "Audit Log")
        static let demoMode = String(localized: "Demo Mode")
    }

    // MARK: - Onboarding

    enum Onboarding {
        static let page1Title = String(localized: "Maritime Compliance\nin Your Pocket")
        static let page1Sub = String(localized: "OceanCheck helps you verify crew, track documents, and manage vessel compliance — all from your iPhone.")
        static let page2Title = String(localized: "Verify Anyone\nin the Chain")
        static let page2Sub = String(localized: "From seafarers to beneficial owners, OceanCheck covers every entity in the maritime compliance chain.")
        static let page3Title = String(localized: "What You'll Need")
        static let page3Sub = String(localized: "OceanCheck connects to verification services that require API credentials.")
    }

    // MARK: - Roles

    enum Role {
        static let agent = String(localized: "Agent")
        static let subject = String(localized: "Crew / Subject")
        static let owner = String(localized: "Vessel Owner")
    }

    // MARK: - Biometric

    enum Biometric {
        static func unlockWith(_ name: String) -> String {
            String(localized: "Unlock with \(name)")
        }
        static func lockWith(_ name: String) -> String {
            String(localized: "Lock with \(name)")
        }
    }

    // MARK: - Expiry

    enum Expiry {
        static func expiredCount(_ n: Int) -> String {
            String(localized: "\(n) expired")
        }
        static func expiringCount(_ n: Int) -> String {
            String(localized: "\(n) expiring soon")
        }
        static let allClear = String(localized: "All documents current")
    }

    // MARK: - Widget

    enum Widget {
        static let title = String(localized: "Expiry Status")
        static let description = String(localized: "Document and certificate expiry at a glance.")
    }

    // MARK: - Reports

    enum Report {
        static let complianceReport = String(localized: "VESSEL COMPLIANCE SUMMARY")
        static let uboReport = String(localized: "UBO COMPLIANCE REPORT")
        static let crewList = String(localized: "CREW LIST")
        static let confidential = String(localized: "CONFIDENTIAL")
        static let generated = String(localized: "Generated by OceanCheck")
    }

    // MARK: - Empty States

    enum Empty {
        static let noVessels = String(localized: "No vessels yet")
        static let noCrew = String(localized: "No crew members registered yet")
        static let noAuditEvents = String(localized: "No audit events yet")
    }
}
