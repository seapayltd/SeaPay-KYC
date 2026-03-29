//
//  MockServices.swift
//  SeaPay KYCTests
//
//  Mock service implementations for unit testing.
//  Used with ServiceContainer.forTesting() to inject into KYCViewModel.
//

import Foundation
@testable import SeaPay_KYC

// MARK: - Mock Notifications

class MockNotificationService: NotificationServiceProtocol {
    var rescheduleCount = 0
    var permissionRequested = false

    func requestPermission() { permissionRequested = true }

    func rescheduleAll(checks: [KYCCheck], vessels: [Vessel]) {
        rescheduleCount += 1
    }
}

// MARK: - Mock Cloud Backup

class MockCloudBackup: CloudBackupProtocol {
    var backupCount = 0
    var lastChecksFile: URL?

    func backup(checksFile: URL, vesselsFile: URL, imagesDir: URL) {
        backupCount += 1
        lastChecksFile = checksFile
    }
}
