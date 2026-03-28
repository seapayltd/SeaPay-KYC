//
//  APIUsageView.swift
//  OceanCheck
//
//  Dashboard showing API call counts and estimated costs.
//

import SwiftUI

struct APIUsageView: View {
    private let today = APIUsageTracker.todayUsage()
    private let last30 = APIUsageTracker.last30Days()
    private let totals = APIUsageTracker.totalLast30Days()

    var body: some View {
        List {
            // Today
            Section("Today") {
                usageRow("ID Verification", today.idScans, "person.text.rectangle")
                usageRow("AML Screening", today.amlScreenings, "shield.checkered")
                usageRow("Proof of Address", today.poaChecks, "house")
                usageRow("Claude OCR", today.claudeOCR, "doc.text.viewfinder")
                usageRow("Sessions", today.sessions, "link")
                HStack {
                    Text("Total").font(Typo.body).fontWeight(.medium)
                    Spacer()
                    Text("\(today.totalCalls) calls").font(Typo.body).fontWeight(.medium)
                }
                HStack {
                    Text("Est. cost").font(Typo.meta).foregroundStyle(.secondary)
                    Spacer()
                    Text("$\(String(format: "%.2f", today.estimatedCost))").font(Typo.body).fontWeight(.medium)
                }
            }

            // 30-day summary
            Section("Last 30 Days") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(totals.calls)").font(.system(size: 28, weight: .bold))
                        Text("API calls").font(Typo.meta).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("$\(String(format: "%.2f", totals.cost))").font(.system(size: 28, weight: .bold))
                        Text("Est. cost").font(Typo.meta).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }

            // Daily breakdown
            if !last30.isEmpty {
                Section("Daily Breakdown") {
                    ForEach(last30) { day in
                        HStack {
                            Text(day.date).font(Typo.body)
                            Spacer()
                            Text("\(day.totalCalls) calls").font(Typo.meta).foregroundStyle(.secondary)
                            Text("$\(String(format: "%.2f", day.estimatedCost))").font(Typo.meta).frame(width: 60, alignment: .trailing)
                        }
                    }
                }
            }

            // Pricing note
            Section {
                Text("Cost estimates are approximate and based on typical API pricing. Check your Didit and Anthropic dashboards for actual charges.")
                    .font(Typo.meta).foregroundStyle(.quaternary)
            }
        }
        .navigationTitle("API Usage")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func usageRow(_ label: String, _ count: Int, _ icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 20)
            Text(label).font(Typo.body).foregroundStyle(.secondary)
            Spacer()
            Text("\(count)").font(Typo.body).fontWeight(.medium)
        }
    }
}
