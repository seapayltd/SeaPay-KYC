//
//  KYCViewModel+Persistence.swift
//  OceanCheck
//
//  Encrypted JSON persistence, image cache, backup export/import.
//

import Foundation
import UIKit
import os.log

private let persistLogger = Logger(subsystem: "com.seapay.kyc", category: "Persistence")

extension KYCViewModel {

    // MARK: - Backup Export

    func exportBackup() -> URL? {
        let fm = FileManager.default
        let backupDir = fm.temporaryDirectory.appendingPathComponent("OceanCheck_Backup_\(UUID().uuidString.prefix(8))")
        try? fm.removeItem(at: backupDir)
        try? fm.createDirectory(at: backupDir, withIntermediateDirectories: true)

        // Decrypt files for backup (export as plaintext for portability)
        let checksURL = docsDir.appendingPathComponent("kyc_checks.json")
        let vesselsURL = docsDir.appendingPathComponent("vessels.json")
        let transferURL = docsDir.appendingPathComponent("transfer_log.json")

        if let data = EncryptionService.readDecrypted(from: checksURL) {
            try? data.write(to: backupDir.appendingPathComponent("kyc_checks.json"))
        }
        if let data = EncryptionService.readDecrypted(from: vesselsURL) {
            try? data.write(to: backupDir.appendingPathComponent("vessels.json"))
        }
        if let data = EncryptionService.readDecrypted(from: transferURL) {
            try? data.write(to: backupDir.appendingPathComponent("transfer_log.json"))
        }

        // Copy images
        let imgsBackup = backupDir.appendingPathComponent("images")
        try? fm.createDirectory(at: imgsBackup, withIntermediateDirectories: true)
        if let files = try? fm.contentsOfDirectory(atPath: imagesDir.path) {
            for f in files { try? fm.copyItem(at: imagesDir.appendingPathComponent(f), to: imgsBackup.appendingPathComponent(f)) }
        }

        // Create zip
        let zipURL = fm.temporaryDirectory.appendingPathComponent("OceanCheck_Backup.zip")
        try? fm.removeItem(at: zipURL)
        var error: NSError?
        var success = false
        NSFileCoordinator().coordinate(readingItemAt: backupDir, options: .forUploading, error: &error) { tempURL in
            try? fm.copyItem(at: tempURL, to: zipURL)
            success = true
        }
        try? fm.removeItem(at: backupDir)

        #if DEBUG
        persistLogger.debug("ZIP created: \(success), file exists: \(fm.fileExists(atPath: zipURL.path))")
        #endif

        if success && fm.fileExists(atPath: zipURL.path) { return zipURL }
        let checksFile = docsDir.appendingPathComponent("kyc_checks.json")
        return fm.fileExists(atPath: checksFile.path) ? checksFile : nil
    }

    func importBackup(from url: URL) -> Bool {
        guard url.startAccessingSecurityScopedResource() else { return false }
        defer { url.stopAccessingSecurityScopedResource() }

        let fm = FileManager.default
        let tempDir = docsDir.appendingPathComponent("_import_temp")
        try? fm.removeItem(at: tempDir)
        try? fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dest = tempDir.appendingPathComponent(url.lastPathComponent)
        try? fm.copyItem(at: url, to: dest)

        let checksFile = docsDir.appendingPathComponent("kyc_checks.json")
        let vesselsFile = docsDir.appendingPathComponent("vessels.json")
        let transferLogFile = docsDir.appendingPathComponent("transfer_log.json")

        let checksSource = findFile("kyc_checks.json", in: tempDir)
        let vesselsSource = findFile("vessels.json", in: tempDir)

        if let src = checksSource { try? fm.removeItem(at: checksFile); try? fm.copyItem(at: src, to: checksFile) }
        if let src = vesselsSource { try? fm.removeItem(at: vesselsFile); try? fm.copyItem(at: src, to: vesselsFile) }
        if let src = findFile("transfer_log.json", in: tempDir) { try? fm.removeItem(at: transferLogFile); try? fm.copyItem(at: src, to: transferLogFile) }

        let imgsSource = findDirectory("images", in: tempDir)
        if let src = imgsSource, let files = try? fm.contentsOfDirectory(atPath: src.path) {
            try? fm.createDirectory(at: imagesDir, withIntermediateDirectories: true)
            for f in files {
                let d = imagesDir.appendingPathComponent(f)
                try? fm.removeItem(at: d)
                try? fm.copyItem(at: src.appendingPathComponent(f), to: d)
            }
        }

        try? fm.removeItem(at: tempDir)
        reloadAll()
        return checksSource != nil
    }

    // MARK: - File Search Helpers

    func findFile(_ name: String, in dir: URL) -> URL? {
        let fm = FileManager.default
        let direct = dir.appendingPathComponent(name)
        if fm.fileExists(atPath: direct.path) { return direct }
        if let contents = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for item in contents {
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue {
                    if let found = findFile(name, in: item) { return found }
                }
                if item.lastPathComponent == name { return item }
            }
        }
        return nil
    }

    func findDirectory(_ name: String, in dir: URL) -> URL? {
        let fm = FileManager.default
        let direct = dir.appendingPathComponent(name)
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: direct.path, isDirectory: &isDir), isDir.boolValue { return direct }
        if let contents = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for item in contents {
                if fm.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue {
                    if item.lastPathComponent == name { return item }
                    if let found = findDirectory(name, in: item) { return found }
                }
            }
        }
        return nil
    }
}
