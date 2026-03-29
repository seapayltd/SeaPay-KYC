//
//  ScenarioChecklistView.swift
//  OceanCheck
//
//  Shows scenario-driven document checklist for a vessel in a workspace.
//  Displays required docs, which are present/missing/expiring.
//

import SwiftUI

struct ScenarioChecklistView: View {
    let scenario: FleetScenario
    let vessel: Vessel
    let checks: [KYCCheck]

    private var vesselDocs: [CrewDocument] {
        (vessel.documents ?? []).filter { !$0.isArchived }
    }

    private var requiredVesselDocs: [VesselDocType] {
        scenario.includesAllDocs ? Array(Set(vesselDocs.compactMap(\.vesselDocType))) : scenario.requiredVesselDocTypes
    }

    private var requiredCrewDocs: [MaritimeDocType] {
        scenario.requiredCrewDocTypes
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: scenario.icon).font(.system(size: 13)).foregroundStyle(.secondary)
                Text(scenario.rawValue).font(Typo.body).fontWeight(.medium)
                Spacer()
                Text("\(completedCount)/\(totalCount)").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(completedCount == totalCount ? Color.clear_ : .secondary)
            }

            ProgressBar(value: completedCount, total: totalCount, height: 4)

            // Vessel certificates
            if !requiredVesselDocs.isEmpty {
                Text("VESSEL CERTIFICATES").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary).tracking(0.5)
                ForEach(requiredVesselDocs, id: \.rawValue) { docType in
                    let doc = vesselDocs.first(where: { $0.vesselDocType == docType })
                    checklistRow(name: docType.rawValue, status: doc?.status, hasDoc: doc != nil)
                }
            }

            // Crew documents
            if !requiredCrewDocs.isEmpty {
                Text("CREW DOCUMENTS").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary).tracking(0.5).padding(.top, 4)
                ForEach(requiredCrewDocs, id: \.rawValue) { docType in
                    let crewWithDoc = checks.filter { check in
                        (check.documents ?? []).contains(where: { $0.type == docType && !$0.isArchived })
                    }.count
                    let crewTotal = checks.filter { $0.entityType.category == .crew }.count
                    HStack(spacing: 8) {
                        Image(systemName: crewWithDoc >= crewTotal && crewTotal > 0 ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 12))
                            .foregroundStyle(crewWithDoc >= crewTotal && crewTotal > 0 ? Color.clear_ : .secondary.opacity(0.4))
                        Text(docType.displayName).font(Typo.meta).foregroundStyle(.primary)
                        Spacer()
                        Text("\(crewWithDoc)/\(crewTotal)").font(.system(size: 11, design: .rounded)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(14)
        .background(Color.surfaceMuted.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Row

    private func checklistRow(name: String, status: CrewDocument.Status?, hasDoc: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: hasDoc ? (status == .expired ? "exclamationmark.circle.fill" : status == .expiringSoon ? "exclamationmark.triangle.fill" : "checkmark.circle.fill") : "circle")
                .font(.system(size: 12))
                .foregroundStyle(hasDoc ? (status == .expired ? Color.flagged : status == .expiringSoon ? Color.review : Color.clear_) : .secondary.opacity(0.4))
            Text(name).font(Typo.meta).foregroundStyle(.primary).lineLimit(1)
            Spacer()
            if !hasDoc {
                Text("Missing").font(.system(size: 10)).foregroundStyle(Color.flagged.opacity(0.7))
            }
        }
    }

    // MARK: - Counts

    private var completedCount: Int {
        let vesselComplete = requiredVesselDocs.filter { req in vesselDocs.contains(where: { $0.vesselDocType == req && $0.status != .expired }) }.count
        return vesselComplete
    }

    private var totalCount: Int { requiredVesselDocs.count }
}
