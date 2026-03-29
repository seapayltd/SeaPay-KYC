//
//  HomeView.swift
//  OceanCheck
//
//  Home: vessel cards with hero photos, crew list, expiry alerts.
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
    @State private var showBatchImport = false
    @State private var showCSVExport = false
    @State private var csvURL: URL?
    @State private var searchText = ""
    @State private var tab = 0
    @State private var allFilter = 0 // 0=All, 1=Flagged, 2=Expiring, 3=Pending

    // iPad sidebar
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selectedVesselId: String?
    @State private var sidebarSelection: SidebarItem? = .vessels
    enum SidebarItem: Hashable { case vessels, people, settings }

    var body: some View {
        if sizeClass == .regular {
            iPadLayout
        } else {
            iPhoneLayout
        }
    }

    // MARK: - iPad Split View

    private var iPadLayout: some View {
        NavigationSplitView {
            List(selection: $sidebarSelection) {
                Section {
                    Label("Vessels", systemImage: "ferry").tag(SidebarItem.vessels)
                    Label("People", systemImage: "person.3").tag(SidebarItem.people)
                }
                Section {
                    Label("Settings", systemImage: "gearshape").tag(SidebarItem.settings)
                }

                if !vm.vessels.isEmpty {
                    Section("Vessels") {
                        ForEach(vm.vessels) { vessel in
                            NavigationLink(value: vessel.id) {
                                HStack(spacing: 10) {
                                    Image(systemName: vessel.vesselType?.icon ?? "ferry")
                                        .font(.system(size: 13)).foregroundStyle(.secondary).frame(width: 20)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(vessel.name).font(Typo.body).fontWeight(.medium)
                                        Text("\(vm.checksForVessel(vessel.id).count) crew").font(Typo.meta).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("OceanCheck")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { showAddVessel = true } label: { Label("Add Vessel", systemImage: "ferry") }
                        Button { showBatchInvite = true } label: { Label("Batch Invite", systemImage: "person.2.badge.plus") }
                        Button { showBatchImport = true } label: { Label("Import CSV", systemImage: "square.and.arrow.down") }
                        if !vm.checks.isEmpty {
                            Divider()
                            Button { csvURL = vm.generateCSV(vesselId: nil); if csvURL != nil { showCSVExport = true } } label: { Label("Export CSV", systemImage: "tablecells") }
                            Button { csvURL = vm.generateXLSX(vesselId: nil); if csvURL != nil { showCSVExport = true } } label: { Label("Export XLSX", systemImage: "doc.richtext") }
                        }
                    } label: {
                        Image(systemName: "plus.circle").font(.system(size: 16))
                    }
                }
            }
        } detail: {
            NavigationStack {
                Group {
                    switch sidebarSelection {
                    case .vessels:
                        iPadVesselContent
                    case .people:
                        allChecksList.refreshable { await vm.refreshPendingSessions() }
                    case .settings:
                        SettingsSheet(vm: vm, appState: appState)
                    case .none:
                        iPadVesselContent
                    }
                }
                .background(Color.surface.ignoresSafeArea())
            }
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search")
        .sheet(item: $activeCheck) { VerificationSheet(vm: vm, check: $0) }
        .sheet(item: $inviteCheck) { InviteSheet(vm: vm, check: $0) }
        .sheet(isPresented: $showAddVessel) { VesselSheet(vm: vm) }
        .sheet(isPresented: $showBatchInvite) { BatchInviteSheet(vm: vm) }
        .sheet(isPresented: $showBatchImport) { BatchImportSheet(vm: vm) }
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

    @ViewBuilder
    private var iPadVesselContent: some View {
        if vm.vessels.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "ferry").font(.system(size: 48)).foregroundStyle(.quaternary)
                Text("No vessels yet").font(Typo.context).foregroundStyle(.secondary)
                Button { showAddVessel = true } label: { Text("Add Vessel") }.buttonStyle(PrimaryButtonStyle()).frame(width: 200)
            }
        } else {
            vesselsList.refreshable { await vm.refreshPendingSessions() }
        }
    }

    // MARK: - iPhone Stack

    private var iPhoneLayout: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    // Offline + queue
                    if !vm.isOnline {
                        HStack(spacing: 8) {
                            Image(systemName: "wifi.slash").font(.system(size: 11))
                            Text("Offline").font(Typo.meta)
                            if !vm.offlineQueue.isEmpty {
                                Text("\u{2022} \(vm.offlineQueue.count) queued").font(Typo.meta).opacity(0.8)
                            }
                        }
                        .foregroundStyle(.white).frame(maxWidth: .infinity)
                        .padding(.vertical, 6).background(Color.secondary.opacity(0.7))
                        .transition(.move(edge: .top).combined(with: .opacity))
                    } else if vm.offlineQueue.isProcessing {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.mini).tint(.white)
                            Text("Syncing \(vm.offlineQueue.count) queued actions...").font(Typo.meta)
                        }
                        .foregroundStyle(.white).frame(maxWidth: .infinity)
                        .padding(.vertical, 6).background(Color.clear_.opacity(0.7))
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // Expiry alert
                    expiryBanner

                    // Content
                    if tab == 0 {
                        vesselsList.refreshable { await vm.refreshPendingSessions() }
                    } else {
                        allChecksList.refreshable { await vm.refreshPendingSessions() }
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxHeight: .infinity)
                .background(Color.surface.ignoresSafeArea())

                // Floating add button
                addButton
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 24) {
                        tabLabel("Vessels", index: 0)
                        tabLabel("People", index: 1)
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape").font(.system(size: 14)).foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { showBatchInvite = true } label: { Label("Batch Invite", systemImage: "person.2.badge.plus") }
                        Button { showBatchImport = true } label: { Label("Import Crew CSV", systemImage: "square.and.arrow.down") }
                        if !vm.checks.isEmpty {
                            Button { csvURL = vm.generateCSV(vesselId: nil); if csvURL != nil { showCSVExport = true } } label: { Label("Export CSV", systemImage: "tablecells") }
                            Button { csvURL = vm.generateXLSX(vesselId: nil); if csvURL != nil { showCSVExport = true } } label: { Label("Export XLSX", systemImage: "doc.richtext") }
                        }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 14)).foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("More actions")
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search crew or vessels")
            .sheet(item: $activeCheck) { VerificationSheet(vm: vm, check: $0) }
            .sheet(item: $inviteCheck) { InviteSheet(vm: vm, check: $0) }
            .sheet(isPresented: $showSettings) { SettingsSheet(vm: vm, appState: appState) }
            .sheet(isPresented: $showAddVessel) { VesselSheet(vm: vm) }
            .sheet(isPresented: $showBatchInvite) { BatchInviteSheet(vm: vm) }
            .sheet(isPresented: $showBatchImport) { BatchImportSheet(vm: vm) }
            .sheet(isPresented: $showCSVExport) { if let url = csvURL { ActivityView(items: [url]) } }
            .sheet(item: $selectedVesselForAdd) { vessel in
                AddCrewSheet(vm: vm, vesselId: vessel.id) { check, method in
                    selectedVesselForAdd = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        if method == .invite { inviteCheck = check } else { activeCheck = check }
                    }
                }
            }
            // Keyboard shortcuts (Mac + iPad with keyboard)
            .onAddVessel { showAddVessel = true }
            .onOpenSettings { showSettings = true }
            .onExport { csvURL = vm.generateCSV(vesselId: nil); if csvURL != nil { showCSVExport = true } }
            .onRefresh { Task { await vm.refreshPendingSessions() } }
        }
    }

    // MARK: - Expiry Banner

    @ViewBuilder
    private var expiryBanner: some View {
        let totalExpiring = vm.expiringChecks.count + vm.allExpiringDocuments.count + vm.expiringVesselDocuments.count
        let totalExpired = vm.expiredChecks.count + vm.allExpiredDocuments.count + vm.expiredVesselDocuments.count
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
            .accessibilityLabel(totalExpired > 0 ? "\(totalExpired) expired documents, tap for details" : "\(totalExpiring) documents expiring soon, tap for details")
        }
    }

    // MARK: - Floating Add Button

    @State private var selectedVesselForAdd: Vessel?

    private var addButton: some View {
        Menu {
            Button { showAddVessel = true } label: { Label("Add Vessel", systemImage: "ferry") }
            if !vm.vessels.isEmpty {
                Divider()
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
        .accessibilityLabel("Add vessel or crew")
    }

    // MARK: - Vessels List

    private var vesselsList: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                ForEach(filteredVessels) { vessel in
                    let seafarers = vm.seafarersForVessel(vessel.id)
                    let compliance = vm.complianceChecksForVessel(vessel.id)
                    let crewPassed = seafarers.filter { $0.status == .passed }.count
                    let compPassed = compliance.filter { $0.status == .passed }.count
                    let hasFlag = seafarers.contains { $0.status == .failed } || compliance.contains { $0.status == .failed }
                    let hasWarning = !hasFlag && (seafarers.contains { $0.status == .requiresReview } || compliance.contains { $0.status == .requiresReview })

                    NavigationLink { VesselDetailView(vm: vm, vessel: vessel) } label: {
                        vesselCard(
                            vessel: vessel,
                            seafarers: seafarers, compliance: compliance,
                            crewPassed: crewPassed, compPassed: compPassed,
                            hasFlag: hasFlag, hasWarning: hasWarning
                        )
                    }
                    .accessibilityLabel("\(vessel.name), \(seafarers.count) crew, \(crewPassed) verified\(hasFlag ? ", has issues" : hasWarning ? ", needs review" : "")")
                }

                if vm.vessels.isEmpty { emptyVesselsState }
            }
            .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 80)
        }
    }

    // MARK: - Vessel Card

    private func vesselCard(vessel: Vessel, seafarers: [KYCCheck], compliance: [KYCCheck], crewPassed: Int, compPassed: Int, hasFlag: Bool, hasWarning: Bool) -> some View {
        let photoData = vessel.photoFilename.flatMap { vm.loadDocumentImage(filename: $0) }
        return VStack(spacing: 0) {
            // Hero image area
            ZStack(alignment: .topTrailing) {
                HeroImageView(
                    imageData: photoData,
                    fallbackIcon: vessel.vesselType?.icon ?? "ferry",
                    overlayTitle: photoData != nil ? vessel.name : nil,
                    aspectRatio: 16.0 / 9.0
                )

                // Status dot
                if hasFlag || hasWarning {
                    Circle().fill(hasFlag ? Color.flagged : Color.review)
                        .frame(width: 10, height: 10)
                        .padding(12)
                }
            }

            // Info below image
            VStack(alignment: .leading, spacing: 10) {
                // Name (only if no photo — if photo, it's overlaid)
                if photoData == nil {
                    HStack {
                        Text(vessel.name).font(.system(size: 18, weight: .bold)).foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.quaternary)
                    }
                }

                // Type + flag
                HStack(spacing: 8) {
                    if let vt = vessel.vesselType {
                        Label(vt.rawValue, systemImage: vt.icon).font(Typo.meta).foregroundStyle(.secondary)
                    }
                    if !vessel.flagState.isEmpty {
                        Text("·").foregroundStyle(.quaternary)
                        Text(vessel.flagState).font(Typo.meta).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    if vessel.photoFilename != nil {
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.quaternary)
                    }
                }

                // Stats
                if !seafarers.isEmpty || !compliance.isEmpty {
                    Divider().opacity(0.3)
                    HStack(spacing: 20) {
                        if !seafarers.isEmpty {
                            miniStat("\(crewPassed)/\(seafarers.count)", "Crew", crewPassed == seafarers.count ? .clear_ : .review)
                        }
                        if !compliance.isEmpty {
                            miniStat("\(compPassed)/\(compliance.count)", "Compliance", compPassed == compliance.count ? .clear_ : .review)
                        }
                        Spacer()
                    }

                    // Status summary sentence
                    let flaggedCount = seafarers.filter { $0.status == .failed }.count + compliance.filter { $0.status == .failed }.count
                    let reviewCount = seafarers.filter { $0.status == .requiresReview }.count
                    if flaggedCount > 0 || reviewCount > 0 {
                        Text(statusSummary(flagged: flaggedCount, review: reviewCount))
                            .font(Typo.meta).foregroundStyle(flaggedCount > 0 ? Color.flagged : Color.review)
                    }
                } else {
                    Text("Ready for crew").font(Typo.meta).foregroundStyle(.quaternary)
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 14)
        }
        .background(cardBackground(hasFlag: hasFlag, hasWarning: hasWarning))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.primary.opacity(0.06), lineWidth: 0.5))
    }

    // MARK: - Empty Vessels State

    private var emptyVesselsState: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 60)

            Circle().fill(Color.surfaceMuted).frame(width: 120, height: 120)
                .overlay {
                    Image(systemName: "ferry").font(.system(size: 48)).foregroundStyle(.quaternary)
                }

            Text("No vessels yet").font(Typo.context).foregroundStyle(.secondary)
            Text("Add your first vessel to get started").font(Typo.meta).foregroundStyle(.quaternary)

            Button { showAddVessel = true } label: {
                Text("Add Vessel")
            }
            .buttonStyle(SecondaryButtonStyle())
            .padding(.horizontal, 80)
            .padding(.top, 4)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - All Checks List

    private var allChecksList: some View {
        VStack(spacing: 0) {
            // Filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(filterOptions.enumerated()), id: \.offset) { i, title in
                        Button { withAnimation(.smooth(duration: 0.2)) { allFilter = i } } label: {
                            FilterChip(title: title, isSelected: allFilter == i)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 8)
            }

            if filteredChecks.isEmpty {
                VStack(spacing: 14) {
                    Spacer(minLength: 60)
                    Image(systemName: "person.crop.rectangle.stack").font(.system(size: 44)).foregroundStyle(.quaternary)
                    Text(vm.checks.isEmpty ? "No checks yet" : "No results").font(Typo.context).foregroundStyle(.secondary)
                    Text(vm.checks.isEmpty ? "Tap + to add a person" : "Try a different filter").font(Typo.meta).foregroundStyle(.quaternary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List {
                    // Group by vessel
                    ForEach(groupedChecks, id: \.0) { vesselName, checks in
                        Section(vesselName) {
                            ForEach(checks) { check in
                                Button { activeCheck = check } label: {
                                    checkRow(check)
                                }
                                .contextMenu {
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
                                let ids = offsets.map { checks[$0].id }
                                for id in ids { vm.deleteCheckById(id) }
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private let filterOptions = ["All", "Flagged", "Expiring", "Pending"]

    private var filteredChecks: [KYCCheck] {
        let base: [KYCCheck]
        switch allFilter {
        case 1: base = vm.checks.filter { $0.status == .failed || $0.status == .requiresReview }
        case 2: base = vm.checks.filter { check in
            if let exp = check.expiryDate, let date = DateFormatter.shortDate.date(from: exp) {
                return date < Calendar.current.date(byAdding: .day, value: 90, to: Date())!
            }
            return false
        }
        case 3: base = vm.checks.filter { $0.status == .pending || $0.status == .inProgress }
        default: base = vm.checks
        }
        guard !searchText.isEmpty else { return base }
        return base.filter { check in
            check.customerName.localizedCaseInsensitiveContains(searchText) ||
            (check.documentNumber ?? "").localizedCaseInsensitiveContains(searchText) ||
            (check.crewRank?.rawValue ?? "").localizedCaseInsensitiveContains(searchText) ||
            (check.vesselId.flatMap { vid in vm.vessels.first(where: { $0.id == vid })?.name } ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    private var groupedChecks: [(String, [KYCCheck])] {
        var groups: [String: [KYCCheck]] = [:]
        for check in filteredChecks {
            let key: String
            if let vid = check.vesselId, let v = vm.vessels.first(where: { $0.id == vid }) {
                key = v.name
            } else {
                key = "Unassigned"
            }
            groups[key, default: []].append(check)
        }
        // Sort: vessel names alphabetically, "Unassigned" last
        return groups.sorted { a, b in
            if a.key == "Unassigned" { return false }
            if b.key == "Unassigned" { return true }
            return a.key < b.key
        }
    }

    // MARK: - Components

    private func checkRow(_ check: KYCCheck) -> some View {
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
                }
            }
            Spacer()
            StatusBadge(status: check.status)
        }
        .padding(.vertical, 3)
    }

    private func tabLabel(_ title: String, index: Int) -> some View {
        Button { withAnimation(.smooth(duration: 0.2)) { tab = index } } label: {
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: tab == index ? .semibold : .regular))
                    .foregroundStyle(tab == index ? .primary : .secondary)
                RoundedRectangle(cornerRadius: 1)
                    .fill(tab == index ? Color.primary : Color.clear)
                    .frame(height: 2).frame(width: 30)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) tab\(tab == index ? ", selected" : "")")
        .accessibilityAddTraits(tab == index ? .isSelected : [])
    }

    private func cardBackground(hasFlag: Bool, hasWarning: Bool) -> Color {
        if hasFlag { return Color.flagged.opacity(0.04) }
        if hasWarning { return Color.review.opacity(0.04) }
        return Color.surfaceMuted.opacity(0.4)
    }

    private func statusSummary(flagged: Int, review: Int) -> String {
        var parts: [String] = []
        if flagged > 0 { parts.append("\(flagged) flagged") }
        if review > 0 { parts.append("\(review) review") }
        return parts.joined(separator: ", ")
    }

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

    private var filteredVessels: [Vessel] {
        searchText.isEmpty ? vm.vessels : vm.vessels.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.imoNumber.localizedCaseInsensitiveContains(searchText)
        }
    }
}

// MARK: - Date Formatter Helper

private extension DateFormatter {
    static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        return f
    }()
}

// MARK: - Expiry Detail

struct ExpiryDetailView: View {
    @ObservedObject var vm: KYCViewModel
    @State private var activeCheck: KYCCheck?
    @State private var selectedVesselDoc: (vesselId: String, doc: CrewDocument)?

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
                Section("Expiring Soon — Crew Certificates") {
                    ForEach(vm.allExpiringDocuments, id: \.document.id) { item in docRow(item.check, item.document, color: .review) }
                }
            }

            // Vessel certificate expirations
            if !vm.expiredVesselDocuments.isEmpty {
                Section("Expired — Vessel Certificates") {
                    ForEach(vm.expiredVesselDocuments, id: \.document.id) { item in vesselDocRow(item.vessel, item.document, color: .flagged) }
                }
            }
            if !vm.expiringVesselDocuments.isEmpty {
                Section("Expiring Soon — Vessel Certificates") {
                    ForEach(vm.expiringVesselDocuments, id: \.document.id) { item in vesselDocRow(item.vessel, item.document, color: .review) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Document Expiry")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $activeCheck) { VerificationSheet(vm: vm, check: $0) }
        .sheet(isPresented: Binding(
            get: { selectedVesselDoc != nil },
            set: { if !$0 { selectedVesselDoc = nil } }
        )) {
            if let sel = selectedVesselDoc {
                VesselDocDetailSheet(vm: vm, vesselId: sel.vesselId, document: sel.doc)
            }
        }
    }

    private func vesselDocRow(_ vessel: Vessel, _ doc: CrewDocument, color: Color) -> some View {
        Button {
            selectedVesselDoc = (vesselId: vessel.id, doc: doc)
        } label: {
            HStack {
                RoundedRectangle(cornerRadius: 1.5).fill(color)
                    .frame(width: 3, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(vessel.name).font(Typo.body)
                    Text(doc.displayName).font(Typo.meta).foregroundStyle(.secondary)
                }
                Spacer()
                if let exp = doc.expiryDate { Text(exp.formatted(date: .abbreviated, time: .omitted)).font(Typo.meta).foregroundStyle(color) }
                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(.quaternary)
            }
            .padding(.vertical, 2)
        }
    }

    private func idRow(_ check: KYCCheck, color: Color) -> some View {
        Button { activeCheck = check } label: {
            HStack {
                RoundedRectangle(cornerRadius: 1.5).fill(color)
                    .frame(width: 3, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(check.displayName).font(Typo.body)
                    Text(check.documentType ?? "Passport").font(Typo.meta).foregroundStyle(.secondary)
                }
                Spacer()
                if let exp = check.expiryDate { Text(exp).font(Typo.meta).foregroundStyle(color) }
                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(.quaternary)
            }
            .padding(.vertical, 2)
        }
    }

    private func docRow(_ check: KYCCheck, _ doc: CrewDocument, color: Color) -> some View {
        Button { activeCheck = check } label: {
            HStack {
                RoundedRectangle(cornerRadius: 1.5).fill(color)
                    .frame(width: 3, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(check.displayName).font(Typo.body)
                    Text(doc.type.displayName).font(Typo.meta).foregroundStyle(.secondary)
                }
                Spacer()
                if let exp = doc.expiryDate { Text(exp.formatted(date: .abbreviated, time: .omitted)).font(Typo.meta).foregroundStyle(color) }
                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(.quaternary)
            }
            .padding(.vertical, 2)
        }
    }
}
