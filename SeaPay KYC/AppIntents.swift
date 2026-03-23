//
//  AppIntents.swift
//  OceanCheck
//
//  Siri Shortcuts for common compliance actions.
//

import AppIntents

struct OpenOceanCheckIntent: AppIntent {
    static var title: LocalizedStringResource = "Open OceanCheck"
    static var description = IntentDescription("Open the OceanCheck maritime compliance app")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        return .result()
    }
}

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
    }
}
