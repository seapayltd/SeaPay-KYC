//
//  Expiry_Widget.swift
//  Expiry Widget
//
//  Home screen widget showing document/certificate expiry counts.
//  Reads a lightweight JSON snapshot from the App Group shared container.
//

import WidgetKit
import SwiftUI

// MARK: - Shared Data Model (written by main app, read by widget)

struct WidgetExpiryData: Codable {
    let expiredCount: Int
    let expiringCount: Int
    let nextExpiryDate: String?
    let nextExpiryName: String?
    let vesselCount: Int
    let crewCount: Int
    let updatedAt: Date
}

// MARK: - Timeline Provider

struct ExpiryTimelineProvider: AppIntentTimelineProvider {
    typealias Entry = ExpiryEntry
    typealias Intent = ExpiryWidgetIntent

    func placeholder(in context: Context) -> ExpiryEntry {
        ExpiryEntry(date: Date(), data: .placeholder, configuration: ExpiryWidgetIntent())
    }

    func snapshot(for configuration: ExpiryWidgetIntent, in context: Context) async -> ExpiryEntry {
        ExpiryEntry(date: Date(), data: loadData(), configuration: configuration)
    }

    func timeline(for configuration: ExpiryWidgetIntent, in context: Context) async -> Timeline<ExpiryEntry> {
        let data = loadData()
        let entry = ExpiryEntry(date: Date(), data: data, configuration: configuration)
        // Refresh every 2 hours
        let next = Calendar.current.date(byAdding: .hour, value: 2, to: Date()) ?? Date()
        return Timeline(entries: [entry], policy: .after(next))
    }

    private func loadData() -> WidgetExpiryData {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.navemagna.SeaPay-KYC") else {
            return .placeholder
        }
        let file = container.appendingPathComponent("widget_expiry.json")
        guard let data = try? Data(contentsOf: file) else { return .placeholder }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(WidgetExpiryData.self, from: data)) ?? .placeholder
    }
}

extension WidgetExpiryData {
    static let placeholder = WidgetExpiryData(
        expiredCount: 0, expiringCount: 2,
        nextExpiryDate: "15 Apr 2026", nextExpiryName: "ENG1 — J. Smith",
        vesselCount: 1, crewCount: 5, updatedAt: Date()
    )
}

// MARK: - Entry

struct ExpiryEntry: TimelineEntry {
    let date: Date
    let data: WidgetExpiryData
    let configuration: ExpiryWidgetIntent
}

// MARK: - Small Widget View

struct ExpirySmallView: View {
    let data: WidgetExpiryData

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.shield").font(.system(size: 12)).foregroundStyle(.secondary)
                Text("OceanCheck").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
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
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 14)).foregroundStyle(.green)
                    Text("All clear").font(.system(size: 14, weight: .bold)).foregroundStyle(.green)
                }
                Text("No expiring docs").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Medium Widget View

struct ExpiryMediumView: View {
    let data: WidgetExpiryData

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.shield").font(.system(size: 12)).foregroundStyle(.secondary)
                    Text("OceanCheck").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                }

                Spacer()

                if data.expiredCount > 0 {
                    statRow("\(data.expiredCount)", "Expired", .red)
                }
                if data.expiringCount > 0 {
                    statRow("\(data.expiringCount)", "Expiring", .orange)
                }
                if data.expiredCount == 0 && data.expiringCount == 0 {
                    Text("All current").font(.system(size: 13, weight: .medium)).foregroundStyle(.green)
                }
            }

            if let name = data.nextExpiryName, let date = data.nextExpiryDate {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Next expiry").font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                    Text(date).font(.system(size: 14, weight: .bold))
                    Text(name).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                    Spacer()
                }
            }

            Spacer()
        }
    }

    private func statRow(_ value: String, _ label: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Text(value).font(.system(size: 20, weight: .bold)).foregroundStyle(color)
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Lock Screen (Accessory) Widgets

struct ExpiryAccessoryCircularView: View {
    let data: WidgetExpiryData

    var body: some View {
        let total = data.expiredCount + data.expiringCount
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 1) {
                Image(systemName: total > 0 ? "exclamationmark.triangle" : "checkmark.shield")
                    .font(.system(size: 12))
                Text("\(total)")
                    .font(.system(size: 16, weight: .bold))
            }
        }
    }
}

struct ExpiryAccessoryRectangularView: View {
    let data: WidgetExpiryData

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.shield").font(.system(size: 10))
                Text("OceanCheck").font(.system(size: 10, weight: .semibold))
            }
            if data.expiredCount > 0 {
                Text("\(data.expiredCount) expired").font(.system(size: 12, weight: .bold))
            }
            if data.expiringCount > 0 {
                Text("\(data.expiringCount) expiring soon").font(.system(size: 12, weight: .medium))
            }
            if data.expiredCount == 0 && data.expiringCount == 0 {
                Text("All documents current").font(.system(size: 12, weight: .medium))
            }
        }
    }
}

// MARK: - Widget Definition

struct Expiry_Widget: Widget {
    let kind: String = "com.navemagna.SeaPay-KYC.ExpiryWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ExpiryWidgetIntent.self, provider: ExpiryTimelineProvider()) { entry in
            ExpiryWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Expiry Status")
        .description("Document and certificate expiry at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

// MARK: - Entry View (routes by widget family)

struct ExpiryWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: ExpiryEntry

    var body: some View {
        switch family {
        case .systemMedium: ExpiryMediumView(data: entry.data)
        case .accessoryCircular: ExpiryAccessoryCircularView(data: entry.data)
        case .accessoryRectangular: ExpiryAccessoryRectangularView(data: entry.data)
        default: ExpirySmallView(data: entry.data)
        }
    }
}

// MARK: - Preview

#Preview(as: .systemSmall) {
    Expiry_Widget()
} timeline: {
    ExpiryEntry(date: .now, data: .placeholder, configuration: ExpiryWidgetIntent())
}
