//
//  HomeView.swift
//  OceanCheck
//
//  Home: vessel cards, crew list, expiry alerts.
//  One purpose: what needs your attention?
//

import SwiftUI
import Network

struct HomeView: View {
    @ObservedObject var vm: KYCViewModel
    var appState: AppState

    @State private var activeCheck: KYCCheck?
    @State private var inviteCheck: KYCCheck?
    @State private var showSettings = false
    @State private var showAddVessel = false
    @State private var showBatchInvite = false
    @State private var showCSVExport = false
    @State private var csvURL: URL?
    @State private var searchText = ""
    @State private var tab = 0

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    // Offline
                    if !vm.isOnline {
                        HStack(spacing: 8) {
                            Image(systemName: "wifi.slash").font(.system(size: 11))
                            Text("Offline").font(Typo.meta)
                        }
                        .foregroundStyle(.white).frame(maxWidth: .infinity)
                        .padding(.vertical, 6).background(Color.secondary.opacity(0.7))
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // Expiry alert
                    expiryBanner

                    // Tabs
                    Picker("", selection: $tab) {
                        Text("Vessels").tag(0)
                        Text("All").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 20).padding(.vertical, 10)

                    // Content
                    if tab == 0 { vesselsList } else { allChecksList }

                    Spacer(minLength: 0)
                }
                .frame(maxHeight: .infinity)
                .background(Color.surface.ignoresSafeArea())

                // Floating add button — pinned to screen bottom-right
                addButton
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { Text("OceanCheck").font(BrandFont.brand(17)) }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape").font(.system(size: 14)).foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { showBatchInvite = true } label: { Label("Batch Invite", systemImage: "person.2.badge.plus") }
                        if !vm.checks.isEmpty {
                            Button { csvURL = vm.generateCSV(vesselId: nil); if csvURL != nil { showCSVExport = true } } label: { Label("Export CSV", systemImage: "tablecells") }
                        }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 14)).foregroundStyle(.secondary)
                    }
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search crew or vessels")
            .sheet(item: $activeCheck) { VerificationSheet(vm: vm, check: $0) }
            .sheet(item: $inviteCheck) { InviteSheet(vm: vm, check: $0) }
            .sheet(isPresented: $showSettings) { SettingsSheet(vm: vm, appState: appState) }
            .sheet(isPresented: $showAddVessel) { VesselSheet(vm: vm) }
            .sheet(isPresented: $showBatchInvite) { BatchInviteSheet(vm: vm) }
            .sheet(isPresented: $showCSVExport) { if let url = csvURL { ActivityView(items: [url]) } }
            .sheet(item: $selectedVesselForAdd) { vessel in
                AddCrewSheet(vm: vm, vesselId: vessel.id) { check, method in
                    selectedVesselForAdd = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        if method == .invite { inviteCheck = check } else { activeCheck = check }
                    }
                }
            }
        }
    }

    // MARK: - Expiry Banner

    @ViewBuilder
    private var expiryBanner: some View {
        let totalExpiring = vm.expiringChecks.count + vm.allExpiringDocuments.count
        let totalExpired = vm.expiredChecks.count + vm.allExpiredDocuments.count
        if totalExpiring > 0 || totalExpired > 0 {
            NavigationLink {
                ExpiryDetailView(vm: vm)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 13))
                    Text(totalExpired > 0 ? "\(totalExpired) expired" : "\(totalExpiring) expiring soon")
                        .font(Typo.meta).fontWeight(.medium)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).opacity(0.4)
                }
                .foregroundStyle(Color.review)
                .padding(.horizontal, 20).padding(.vertical, 10)
                .background(Color.review.opacity(0.06))
            }
        }
    }

    // MARK: - Floating Add Button

    @State private var selectedVesselForAdd: Vessel?

    private var addButton: some View {
        Menu {
            Button { showAddVessel = true } label: { Label("Add Vessel", systemImage: "ferry") }
            if !vm.vessels.isEmpty {
                Divider()
                // Add person — pick vessel first
                ForEach(vm.vessels) { vessel in
                    Button { selectedVesselForAdd = vessel } label: {
                        Label("Add to \(vessel.name)", systemImage: "person.badge.plus")
                    }
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.surface)
                .frame(width: 56, height: 56)
                .background(Color.primary)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
        }
        .padding(.trailing, 20).padding(.bottom, 20)
    }

    // MARK: - Vessels List

    private var vesselsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(filteredVessels) { vessel in
                    let seafarers = vm.seafarersForVessel(vessel.id)
                    let compliance = vm.complianceChecksForVessel(vessel.id)
                    let crewPassed = seafarers.filter { $0.status == .passed }.count
                    let compPassed = compliance.filter { $0.status == .passed }.count

                    NavigationLink { VesselDetailView(vm: vm, vessel: vessel) } label: {
                        VStack(alignment: .leading, spacing: 12) {
                            // Vessel name — bold, prominent
                            HStack {
                                Text(vessel.name).font(.system(size: 18, weight: .bold)).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.quaternary)
                            }

                            // Type + flag
                            HStack(spacing: 10) {
                                if let vt = vessel.vesselType {
                                    Label(vt.rawValue, systemImage: vt.icon).font(Typo.meta).foregroundStyle(.secondary)
                                }
                                if !vessel.flagState.isEmpty {
                                    Text(vessel.flagState).font(Typo.meta).foregroundStyle(.tertiary)
                                }
                            }

                            // Stats row — clear separation
                            if !seafarers.isEmpty || !compliance.isEmpty {
                                HStack(spacing: 20) {
                                    if !seafarers.isEmpty {
                                        miniStat("\(crewPassed)/\(seafarers.count)", "Crew", crewPassed == seafarers.count ? .clear_ : .secondary)
                                    }
                                    if !compliance.isEmpty {
                                        miniStat("\(compPassed)/\(compliance.count)", "Compliance", compPassed == compliance.count ? .clear_ : .secondary)
                                    }
                                    Spacer()
                                }
                                .padding(.top, 2)
                            } else {
                                Text("Ready for crew").font(Typo.meta).foregroundStyle(.quaternary).padding(.top, 2)
                            }
                        }
                        .padding(18)
                        .background(Color.surfaceMuted.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.primary.opacity(0.06), lineWidth: 0.5))
                    }
                }

                if vm.vessels.isEmpty {
                    VStack(spacing: 16) {
                        Spacer(minLength: 80)
                        Image(systemName: "ferry").font(.system(size: 48)).foregroundStyle(.quaternary)
                        Text("No vessels yet").font(Typo.context).foregroundStyle(.secondary)
                        Text("Tap + to add your first vessel").font(Typo.meta).foregroundStyle(.quaternary)
                            .padding(.bottom, 4)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 80)
        }
    }

    // MARK: - All Checks List

    private var allChecksList: some View {
        Group {
            if filtered.isEmpty {
                VStack(spacing: 14) {
                    Spacer(minLength: 60)
                    Image(systemName: "person.crop.rectangle.stack").font(.system(size: 44)).foregroundStyle(.quaternary)
                    Text(vm.checks.isEmpty ? "No checks yet" : "No results").font(Typo.context).foregroundStyle(.secondary)
                    Text(vm.checks.isEmpty ? "Tap + to add a person" : "Try a different search").font(Typo.meta).foregroundStyle(.quaternary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(filtered) { check in
                        Button { activeCheck = check } label: {
                            HStack(spacing: 12) {
                                avatarView(check, size: 36)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(check.displayName).font(Typo.body).lineLimit(1)
                                    HStack(spacing: 6) {
                                        if check.entityType != .seafarer {
                                            Text(check.entityType.rawValue).font(Typo.meta).foregroundStyle(.secondary)
                                        } else if let rank = check.crewRank {
                                            Text(rank.rawValue).font(Typo.meta).foregroundStyle(.secondary)
                                        }
                                        if let vid = check.vesselId, let v = vm.vessels.first(where: { $0.id == vid }) {
                                            Text(v.name).font(Typo.meta).foregroundStyle(.tertiary)
                                        }
                                    }
                                }
                                Spacer()
                                StatusBadge(status: check.status)
                            }
                            .padding(.vertical, 3)
                        }
                        .contextMenu {
                            // Assign to vessel
                            if !vm.vessels.isEmpty {
                                Menu {
                                    ForEach(vm.vessels) { vessel in
                                        Button(vessel.name) { vm.assignCheckToVessel(checkId: check.id, vesselId: vessel.id) }
                                    }
                                } label: { Label("Assign to Vessel", systemImage: "ferry") }
                            }
                            if check.vesselId != nil {
                                Button { vm.unassignCheckFromVessel(checkId: check.id) } label: { Label("Remove from Vessel", systemImage: "minus.circle") }
                            }
                            Divider()
                            Button(role: .destructive) { vm.deleteCheckById(check.id) } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { filtered[$0].id }
                        let real = IndexSet(ids.compactMap { id in vm.checks.firstIndex(where: { $0.id == id }) })
                        vm.deleteCheck(at: real)
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Components

    private func miniStat(_ value: String, _ label: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Text(value).font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(color)
            Text(label).font(Typo.meta).foregroundStyle(.secondary)
        }
    }

    private func avatarView(_ check: KYCCheck, size: CGFloat) -> some View {
        Group {
            if let photo = check.profilePhoto, let data = vm.loadDocumentImage(filename: photo), let img = UIImage(data: data) {
                Image(uiImage: img).resizable().scaledToFill()
                    .frame(width: size, height: size).clipShape(Circle())
            } else {
                Circle().fill(Color.surfaceMuted).frame(width: size, height: size)
                    .overlay { Text(String(check.customerName.prefix(1)).uppercased()).font(.system(size: size * 0.38, weight: .medium)).foregroundStyle(.secondary) }
            }
        }
    }

    // MARK: - Helpers

    private var filtered: [KYCCheck] {
        searchText.isEmpty ? vm.checks : vm.checks.filter {
            $0.customerName.localizedCaseInsensitiveContains(searchText) ||
            ($0.documentNumber ?? "").localizedCaseInsensitiveContains(searchText) ||
            ($0.crewRank?.rawValue ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    private var filteredVessels: [Vessel] {
        searchText.isEmpty ? vm.vessels : vm.vessels.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.imoNumber.localizedCaseInsensitiveContains(searchText)
        }
    }
}

// MARK: - Quick Add Person (from home, no vessel context)

// MARK: - Expiry Detail

struct ExpiryDetailView: View {
    @ObservedObject var vm: KYCViewModel
    @State private var activeCheck: KYCCheck?

    var body: some View {
        List {
            if !vm.expiredChecks.isEmpty {
                Section("Expired — ID Documents") {
                    ForEach(vm.expiredChecks) { check in idRow(check, color: .flagged) }
                }
            }
            if !vm.expiringChecks.isEmpty {
                Section("Expiring Soon — ID Documents") {
                    ForEach(vm.expiringChecks) { check in idRow(check, color: .review) }
                }
            }
            if !vm.allExpiredDocuments.isEmpty {
                Section("Expired — Certificates") {
                    ForEach(vm.allExpiredDocuments, id: \.document.id) { item in docRow(item.check, item.document, color: .flagged) }
                }
            }
            if !vm.allExpiringDocuments.isEmpty {
                Section("Expiring Soon — Certificates") {
                    ForEach(vm.allExpiringDocuments, id: \.document.id) { item in docRow(item.check, item.document, color: .review) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Document Expiry")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $activeCheck) { VerificationSheet(vm: vm, check: $0) }
    }

    private func idRow(_ check: KYCCheck, color: Color) -> some View {
        Button { activeCheck = check } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(check.displayName).font(Typo.body)
                    Text(check.documentType ?? "Passport").font(Typo.meta).foregroundStyle(.secondary)
                }
                Spacer()
                if let exp = check.expiryDate { Text(exp).font(Typo.meta).foregroundStyle(color) }
            }
            .padding(.vertical, 2)
        }
    }

    private func docRow(_ check: KYCCheck, _ doc: CrewDocument, color: Color) -> some View {
        Button { activeCheck = check } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(check.displayName).font(Typo.body)
                    Text(doc.type.displayName).font(Typo.meta).foregroundStyle(.secondary)
                }
                Spacer()
                if let exp = doc.expiryDate { Text(exp.formatted(date: .abbreviated, time: .omitted)).font(Typo.meta).foregroundStyle(color) }
            }
            .padding(.vertical, 2)
        }
    }
}
