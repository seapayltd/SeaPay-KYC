//
//  AppConfiguration.swift
//  SeaPay KYC
//

import Foundation

enum AppConfiguration: Sendable {
    enum Environment: Sendable { case development, production }

    #if DEBUG
    nonisolated static let environment: Environment = .development
    #else
    nonisolated static let environment: Environment = .production
    #endif

    // MARK: - API

    nonisolated static let verificationBaseURL = "https://verification.didit.me/v3"

    nonisolated static var apiKey: String {
        if let stored = KeychainService.get(.diditAPIKey), !stored.isEmpty { return stored }
        return plistValue(for: "KYC_API_KEY") ?? ""
    }

    nonisolated static var workflowID: String {
        KeychainService.get(.workflowID) ?? ""
    }

    nonisolated static var isAgentConfigured: Bool { !apiKey.isEmpty }
    nonisolated static var hasWorkflow: Bool { !workflowID.isEmpty }

    // MARK: - Deep Links

    nonisolated static let urlScheme = "oceancheck"

    // MARK: - Limits

    nonisolated static let maxImageSizeMB = 5
    nonisolated static let maxImageSizeBytes = maxImageSizeMB * 1024 * 1024
    nonisolated static let minImageWidth = 640
    nonisolated static let minImageHeight = 480

    // MARK: - Feature Flags

    nonisolated static let enableBiometricAuth = true

    // MARK: - Helpers

    nonisolated static var isConfigured: Bool {
        !apiKey.isEmpty || UserDefaults.standard.bool(forKey: "isCollaborator")
    }

    nonisolated private static func plistValue(for key: String) -> String? {
        Bundle.main.infoDictionary?[key] as? String
    }
}
