//
//  ServiceProtocols.swift
//  OceanCheck
//
//  Protocol abstractions for external services.
//  Enables dependency injection, testability, and mock implementations.
//

import Foundation

// MARK: - Notification Service Protocol

protocol NotificationServiceProtocol {
    func requestPermission()
    func rescheduleAll(checks: [KYCCheck], vessels: [Vessel])
}

extension NotificationService: NotificationServiceProtocol {}

// MARK: - Cloud Backup Protocol

protocol CloudBackupProtocol {
    func backup(checksFile: URL, vesselsFile: URL, imagesDir: URL)
}

extension CloudBackupService: CloudBackupProtocol {}

// MARK: - Service Container

/// Centralized access to all services. Use `ServiceContainer.shared` as default,
/// or inject a custom container for testing/demo mode.
@MainActor
final class ServiceContainer {
    static let shared = ServiceContainer()

    let api: VerificationAPIService
    let claude: ClaudeService
    let notifications: NotificationServiceProtocol
    let cloudBackup: CloudBackupProtocol

    init(
        api: VerificationAPIService? = nil,
        claude: ClaudeService? = nil,
        notifications: NotificationServiceProtocol? = nil,
        cloudBackup: CloudBackupProtocol? = nil
    ) {
        self.api = api ?? VerificationAPIService.shared
        self.claude = claude ?? ClaudeService.shared
        self.notifications = notifications ?? NotificationService.shared
        self.cloudBackup = cloudBackup ?? CloudBackupService.shared
    }

    /// Create a container with mock notification/backup services (for testing)
    static func forTesting(
        notifications: NotificationServiceProtocol,
        cloudBackup: CloudBackupProtocol
    ) -> ServiceContainer {
        ServiceContainer(notifications: notifications, cloudBackup: cloudBackup)
    }
}
