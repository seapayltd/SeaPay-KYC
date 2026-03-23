//
//  ShareVesselSheet.swift
//  OceanCheck
//
//  Scenario-driven vessel data sharing.
//  Each export is justified by a real-world maritime event.
//

import SwiftUI
import PDFKit

// MARK: - Scenarios

enum VesselShareScenario: String, CaseIterable, Identifiable {
    case vesselSale = "Vessel Sale"
    case managementChange = "Change of Management"
    case flagStateRequest = "Flag State / PSC Request"
    case portRequest = "Port / Harbour Master"
    case classSociety = "Class Society / Surveyor"
    case insuranceRequest = "P&I Club / Insurance"
    case charterDueDiligence = "Charter Due Diligence"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .vesselSale: return "arrow.right.arrow.left"
        case .managementChange: return "building.2.crop.circle"
        case .flagStateRequest: return "flag"
        case .portRequest: return "ferry"
        case .classSociety: return "checkmark.seal"
        case .insuranceRequest: return "shield.checkered"
        case .charterDueDiligence: return "doc.text.magnifyingglass"
        }
    }

    var subtitle: String {
        switch self {
        case .vesselSale: return "Transfer complete vessel file to buyer's agent"
        case .managementChange: return "Hand over to new management company"
        case .flagStateRequest: return "Crew list, certificates, compliance evidence"
        case .portRequest: return "Pre-arrival documentation (FAL 5 + certificates)"
        case .classSociety: return "Certificate status and survey dates"
        case .insuranceRequest: return "Full compliance evidence for P&I"
        case .charterDueDiligence: return "Sanitized compliance summary for charterers"
        }
    }

    var isTransfer: Bool { self == .vesselSale || self == .managementChange }
    var isSanitized: Bool { self == .charterDueDiligence }

    var scope: ShareScope {
        switch self {
        case .vesselSale:
            return ShareScope(vesselCerts: true, crewRecords: true, crewDocs: true, shoreBased: true, ownership: true, ubo: true, aml: true, images: true, sanitize: false)
        case .managementChange:
            return ShareScope(vesselCerts: true, crewRecords: true, crewDocs: true, shoreBased: false, ownership: true, ubo: true, aml: true, images: true, sanitize: false)
        case .flagStateRequest:
            return ShareScope(vesselCerts: true, crewRecords: true, crewDocs: true, shoreBased: false, ownership: false, ubo: false, aml: true, images: false, sanitize: false)
        case .portRequest:
            return ShareScope(vesselCerts: true, crewRecords: true, crewDocs: false, shoreBased: false, ownership: false, ubo: false, aml: false, images: false, sanitize: false)
        case .classSociety:
            return ShareScope(vesselCerts: true, crewRecords: false, crewDocs: false, shoreBased: false, ownership: false, ubo: false, aml: false, images: false, sanitize: false)
        case .insuranceRequest:
            return ShareScope(vesselCerts: true, crewRecords: true, crewDocs: true, shoreBased: false, ownership: true, ubo: true, aml: true, images: false, sanitize: false)
        case .charterDueDiligence:
            return ShareScope(vesselCerts: true, crewRecords: true, crewDocs: false, shoreBased: false, ownership: false, ubo: false, aml: false, images: false, sanitize: true)
        }
    }
}

struct ShareScope {
    var vesselCerts: Bool
    var crewRecords: Bool
    var crewDocs: Bool
    var shoreBased: Bool
    var ownership: Bool
    var ubo: Bool
    var aml: Bool
    var images: Bool
    var sanitize: Bool
}

// MARK: - Share Vessel Sheet

struct ShareVesselSheet: View {
    @ObservedObject var vm: KYCViewModel
    let vessel: Vessel
    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .selectScenario
    @State private var selectedScenario: VesselShareScenario?
    @State private var resultURL: URL?
    @State private var showShare = false
    @State private var generating = false

    enum Phase { case selectScenario, generating, preview }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .selectScenario: scenarioList
                case .generating: generatingView
                case .preview: previewView
                }
            }
            .background(Color.surface.ignoresSafeArea())
            .navigationTitle("Share Vessel Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { if phase == .selectScenario { dismiss() } else { withAnimation { phase = .selectScenario; resultURL = nil } } } label: {
                        Image(systemName: phase == .selectScenario ? "xmark" : "chevron.left").foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Scenario List

    private var scenarioList: some View {
        List {
            Section {
                ForEach([VesselShareScenario.vesselSale, .managementChange]) { scenario in
                    scenarioRow(scenario)
                }
            } header: {
                Text("Handover")
            } footer: {
                Text("Creates a transfer package (.oceancheck) that another agent can import")
            }

            Section {
                ForEach([VesselShareScenario.flagStateRequest, .portRequest, .classSociety, .insuranceRequest, .charterDueDiligence]) { scenario in
                    scenarioRow(scenario)
                }
            } header: {
                Text("Export for Third Party")
            } footer: {
                Text("Generates a formal PDF packet for the recipient")
            }
        }
        .listStyle(.insetGrouped)
    }

    private func scenarioRow(_ scenario: VesselShareScenario) -> some View {
        Button {
            selectedScenario = scenario
            withAnimation { phase = .generating }
            Task { await generate(scenario) }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: scenario.icon).font(.system(size: 16)).foregroundStyle(.primary).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(scenario.rawValue).font(Typo.body).fontWeight(.medium)
                    Text(scenario.subtitle).font(Typo.meta).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: scenario.isTransfer ? "arrow.right.circle" : "doc.text").font(Typo.meta).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
        }
        .foregroundStyle(.primary)
    }

    // MARK: - Generating

    private var generatingView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView().controlSize(.large)
            Text("Preparing \(selectedScenario?.rawValue ?? "export")...").font(Typo.body).foregroundStyle(.secondary)
            if let s = selectedScenario {
                Text(s.isTransfer ? "Creating transfer package" : "Generating PDF").font(Typo.meta).foregroundStyle(.tertiary)
            }
            Spacer()
        }
    }

    // MARK: - Preview

    private var previewView: some View {
        VStack(spacing: 0) {
            if let url = resultURL {
                if url.pathExtension == "pdf" {
                    PDFKitView(url: url).ignoresSafeArea(edges: .bottom)
                } else {
                    // Transfer package — show summary
                    ScrollView {
                        VStack(spacing: 20) {
                            Spacer(minLength: 40)
                            Image(systemName: "checkmark.circle").font(.system(size: 48)).foregroundStyle(Color.clear_)
                            Text("Transfer Package Ready").font(Typo.context)

                            let crew = vm.seafarersForVessel(vessel.id)
                            let docs = (vessel.documents ?? []).count
                            VStack(spacing: 6) {
                                summaryLine("ferry", vessel.name)
                                summaryLine("person.text.rectangle", "\(crew.count) crew members")
                                summaryLine("doc.text", "\(docs) vessel certificates")
                                if vessel.ownershipStructure != nil { summaryLine("person.badge.key", "Ownership structure included") }
                            }

                            Text(url.lastPathComponent).font(Typo.meta).foregroundStyle(.tertiary)
                            Spacer(minLength: 40)
                        }
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 36)).foregroundStyle(.quaternary)
                    Text("Failed to generate export").font(Typo.body).foregroundStyle(.secondary)
                }
            }

            // Share bar
            if resultURL != nil {
                Button { showShare = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share")
                    }
                    .font(Typo.body).fontWeight(.medium)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Color.primary).foregroundStyle(Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
                .background(.bar)
            }
        }
        .sheet(isPresented: $showShare) {
            if let url = resultURL { ActivityView(items: [url]) }
        }
    }

    private func summaryLine(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(Typo.meta).foregroundStyle(.secondary).frame(width: 20)
            Text(text).font(Typo.body)
            Spacer()
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Generate

    private func generate(_ scenario: VesselShareScenario) async {
        try? await Task.sleep(nanoseconds: 200_000_000)
        await MainActor.run {
            if scenario.isTransfer {
                resultURL = vm.generateTransferPackage(vesselId: vessel.id, scenario: scenario)
            } else {
                resultURL = vm.generateShareExport(vesselId: vessel.id, scenario: scenario)
            }
            withAnimation { phase = .preview }
        }
    }
}
