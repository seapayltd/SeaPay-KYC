//
//  OwnerPortal.swift
//  OceanCheck
//
//  Read-only vessel dashboard for yacht owners.
//  Agent shares .oceandash file → owner opens → dashboard displays.
//

import SwiftUI

// MARK: - Snapshot Models

struct OwnerVesselSnapshot: Codable {
    let vesselName: String
    let vesselType: String?
    let flagState: String
    let imoNumber: String
    let grossTonnage: String?

    let certTotal: Int
    let certComplete: Int
    let certExpiring: Int
    let certExpired: Int

    let crew: [OwnerCrewEntry]
    let certificates: [OwnerCertEntry]

    let agentName: String
    let agentOrganization: String?
    let lastUpdated: Date
    let accessCode: String
}

struct OwnerCrewEntry: Codable, Identifiable {
    let id: String
    let name: String
    let rank: String?
    let entityType: String
    let status: String
    let docRatio: String?
}

struct OwnerCertEntry: Codable, Identifiable {
    let id: String
    let name: String
    let category: String
    let status: String
    let expiryDate: String?
}

// MARK: - Local Storage for Owner Snapshots

enum OwnerStorage {
    private static let key = "ownerSnapshot"

    static func save(_ snapshot: OwnerVesselSnapshot) {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(snapshot) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func load() -> OwnerVesselSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(OwnerVesselSnapshot.self, from: data)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: "ownerAccessCode")
    }

    static var hasSnapshot: Bool { UserDefaults.standard.data(forKey: key) != nil }
}

// MARK: - Owner Dashboard View

struct OwnerDashboardView: View {
    var onSignOut: (() -> Void)? = nil
    @State private var snapshot: OwnerVesselSnapshot? = OwnerStorage.load()
    @State private var showSignOutConfirm = false

    var body: some View {
        NavigationStack {
            Group {
                if let snapshot {
                    dashboardContent(snapshot)
                } else {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "doc.badge.arrow.up").font(.system(size: 44)).foregroundStyle(.quaternary)
                        Text("No vessel data yet").font(Typo.context).foregroundStyle(.secondary)
                        Text("Ask your agent to share a vessel dashboard file with you. When you open it, your vessel data will appear here.")
                            .font(Typo.meta).foregroundStyle(.tertiary).multilineTextAlignment(.center).padding(.horizontal, 32)
                        Spacer()
                    }
                }
            }
            .background(Color.surface.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(snapshot?.vesselName ?? "OceanCheck").font(BrandFont.brand(17))
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showSignOutConfirm = true } label: {
                        Image(systemName: "rectangle.portrait.and.arrow.right").font(.system(size: 14)).foregroundStyle(.secondary)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                snapshot = OwnerStorage.load()
            }
            .alert("Sign Out", isPresented: $showSignOutConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Sign Out", role: .destructive) {
                    OwnerStorage.clear()
                    onSignOut?()
                }
            } message: { Text("This will remove the vessel data from this device.") }
        }
    }

    func updateSnapshot(_ newSnapshot: OwnerVesselSnapshot) {
        snapshot = newSnapshot
    }

    // MARK: - Dashboard Content

    private func dashboardContent(_ s: OwnerVesselSnapshot) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                // Vessel header
                VStack(spacing: 8) {
                    Image(systemName: vesselIcon(s.vesselType))
                        .font(.system(size: 40)).foregroundStyle(.quaternary)
                    Text(s.vesselName).font(Typo.hero)
                    HStack(spacing: 8) {
                        if let vt = s.vesselType { MetadataPill(icon: nil, text: vt) }
                        if !s.flagState.isEmpty { MetadataPill(icon: "flag", text: s.flagState) }
                        if !s.imoNumber.isEmpty { MetadataPill(icon: "number", text: "IMO \(s.imoNumber)") }
                    }
                }
                .padding(.top, 16)

                // Compliance readiness
                ReadinessCard(
                    completed: s.certComplete, total: s.certTotal,
                    expiringCount: s.certExpiring, expiredCount: s.certExpired,
                    label: "certificates"
                )
                .padding(.horizontal, 16)

                // Crew
                if !s.crew.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("CREW & PERSONNEL (\(s.crew.count))")
                            .font(Typo.meta).foregroundStyle(.secondary).tracking(0.6)
                            .padding(.horizontal, 20).padding(.bottom, 6)

                        VStack(spacing: 0) {
                            ForEach(s.crew) { entry in crewRow(entry) }
                        }
                        .background(Color.surfaceMuted.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 16)
                    }
                }

                // Certificates
                if !s.certificates.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("CERTIFICATES")
                            .font(Typo.meta).foregroundStyle(.secondary).tracking(0.6)
                            .padding(.horizontal, 20).padding(.bottom, 6)

                        VStack(spacing: 0) {
                            ForEach(s.certificates) { cert in certRow(cert) }
                        }
                        .background(Color.surfaceMuted.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 16)
                    }
                }

                // Agent info
                VStack(spacing: 4) {
                    Text("Managed by \(s.agentName)").font(Typo.meta).foregroundStyle(.tertiary)
                    if let org = s.agentOrganization, !org.isEmpty {
                        Text(org).font(Typo.meta).foregroundStyle(.quaternary)
                    }
                    Text("Updated \(s.lastUpdated.formatted(date: .abbreviated, time: .shortened))")
                        .font(Typo.meta).foregroundStyle(.quaternary)
                }
                .padding(.top, 8).padding(.bottom, 32)
            }
        }
    }

    // MARK: - Row Views

    private func crewRow(_ entry: OwnerCrewEntry) -> some View {
        HStack(spacing: 12) {
            Circle().fill(statusColor(entry.status).opacity(0.1)).frame(width: 36, height: 36)
                .overlay {
                    Text(String(entry.name.prefix(1)).uppercased())
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(statusColor(entry.status))
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).font(Typo.body).fontWeight(.medium)
                HStack(spacing: 6) {
                    Text(entry.rank ?? entry.entityType).font(Typo.meta).foregroundStyle(.secondary)
                    if let ratio = entry.docRatio { Text(ratio).font(Typo.meta).foregroundStyle(.tertiary) }
                }
            }
            Spacer()
            Text(entry.status).font(.system(size: 11, weight: .semibold)).foregroundStyle(statusColor(entry.status))
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func certRow(_ cert: OwnerCertEntry) -> some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5).fill(certStatusColor(cert.status))
                .frame(width: 3, height: 28).padding(.trailing, 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(cert.name).font(Typo.body).lineLimit(1)
                if let exp = cert.expiryDate { Text(exp).font(Typo.meta).foregroundStyle(certStatusColor(cert.status)) }
            }
            Spacer()
            Text(cert.status).font(Typo.meta).foregroundStyle(certStatusColor(cert.status))
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "Clear": return .clear_
        case "Flagged": return .flagged
        case "Review": return .review
        default: return Color.secondary.opacity(0.5)
        }
    }

    private func certStatusColor(_ status: String) -> Color {
        switch status {
        case "Valid": return .clear_
        case "Expiring": return .review
        case "Expired": return .flagged
        default: return Color.secondary.opacity(0.3)
        }
    }

    private func vesselIcon(_ type: String?) -> String {
        guard let t = type?.lowercased() else { return "ferry" }
        if t.contains("yacht") || t.contains("sail") { return "sailboat" }
        if t.contains("tanker") { return "drop.triangle" }
        if t.contains("cargo") { return "shippingbox" }
        return "ferry"
    }
}

// MARK: - Owner Setup (Instructions)

struct OwnerSetupView: View {
    @Binding var ownerAccessCode: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "sailboat").font(.system(size: 48)).foregroundStyle(.primary.opacity(0.15))
                Text("Vessel Owner Access").font(Typo.context)
                Text("Your yacht manager will share a vessel dashboard file with you via WhatsApp, email, or AirDrop.\n\nWhen you receive it, simply tap the file to open it here.")
                    .font(Typo.meta).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 32)

                // If they already have a snapshot, go to dashboard
                if OwnerStorage.hasSnapshot {
                    Button {
                        ownerAccessCode = "local"
                        UserDefaults.standard.set("local", forKey: "ownerAccessCode")
                    } label: { Text("View Dashboard") }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, 48)
                }

                Spacer()
            }
            .background(Color.surface.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
    }
}

// MARK: - Share with Owner Sheet (Agent Side)

struct ShareWithOwnerSheet: View {
    @ObservedObject var vm: KYCViewModel
    let vesselId: String
    @Environment(\.dismiss) private var dismiss
    @State private var shareItem: IdentifiableURL?
    @State private var generating = false

    private var vessel: Vessel? { vm.vessels.first(where: { $0.id == vesselId }) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "person.badge.key").font(.system(size: 48)).foregroundStyle(.primary.opacity(0.15))
                Text("Share with Owner").font(Typo.context)
                Text("Generate a vessel dashboard that the owner can view in OceanCheck. The dashboard shows compliance status without sensitive personal data.")
                    .font(Typo.meta).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 32)

                // What's included
                VStack(alignment: .leading, spacing: 6) {
                    infoLine("checkmark", "Vessel name, type, flag state")
                    infoLine("checkmark", "Crew names, ranks, verification status")
                    infoLine("checkmark", "Certificate names and expiry dates")
                    infoLine("xmark", "No passport numbers or dates of birth")
                    infoLine("xmark", "No AML screening details")
                }
                .padding(.horizontal, 40)

                Spacer()

                Button {
                    generating = true
                    let vid = vesselId
                    Task.detached { [vm] in
                        let url = await vm.generateOwnerDashboard(vesselId: vid)
                        await MainActor.run {
                            generating = false
                            if let url { shareItem = IdentifiableURL(url: url) }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if generating {
                            ProgressView().controlSize(.small).tint(.surface)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                        Text(generating ? "Preparing..." : "Share Dashboard")
                    }
                }
                .buttonStyle(PrimaryButtonStyle(isEnabled: !generating))
                .disabled(generating)
                .padding(.horizontal, 48)

                Button("Cancel") { dismiss() }
                    .font(Typo.meta).foregroundStyle(.secondary)
                    .padding(.bottom, 20)
            }
            .background(Color.surface.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(item: $shareItem) { item in
                ActivityView(items: [item.url])
            }
        }
    }

    private func infoLine(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon == "checkmark" ? "checkmark.circle" : "xmark.circle")
                .font(Typo.meta).foregroundStyle(icon == "checkmark" ? Color.clear_ : Color.flagged)
            Text(text).font(Typo.meta).foregroundStyle(.secondary)
        }
    }
}
