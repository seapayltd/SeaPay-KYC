//
//  TransferImportSheet.swift
//  OceanCheck
//
//  Preview .oceancheck package contents before importing.
//  Shows sender, vessel, crew count, integrity check.
//

import SwiftUI

struct TransferImportSheet: View {
    @ObservedObject var vm: KYCViewModel
    let packageURL: URL
    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .unpacking
    @State private var preview: TransferPackagePreview?
    @State private var importResult: TransferImportResult?

    enum Phase { case unpacking, preview, importing, result }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .unpacking: unpackingView
                case .preview: previewView
                case .importing: importingView
                case .result: resultView
                }
            }
            .background(Color.surface.ignoresSafeArea())
            .navigationTitle("Transfer Package")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if phase == .preview || phase == .result {
                        Button { dismiss() } label: {
                            Image(systemName: phase == .result ? "xmark" : "xmark").foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .task { await unpack() }
    }

    // MARK: - Phases

    private var unpackingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView().controlSize(.large)
            Text("Reading package...").font(Typo.body).foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var previewView: some View {
        ScrollView {
            VStack(spacing: 16) {
                Spacer(minLength: 16)

                if let p = preview {
                    // Sender card
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader("From")
                        HStack(spacing: 12) {
                            Circle().fill(Color.surfaceMuted).frame(width: 44, height: 44)
                                .overlay { Text(String(p.senderName.prefix(1)).uppercased()).font(.system(size: 18, weight: .semibold)).foregroundStyle(.secondary) }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.senderName).font(Typo.body).fontWeight(.medium)
                                if !p.senderOrg.isEmpty { Text(p.senderOrg).font(Typo.meta).foregroundStyle(.secondary) }
                                if !p.senderAgentId.isEmpty { Text(p.senderAgentId).font(.system(size: 10, design: .monospaced)).foregroundStyle(.quaternary) }
                            }
                            Spacer()
                        }
                        .padding(14)
                        .background(Color.surfaceMuted.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal, 20)

                    // Vessel card
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader("Vessel")
                        VStack(alignment: .leading, spacing: 8) {
                            Text(p.vesselName).font(.system(size: 18, weight: .bold))
                            HStack(spacing: 8) {
                                if let vt = p.vesselType, !vt.isEmpty {
                                    MetadataPill(icon: nil, text: vt)
                                }
                                if !p.vesselIMO.isEmpty {
                                    MetadataPill(icon: "number", text: "IMO \(p.vesselIMO)")
                                }
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.surfaceMuted.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal, 20)

                    // Contents summary
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader("Contents")
                        VStack(spacing: 1) {
                            summaryRow("person.text.rectangle", "\(p.checksCount) crew/compliance checks")
                            if p.hasImages { summaryRow("photo", "Document images included") }
                            if p.hasOwnership { summaryRow("person.badge.key", "Ownership structure included") }
                            summaryRow("calendar", p.generatedAt.prefix(10).description)
                            summaryRow("doc.text", "Format v\(p.formatVersion)")
                        }
                        .background(Color.surfaceMuted.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal, 20)

                    // Integrity check
                    HStack(spacing: 8) {
                        Image(systemName: p.contentHash != nil ? "checkmark.shield" : "questionmark.circle")
                            .font(.system(size: 13))
                            .foregroundStyle(p.contentHash != nil ? Color.clear_ : .secondary)
                        Text(p.contentHash != nil ? "Package integrity verified" : "No integrity hash (older format)")
                            .font(Typo.meta)
                            .foregroundStyle(p.contentHash != nil ? Color.clear_ : .secondary)
                    }
                    .padding(.horizontal, 20)

                    // Existing vessel warning
                    if p.existsLocally {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle").font(.system(size: 13))
                            Text("This vessel already exists. Existing ownership will be archived.")
                                .font(Typo.meta)
                        }
                        .foregroundStyle(Color.review)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.review.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal, 20)
                    }

                    Spacer(minLength: 16)

                    // Actions
                    Button { performImport() } label: { Text("Import") }
                        .buttonStyle(PrimaryButtonStyle())
                        .padding(.horizontal, 32)

                    Button { dismiss() } label: {
                        Text("Cancel").font(Typo.meta).foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 20)
                } else {
                    // Failed to read
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle").font(.system(size: 36)).foregroundStyle(.quaternary)
                        Text("Could not read package").font(Typo.body).foregroundStyle(.secondary)
                    }
                    .padding(.top, 60)

                    Button { dismiss() } label: { Text("Done") }
                        .buttonStyle(PrimaryButtonStyle())
                        .padding(.horizontal, 48).padding(.top, 20)
                }
            }
        }
    }

    private var importingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView().controlSize(.large)
            Text("Importing...").font(Typo.body).foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var resultView: some View {
        VStack(spacing: 20) {
            Spacer()

            if let r = importResult, r.success {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 56)).foregroundStyle(Color.clear_)
                Text("Import Complete").font(Typo.context)
                VStack(spacing: 4) {
                    Text(r.vesselName ?? "Vessel").font(Typo.body).fontWeight(.medium)
                    Text("\(r.importedCheckIds.count) checks imported").font(Typo.meta).foregroundStyle(.secondary)
                    if r.wasUpdate {
                        Text("Existing vessel updated — previous ownership archived").font(Typo.meta).foregroundStyle(Color.review)
                    }
                }
            } else {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 56)).foregroundStyle(Color.flagged)
                Text("Import Failed").font(Typo.context)
                if let err = importResult?.error {
                    Text(err).font(Typo.meta).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).padding(.horizontal, 32)
                }
            }

            Spacer()

            Button { dismiss() } label: { Text("Done") }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 48)
                .padding(.bottom, 20)
        }
    }

    // MARK: - Actions

    private func unpack() async {
        let p = await Task.detached { [vm, packageURL] in
            return await vm.previewTransferPackage(from: packageURL)
        }.value
        await MainActor.run {
            preview = p
            withAnimation { phase = .preview }
        }
    }

    private func performImport() {
        withAnimation { phase = .importing }
        Task.detached { [vm, packageURL] in
            let result = await vm.importTransferPackageEnhanced(from: packageURL)
            await MainActor.run {
                importResult = result
                Haptics.success()
                withAnimation { phase = .result }
            }
        }
    }

    // MARK: - Components

    private func summaryRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 13)).foregroundStyle(.secondary).frame(width: 20)
            Text(text).font(Typo.body)
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}
