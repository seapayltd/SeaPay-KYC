//
//  AppIntents.swift
//  OceanCheck
//
//  Siri Shortcuts for common compliance actions.
//

import AppIntents

// MARK: - Open App

struct OpenOceanCheckIntent: AppIntent {
    static var title: LocalizedStringResource = "Open OceanCheck"
    static var description = IntentDescription("Open the OceanCheck maritime compliance app")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        return .result()
    }
}

// MARK: - Check Expiring Docs

struct CheckExpiringDocsIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Expiring Documents"
    static var description = IntentDescription("See how many maritime documents are expiring soon")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let vm = await KYCViewModel()
        let expiring = await vm.expiringChecks.count + vm.allExpiringDocuments.count
        let expired = await vm.expiredChecks.count + vm.allExpiredDocuments.count

        if expired > 0 {
            return .result(dialog: "\(expired) documents expired, \(expiring) expiring soon.")
        } else if expiring > 0 {
            return .result(dialog: "\(expiring) documents expiring within 90 days.")
        } else {
            return .result(dialog: "All documents are current. No expiring certificates.")
        }
    }
}

// MARK: - Crew Count

struct CrewCountIntent: AppIntent {
    static var title: LocalizedStringResource = "How Many Crew"
    static var description = IntentDescription("Get the total number of crew members across all vessels")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let vm = await KYCViewModel()
        await vm.loadIfNeeded()
        try? await Task.sleep(nanoseconds: 500_000_000)
        let total = await vm.checks.count
        let vessels = await vm.vessels.count
        let passed = await vm.checks.filter { $0.status == .passed }.count

        if total == 0 {
            return .result(dialog: "No crew members registered yet.")
        }
        return .result(dialog: "\(total) crew across \(vessels) vessel\(vessels == 1 ? "" : "s"). \(passed) verified.")
    }
}

// MARK: - Vessel Summary

struct VesselSummaryIntent: AppIntent {
    static var title: LocalizedStringResource = "Vessel Summary"
    static var description = IntentDescription("Get a quick summary of your vessels and their compliance status")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let vm = await KYCViewModel()
        await vm.loadIfNeeded()
        try? await Task.sleep(nanoseconds: 500_000_000)
        let vessels = await vm.vessels

        if vessels.isEmpty {
            return .result(dialog: "No vessels registered yet.")
        }

        let names = vessels.prefix(3).map(\.name).joined(separator: ", ")
        let more = vessels.count > 3 ? " and \(vessels.count - 3) more" : ""
        return .result(dialog: "\(vessels.count) vessel\(vessels.count == 1 ? "" : "s"): \(names)\(more).")
    }
}

// MARK: - Start Verification

struct StartVerificationIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Crew Verification"
    static var description = IntentDescription("Open OceanCheck to begin a new crew verification")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        return .result()
    }
}

// MARK: - Shortcuts Provider

struct OceanCheckShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenOceanCheckIntent(), phrases: [
            "Open \(.applicationName)",
            "Launch \(.applicationName)"
        ], shortTitle: "Open OceanCheck", systemImageName: "checkmark.shield")

        AppShortcut(intent: CheckExpiringDocsIntent(), phrases: [
            "Check expiring documents in \(.applicationName)",
            "Any expiring certificates in \(.applicationName)"
        ], shortTitle: "Expiring Documents", systemImageName: "exclamationmark.triangle")

        AppShortcut(intent: CrewCountIntent(), phrases: [
            "How many crew in \(.applicationName)",
            "Crew count in \(.applicationName)"
        ], shortTitle: "Crew Count", systemImageName: "person.3")

        AppShortcut(intent: VesselSummaryIntent(), phrases: [
            "Vessel summary in \(.applicationName)",
            "Show my vessels in \(.applicationName)"
        ], shortTitle: "Vessel Summary", systemImageName: "ferry")

        AppShortcut(intent: StartVerificationIntent(), phrases: [
            "Start verification in \(.applicationName)",
            "Verify crew in \(.applicationName)"
        ], shortTitle: "Start Verification", systemImageName: "person.badge.shield.checkmark")
    }
}
