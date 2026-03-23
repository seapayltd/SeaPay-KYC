//
//  ExpiryWidget.swift
//  OceanCheck
//
//  Home screen widget showing document expiry status.
//  Note: Requires a Widget Extension target to be added in Xcode.
//  This file provides the data provider and view templates.
//

import SwiftUI
import WidgetKit

// MARK: - Widget Data Provider

struct ExpiryWidgetData {
    let expiredCount: Int
    let expiringCount: Int
    let nextExpiry: String?
    let nextExpiryName: String?

    static let placeholder = ExpiryWidgetData(expiredCount: 0, expiringCount: 2, nextExpiry: "15 Apr 2026", nextExpiryName: "ENG1 — J. Smith")

    static func load() -> ExpiryWidgetData {
        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let checksFile = docsDir.appendingPathComponent("kyc_checks.json")

        guard let data = try? Data(contentsOf: checksFile) else {
            return ExpiryWidgetData(expiredCount: 0, expiringCount: 0, nextExpiry: nil, nextExpiryName: nil)
        }

        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        guard let checks = try? decoder.decode([KYCCheck].self, from: data) else {
            return ExpiryWidgetData(expiredCount: 0, expiringCount: 0, nextExpiry: nil, nextExpiryName: nil)
        }

        let dateFmt = DateFormatter(); dateFmt.dateFormat = "yyyy-MM-dd"
        let now = Date()
        let cutoff = Calendar.current.date(byAdding: .day, value: 90, to: now)!

        var expired = 0, expiring = 0
        var nextDate: Date?
        var nextName: String?

        for check in checks {
            // ID document expiry
            if let s = check.expiryDate, let d = dateFmt.date(from: s) {
                if d < now { expired += 1 }
                else if d <= cutoff {
                    expiring += 1
                    if nextDate == nil || d < nextDate! { nextDate = d; nextName = "\(check.documentType ?? "ID") — \(check.displayName)" }
                }
            }
            // Certificate expiry
            for doc in check.documents ?? [] where doc.expiryDate != nil && !doc.isArchived {
                let d = doc.expiryDate!
                if d < now { expired += 1 }
                else if d <= cutoff {
                    expiring += 1
                    if nextDate == nil || d < nextDate! { nextDate = d; nextName = "\(doc.type.displayName) — \(check.displayName)" }
                }
            }
        }

        let expiryStr = nextDate.map { dateFmt.string(from: $0) }
        return ExpiryWidgetData(expiredCount: expired, expiringCount: expiring, nextExpiry: expiryStr, nextExpiryName: nextName)
    }
}

// MARK: - Widget View Templates

struct ExpiryWidgetSmallView: View {
    let data: ExpiryWidgetData

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "checkmark.shield").font(.system(size: 16)).foregroundStyle(.secondary)
                Text("OceanCheck").font(.system(size: 12, weight: .semibold))
            }

            Spacer()

            if data.expiredCount > 0 {
                HStack(spacing: 4) {
                    Circle().fill(Color.red).frame(width: 6, height: 6)
                    Text("\(data.expiredCount) expired").font(.system(size: 14, weight: .bold)).foregroundStyle(.red)
                }
            }

            if data.expiringCount > 0 {
                HStack(spacing: 4) {
                    Circle().fill(Color.orange).frame(width: 6, height: 6)
                    Text("\(data.expiringCount) expiring").font(.system(size: 14, weight: .bold)).foregroundStyle(.orange)
                }
            }

            if data.expiredCount == 0 && data.expiringCount == 0 {
                Text("All clear").font(.system(size: 16, weight: .bold)).foregroundStyle(.green)
                Text("No expiring docs").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(14)
    }
}

struct ExpiryWidgetMediumView: View {
    let data: ExpiryWidgetData

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "checkmark.shield").font(.system(size: 16)).foregroundStyle(.secondary)
                    Text("OceanCheck").font(.system(size: 12, weight: .semibold))
                }

                Spacer()

                if data.expiredCount > 0 {
                    statRow("\(data.expiredCount)", "Expired", .red)
                }
                if data.expiringCount > 0 {
                    statRow("\(data.expiringCount)", "Expiring", .orange)
                }
                if data.expiredCount == 0 && data.expiringCount == 0 {
                    Text("All documents current").font(.system(size: 13, weight: .medium)).foregroundStyle(.green)
                }
            }

            if let name = data.nextExpiryName, let date = data.nextExpiry {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Next expiry").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    Text(date).font(.system(size: 14, weight: .bold))
                    Text(name).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                }
            }

            Spacer()
        }
        .padding(14)
    }

    private func statRow(_ value: String, _ label: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Text(value).font(.system(size: 20, weight: .bold)).foregroundStyle(color)
            Text(label).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
}
