//
//  TransferHistoryView.swift
//  OceanCheck
//
//  Audit log of all .oceancheck transfers — sent and received.
//  Supports rollback of imports and re-export of received data.
//

import SwiftUI

struct TransferHistoryView: View {
    @ObservedObject var vm: KYCViewModel
    @State private var filter = 0
    @State private var selectedRecord: TransferRecord?
    @State private var showRollbackConfirm = false
    @State private var showReExportShare = false
    @State private var reExportURL: URL?

    private let filters = ["All", "Sent", "Received"]

    private var filtered: [TransferRecord] {
        switch filter {
        case 1: return vm.transferLog.filter { $0.direction == .sent }
        case 2: return vm.transferLog.filter { $0.direction == .received }
        default: return vm.transferLog
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(filters.indices, id: \.self) { i in
                        Button { withAnimation(.smooth(duration: 0.2)) { filter = i } } label: {
                            FilterChip(title: filters[i], isSelected: filter == i)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 10)
            }

            if filtered.isEmpty {
                VStack(spacing: 14) {
                    Spacer(minLength: 60)
                    Image(systemName: "arrow.left.arrow.right.circle").font(.system(size: 44)).foregroundStyle(.quaternary)
                    Text("No transfers yet").font(Typo.context).foregroundStyle(.secondary)
                    Text("Transfer history appears when you send or receive vessel data").font(Typo.meta).foregroundStyle(.quaternary)
                        .multilineTextAlignment(.center).padding(.horizontal, 32)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(filtered) { record in
                        Button { selectedRecord = record } label: {
                            transferRow(record)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .background(Color.surface.ignoresSafeArea())
        .navigationTitle("Transfer History")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedRecord) { record in
            transferDetailSheet(record)
        }
        .sheet(isPresented: $showReExportShare) {
            if let url = reExportURL { ActivityView(items: [url]) }
        }
    }

    // MARK: - Row

    private func transferRow(_ record: TransferRecord) -> some View {
        HStack(spacing: 14) {
            // Direction icon
            Image(systemName: record.direction == .sent ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(record.direction == .sent ? Color.primary : Color.clear_)

            VStack(alignment: .leading, spacing: 3) {
                Text(record.vesselName).font(Typo.body).fontWeight(.medium).foregroundStyle(.primary)
                HStack(spacing: 6) {
                    Text(record.scenario).font(Typo.meta).foregroundStyle(.secondary)
                    Text("·").foregroundStyle(.quaternary)
                    Text("\(record.checksCount) checks").font(Typo.meta).foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    Text(record.direction == .sent ? "To: " : "From: ").font(Typo.meta).foregroundStyle(.tertiary)
                    Text(record.direction == .sent
                         ? (record.receiverAgentName ?? "Unknown")
                         : record.senderAgentName
                    ).font(Typo.meta).foregroundStyle(.tertiary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(record.timestamp.formatted(date: .abbreviated, time: .omitted)).font(Typo.meta).foregroundStyle(.tertiary)
                Text(record.timestamp.formatted(date: .omitted, time: .shortened)).font(Typo.meta).foregroundStyle(.quaternary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Detail Sheet

    private func transferDetailSheet(_ record: TransferRecord) -> some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Spacer(minLength: 16)

                    // Direction badge
                    HStack(spacing: 8) {
                        Image(systemName: record.direction == .sent ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                            .font(.system(size: 20))
                        Text(record.direction == .sent ? "Sent" : "Received").font(Typo.context)
                    }
                    .foregroundStyle(record.direction == .sent ? .primary : Color.clear_)

                    // Vessel
                    VStack(spacing: 4) {
                        Text(record.vesselName).font(.system(size: 20, weight: .bold))
                        if !record.vesselIMO.isEmpty {
                            Text("IMO \(record.vesselIMO)").font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
                        }
                    }

                    // Details
                    VStack(spacing: 1) {
                        detailRow("Scenario", record.scenario)
                        detailRow("Date", record.timestamp.formatted(date: .long, time: .shortened))
                        detailRow("Checks", "\(record.checksCount)")
                        if record.direction == .sent {
                            detailRow("Sender", record.senderAgentName)
                            if !record.senderOrganization.isEmpty { detailRow("Organization", record.senderOrganization) }
                        } else {
                            detailRow("From Agent", record.senderAgentName)
                            if !record.senderOrganization.isEmpty { detailRow("From Org", record.senderOrganization) }
                            if let receiver = record.receiverAgentName { detailRow("Received By", receiver) }
                        }
                        if let hash = record.contentHash {
                            detailRow("Hash", String(hash.prefix(16)) + "...")
                        }
                        if record.wasVesselUpdate { detailRow("Type", "Updated existing vessel") }
                    }
                    .background(Color.surfaceMuted.opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 20)

                    // Actions for received transfers
                    if record.direction == .received {
                        Spacer(minLength: 16)

                        Button {
                            reExportURL = vm.reExportTransfer(transferId: record.id)
                            if reExportURL != nil {
                                selectedRecord = nil
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showReExportShare = true }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "square.and.arrow.up")
                                Text("Re-export Package")
                            }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .padding(.horizontal, 32)

                        Button(role: .destructive) { showRollbackConfirm = true } label: {
                            Text("Rollback Import").font(Typo.meta)
                        }
                    }

                    Spacer(minLength: 32)
                }
            }
            .background(Color.surface.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { selectedRecord = nil } }
            }
            .alert("Rollback Import", isPresented: $showRollbackConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Rollback", role: .destructive) {
                    _ = vm.rollbackImport(transferId: record.id)
                    selectedRecord = nil
                }
            } message: {
                Text("This will remove the imported vessel data and \(record.checksCount) checks. This cannot be undone.")
            }
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(Typo.meta).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
            Text(value).font(Typo.body)
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}
