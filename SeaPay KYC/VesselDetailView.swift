//
//  VesselDetailView.swift
//  OceanCheck
//
//  Vessel detail with hero photo, stats progress bars, crew, compliance.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import PDFKit

struct VesselDetailView: View {
    @ObservedObject var vm: KYCViewModel
    let vessel: Vessel
    @State private var activeCheck: KYCCheck?
    @State private var inviteCheck: KYCCheck?
    @State private var exportPDFPath: NavigationPath = NavigationPath()
    @State private var showExportPDF = false
    @State private var showExportCSV = false
    @State private var transferCheck: KYCCheck?
    @State private var addVesselDoc = false
    @State private var showAddCrew = false
    @State private var selectedVesselDoc: CrewDocument?
    @State private var showAssignExisting = false
    @State private var showAddCompliance = false
    @State private var showOwnershipFlow = false
    @State private var editingPerson: KYCCheck?
    @State private var editName = ""
    @State private var showEditVessel = false
    @State private var showDeleteConfirm = false
    @State private var checkToDelete: KYCCheck?
    @State private var showExportCrewList = false
    @State private var showShareVesselData = false
    @State private var showOwnerShare = false
    @State private var showPhotoPicker = false
    @State private var selectedPhoto: PhotosPickerItem?

    private var v: Vessel { vm.vessels.first(where: { $0.id == vessel.id }) ?? vessel }
    private var crew: [KYCCheck] { vm.checksForVessel(vessel.id) }
    private var seafarerCrew: [KYCCheck] { crew.filter { $0.entityType.category == .crew }.sorted { statusPriority($0.status) < statusPriority($1.status) } }
    private var shoreBasedPersonnel: [KYCCheck] { crew.filter { $0.entityType.category == .shoreBased }.sorted { statusPriority($0.status) < statusPriority($1.status) } }
    private var complianceEntities: [KYCCheck] { crew.filter { $0.entityType.category == .ownership }.sorted { statusPriority($0.status) < statusPriority($1.status) } }

    private func statusPriority(_ status: KYCCheck.CheckStatus) -> Int {
        switch status {
        case .failed: return 0
        case .requiresReview: return 1
        case .pending: return 2
        case .inProgress: return 3
        case .incomplete: return 4
        case .passed: return 5
        }
    }
    private var crewPassedCount: Int { seafarerCrew.filter { $0.status == .passed }.count }
    private var compliancePassedCount: Int { complianceEntities.filter { $0.status == .passed }.count }
    private var vesselDocs: [CrewDocument] { v.documents ?? [] }
    private var unassigned: [KYCCheck] { vm.unassignedChecks }

    private var vesselPhotoData: Data? {
        v.photoFilename.flatMap { vm.loadDocumentImage(filename: $0) }
    }

    // Cached once per render — used by stats + certificateSections
    private var certReadinessCache: (completed: Int, total: Int, expiring: Int, expired: Int) {
        vm.vesselDocReadiness(for: v)
    }

    var body: some View {
        List {
            // Hero header with photo
            Section {
                VStack(spacing: 0) {
                    // Photo or fallback
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        ZStack(alignment: .bottomLeading) {
                            if let data = vesselPhotoData, let img = UIImage(data: data) {
                                Image(uiImage: img).resizable().scaledToFill()
                                    .frame(height: 200).frame(maxWidth: .infinity)
                                    .clipped()
                                    .overlay(alignment: .bottom) {
                                        LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .center, endPoint: .bottom)
                                            .frame(height: 100)
                                    }
                                // Name overlaid on photo
                                Text(v.name).font(Typo.hero).foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                                    .padding(.horizontal, 18).padding(.bottom, 14)
                            } else {
                                VStack(spacing: 12) {
                                    Image(systemName: v.vesselType?.icon ?? "ferry")
                                        .font(.system(size: 40)).foregroundStyle(.quaternary)
                                    Text("Tap to add photo").font(Typo.meta).foregroundStyle(.tertiary)
                                }
                                .frame(height: 160).frame(maxWidth: .infinity)
                                .background(Color.surfaceMuted)
                            }
                        }
                    }
                    .onChange(of: selectedPhoto) { _, item in
                        Task { await loadVesselPhoto(item) }
                    }

                    // Metadata pills
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            if let vt = v.vesselType {
                                MetadataPill(icon: vt.icon, text: vt.rawValue)
                            }
                            if !v.imoNumber.isEmpty {
                                MetadataPill(icon: "number", text: "IMO \(v.imoNumber)")
                            }
                            if !v.flagState.isEmpty {
                                MetadataPill(icon: "flag", text: v.flagState)
                            }
                            if !v.portOfRegistry.isEmpty {
                                MetadataPill(icon: "mappin", text: v.portOfRegistry)
                            }
                            if !v.registeredLength.isEmpty {
                                MetadataPill(icon: "ruler", text: "RL \(v.registeredLength)m")
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                    }

                    // Quick action buttons
                    HStack(spacing: 0) {
                        quickAction("person.badge.plus", "Add Crew") { showAddCrew = true }
                        quickAction("doc.badge.plus", "Add Cert") { addVesselDoc = true }
                        quickAction("square.and.arrow.up", "Share") { showShareVesselData = true }
                        quickAction("pencil", "Edit") { showEditVessel = true }
                    }
                    .padding(.horizontal, 8).padding(.bottom, 10)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            // Stats with progress bars
            Section {
                HStack(spacing: 0) {
                    statWithBar("Certs", certReadinessCache.completed, certReadinessCache.total)
                    if !crew.isEmpty {
                        statWithBar("Crew", crewPassedCount, seafarerCrew.count)
                        let crewDocs = seafarerCrew.flatMap { $0.documents ?? [] }.filter { !$0.isArchived }
                        let crewDocsValid = crewDocs.filter { $0.status == .valid }.count
                        if !crewDocs.isEmpty {
                            statWithBar("Docs", crewDocsValid, crewDocs.count)
                        }
                    }
                    if !complianceEntities.isEmpty {
                        statWithBar("Compliance", compliancePassedCount, complianceEntities.count)
                    }
                }
            }

            // GT warning + Certificates
            certificateSections

            // Crew
            Section {
                ForEach(seafarerCrew) { check in
                    Button { activeCheck = check } label: { crewRow(check) }
                        .contextMenu { personContextMenu(check) }
                        .swipeActions(edge: .leading) {
                            if vm.vessels.count > 1 {
                                Button { transferCheck = check } label: { Label("Move", systemImage: "arrow.right.arrow.left") }.tint(.primary)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { checkToDelete = check } label: { Label("Delete", systemImage: "trash") }
                            Button { vm.unassignCheckFromVessel(checkId: check.id) } label: { Label("Unassign", systemImage: "minus.circle") }.tint(.review)
                        }
                }

                Button { showAddCrew = true } label: {
                    Label("Add crew member", systemImage: "person.badge.plus").font(Typo.body).foregroundStyle(.primary)
                }
                if !unassigned.isEmpty {
                    Button { showAssignExisting = true } label: {
                        Label("Assign unassigned (\(unassigned.count))", systemImage: "person.2.gobackward").font(Typo.body).foregroundStyle(.secondary)
                    }
                }
            } header: { Text("Crew (\(seafarerCrew.count))") }

            // Shore-based personnel
            if !shoreBasedPersonnel.isEmpty {
                Section {
                    ForEach(shoreBasedPersonnel) { check in
                        Button { activeCheck = check } label: { crewRow(check) }
                            .contextMenu { personContextMenu(check) }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { checkToDelete = check } label: { Label("Delete", systemImage: "trash") }
                                Button { vm.unassignCheckFromVessel(checkId: check.id) } label: { Label("Unassign", systemImage: "minus.circle") }.tint(.review)
                            }
                    }
                } header: { Text("Shore-Based (\(shoreBasedPersonnel.count))") }
            }

            // Compliance (UBO verification, owners, management)
            Section {
                if let os = v.ownershipStructure {
                    HStack(spacing: 12) {
                        let icon = os.resolvedEntityType == .trust ? "shield.checkered" : os.isDirectOwnership ? "person" : "building.2"
                        Image(systemName: icon).font(Typo.body).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(os.isDirectOwnership ? "Direct Ownership" : os.spv?.name ?? os.resolvedEntityType.rawValue).font(Typo.body)
                                if os.resolvedEntityType != .company {
                                    MetadataPill(icon: nil, text: os.resolvedEntityType.rawValue)
                                }
                            }
                            let uboCount = os.shareholders.filter(\.isUBO).count
                            let trusteeCount = (os.trustees ?? []).count
                            if os.resolvedEntityType == .trust {
                                Text("\(trusteeCount) trustee\(trusteeCount == 1 ? "" : "s") \u{2022} \((os.beneficiaries ?? []).count) beneficiar\((os.beneficiaries ?? []).count == 1 ? "y" : "ies")").font(Typo.meta).foregroundStyle(.secondary)
                            } else {
                                Text("\(uboCount) UBO\(uboCount == 1 ? "" : "s") \u{2022} \(os.directors.count) director\(os.directors.count == 1 ? "" : "s")").font(Typo.meta).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if os.uboReportGenerated { Image(systemName: "checkmark.seal.fill").foregroundStyle(Color.clear_) }
                    }
                }

                ForEach(complianceEntities) { check in
                    Button { activeCheck = check } label: { crewRow(check) }
                        .contextMenu { personContextMenu(check) }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { checkToDelete = check } label: { Label("Delete", systemImage: "trash") }
                            Button { vm.unassignCheckFromVessel(checkId: check.id) } label: { Label("Unassign", systemImage: "minus.circle") }.tint(.review)
                        }
                }

                Button { showOwnershipFlow = true } label: {
                    Label(v.ownershipStructure == nil ? "UBO Verification" : "Update UBO Verification", systemImage: "person.badge.key").font(Typo.body).foregroundStyle(.primary)
                }
            } header: { Text("Compliance") }
        }
        .listStyle(.insetGrouped)
        .background(Color.surface.ignoresSafeArea())
        .navigationTitle(v.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { showEditVessel = true } label: { Label("Edit Vessel", systemImage: "pencil") }
                    Divider()
                    Button { showShareVesselData = true } label: { Label("Share Vessel Data", systemImage: "square.and.arrow.up") }
                    Button { showOwnerShare = true } label: { Label("Share with Owner", systemImage: "person.badge.key") }
                    Divider()
                    Button(role: .destructive) { showDeleteConfirm = true } label: { Label("Delete Vessel", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.body)
                }
            }
        }
        .alert("Delete Vessel", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { vm.deleteVessel(id: vessel.id) }
        } message: {
            Text("This will delete \(v.name) and unlink all crew. Crew records will be preserved but unassigned.")
        }
        .sheet(item: $activeCheck) { VerificationSheet(vm: vm, check: $0) }
        .sheet(item: $inviteCheck) { InviteSheet(vm: vm, check: $0) }
        .navigationDestination(isPresented: $showExportPDF) { ExportPreviewView(vm: vm, vesselId: vessel.id, type: .pdf) }
        .navigationDestination(isPresented: $showExportCSV) { ExportPreviewView(vm: vm, vesselId: vessel.id, type: .csv) }
        .sheet(item: $transferCheck) { check in TransferSheet(vm: vm, check: check, currentVesselId: vessel.id) }
        .sheet(isPresented: $addVesselDoc) { VesselDocAddSheet(vm: vm, vesselId: vessel.id) }
        .sheet(item: $selectedVesselDoc) { doc in VesselDocDetailSheet(vm: vm, vesselId: vessel.id, document: doc) }
        .sheet(isPresented: $showAddCrew) { AddCrewSheet(vm: vm, vesselId: vessel.id, onCreated: { check, method in
            showAddCrew = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                if method == .invite { inviteCheck = check } else { activeCheck = check }
            }
        }) }
        .sheet(isPresented: $showAssignExisting) { AssignExistingSheet(vm: vm, vesselId: vessel.id) }
        .navigationDestination(isPresented: $showExportCrewList) { CrewListPreview(vm: vm, vessel: vessel) }
        .sheet(isPresented: $showEditVessel) { EditVesselSheet(vm: vm, vessel: v) }
        .sheet(isPresented: $showOwnershipFlow) { OwnershipFlowView(vm: vm, vesselId: vessel.id) }
        .sheet(isPresented: $showShareVesselData) { ShareVesselSheet(vm: vm, vessel: v) }
        .sheet(isPresented: $showOwnerShare) { ShareWithOwnerSheet(vm: vm, vesselId: vessel.id) }
        .alert("Edit Name", isPresented: .constant(editingPerson != nil)) {
            TextField("Name", text: $editName)
            Button("Cancel", role: .cancel) { editingPerson = nil }
            Button("Save") {
                if let check = editingPerson, !editName.trimmingCharacters(in: .whitespaces).isEmpty {
                    vm.updateCheckName(checkId: check.id, name: editName.trimmingCharacters(in: .whitespaces))
                }
                editingPerson = nil
            }
        } message: { Text("Enter the correct name") }
        .alert("Delete", isPresented: .constant(checkToDelete != nil)) {
            Button("Cancel", role: .cancel) { checkToDelete = nil }
            Button("Delete", role: .destructive) {
                if let check = checkToDelete { vm.deleteCheckById(check.id) }
                checkToDelete = nil
            }
        } message: { Text("Delete \(checkToDelete?.displayName ?? "this person")? This cannot be undone.") }
        .sheet(isPresented: $showAddCompliance) {
            AddComplianceSheet(vm: vm, vesselId: vessel.id) { check in
                showAddCompliance = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { activeCheck = check }
            }
        }
    }

    // MARK: - Quick Actions

    private func quickAction(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 16))
                    .frame(width: 44, height: 44)
                    .background(Color.surfaceMuted)
                    .clipShape(Circle())
                Text(label).font(Typo.meta)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Stats with Progress Bar

    // MARK: - Certificate Summary (collapsed — full view pushed)

    @ViewBuilder
    private var certificateSections: some View {
        let readiness = certReadinessCache
        let portfolio = vm.vesselDocumentPortfolio(for: v)
        let attention = portfolio.filter { $0.document?.status == .expired || $0.document?.status == .expiringSoon }

        Section {
            // GT warning
            if v.grossTonnageValue == nil && v.grossTonnage.isEmpty {
                Button { showEditVessel = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle").font(Typo.meta).foregroundStyle(Color.review)
                        Text("Set gross tonnage for accurate requirements").font(Typo.meta).foregroundStyle(Color.review)
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(.quaternary)
                    }
                }
            }

            // Readiness summary
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(readiness.completed) of \(readiness.total) certificates").font(Typo.body)
                    Spacer()
                }
                ProgressBar(value: readiness.completed, total: readiness.total)
                if readiness.expiring > 0 || readiness.expired > 0 {
                    HStack(spacing: 8) {
                        if readiness.expired > 0 { MetadataPill(icon: "xmark.circle", text: "\(readiness.expired) Expired") }
                        if readiness.expiring > 0 { MetadataPill(icon: "exclamationmark.triangle", text: "\(readiness.expiring) Expiring") }
                    }
                }
            }

            // Attention items inline (max 3)
            ForEach(attention.prefix(3)) { item in
                certRow(item)
            }

            // View all + Add
            NavigationLink {
                VesselCertificatePortfolioView(vm: vm, vesselId: vessel.id)
            } label: {
                HStack {
                    Image(systemName: "folder").font(Typo.body).foregroundStyle(.secondary)
                    Text("View all certificates").font(Typo.body).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(portfolio.count)").font(Typo.meta).foregroundStyle(.tertiary)
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.quaternary)
                }
            }

            Button { addVesselDoc = true } label: {
                Label("Add certificate", systemImage: "plus.circle").font(Typo.body).foregroundStyle(.secondary)
            }
        } header: { Text("Certificates") }
    }

    @ViewBuilder
    private func certRow(_ item: KYCViewModel.VesselPortfolioItem) -> some View {
        if let doc = item.document {
            Button { selectedVesselDoc = doc } label: {
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 1.5).fill(doc.statusColor)
                        .frame(width: 3, height: 32).padding(.trailing, 12)
                    Image(systemName: item.type.icon).font(.system(size: 14)).foregroundStyle(doc.statusColor).frame(width: 22).padding(.trailing, 10)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.type.displayName).font(Typo.body).lineLimit(1).foregroundStyle(.primary)
                        HStack(spacing: 8) {
                            if let exp = doc.expiryDate { Text(exp.formatted(date: .abbreviated, time: .omitted)).font(Typo.meta).foregroundStyle(doc.statusColor) }
                            if let num = doc.documentNumber, !num.isEmpty { Text(num).font(Typo.meta).foregroundStyle(.secondary) }
                        }
                    }
                    Spacer()
                    if !doc.imagePaths.isEmpty { Image(systemName: "doc.fill").font(Typo.meta).foregroundStyle(.tertiary) }
                    Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(.quaternary)
                }
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) { vm.removeVesselDocument(vesselId: vessel.id, documentId: doc.id) } label: { Label("Remove", systemImage: "trash") }
            }
        } else {
            Button { addVesselDoc = true } label: {
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 1.5).fill(item.required ? Color.review : Color.secondary.opacity(0.2))
                        .frame(width: 3, height: 32).padding(.trailing, 12)
                    Image(systemName: item.type.icon).font(.system(size: 14)).foregroundStyle(.quaternary).frame(width: 22).padding(.trailing, 10)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.type.displayName).font(Typo.body).lineLimit(1).foregroundStyle(.secondary)
                        Text(item.reason ?? (item.required ? "Required — missing" : "Optional"))
                            .font(Typo.meta).foregroundStyle(item.required ? Color.review : Color.secondary.opacity(0.4))
                    }
                    Spacer()
                    Image(systemName: "plus").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func statWithBar(_ label: String, _ value: Int, _ total: Int) -> some View {
        VStack(spacing: 6) {
            Text("\(value)/\(total)").font(Typo.stat).foregroundStyle(value == total && total > 0 ? Color.clear_ : .secondary)
            Text(label).font(Typo.meta).foregroundStyle(.secondary)
            ProgressBar(value: value, total: total)
                .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Vessel Photo

    private func loadVesselPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        await MainActor.run { vm.saveVesselPhoto(vesselId: vessel.id, imageData: data) }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func personContextMenu(_ check: KYCCheck) -> some View {
        Button { editName = check.displayName; editingPerson = check } label: { Label("Edit Name", systemImage: "pencil") }

        Menu {
            ForEach(CrewRank.allCases) { r in
                Button("\(r.rawValue)") {
                    vm.updateEntityType(checkId: check.id, entityType: .seafarer)
                    vm.setCrewRank(r, for: check.id)
                }
            }
        } label: { Label("Assign as Crew", systemImage: "person.text.rectangle") }

        Menu {
            ForEach(KYCCheck.EntityType.shoreBasedTypes, id: \.self) { et in
                Button(et.rawValue) { vm.updateEntityType(checkId: check.id, entityType: et) }
            }
        } label: { Label("Assign as Shore-Based", systemImage: "building") }

        Menu {
            ForEach(KYCCheck.EntityType.ownershipTypes, id: \.self) { et in
                Button(et.rawValue) { vm.updateEntityType(checkId: check.id, entityType: et) }
            }
        } label: { Label("Assign as Compliance", systemImage: "person.badge.key") }

        Divider()

        if vm.vessels.count > 1 { Button { transferCheck = check } label: { Label("Move to Vessel", systemImage: "arrow.right.arrow.left") } }
        Button { vm.unassignCheckFromVessel(checkId: check.id) } label: { Label("Remove from Vessel", systemImage: "minus.circle") }

        Divider()
        Button(role: .destructive) { checkToDelete = check } label: { Label("Delete", systemImage: "trash") }
    }

    // MARK: - Components

    private func crewRow(_ check: KYCCheck) -> some View {
        HStack(spacing: 14) {
            avatar(check, size: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(check.displayName).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                HStack(spacing: 8) {
                    switch check.entityType.category {
                    case .crew:
                        if let rank = check.crewRank {
                            Text(rank.rawValue).font(Typo.meta).foregroundStyle(.secondary)
                        } else {
                            Text("No rank set").font(Typo.meta).foregroundStyle(.tertiary)
                        }
                    case .shoreBased:
                        Label(check.entityType.rawValue, systemImage: check.entityType.icon)
                            .font(Typo.meta).foregroundStyle(.secondary)
                    case .ownership:
                        HStack(spacing: 4) {
                            Label(check.entityType.rawValue, systemImage: check.entityType.icon).font(Typo.meta).foregroundStyle(.secondary)
                            if let pct = check.ownershipPercent, pct > 0 {
                                Text("\(String(format: "%.0f", pct))%").font(Typo.meta).fontWeight(.medium).foregroundStyle(pct >= 25 ? Color.review : Color.secondary)
                            }
                        }
                    }
                }
                // Document progress bar
                let docs = check.documents ?? []
                if !docs.isEmpty {
                    let valid = docs.filter { $0.status == .valid }.count
                    ProgressBar(value: valid, total: docs.count)
                }
            }
            Spacer()
            StatusBadge(status: check.status)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(check.accessibilityDescription)
        .accessibilityHint("Double tap to view details")
    }

    private func avatar(_ check: KYCCheck, size: CGFloat) -> some View {
        Group {
            if let photo = check.profilePhoto, let data = vm.loadDocumentImage(filename: photo), let img = UIImage(data: data) {
                Image(uiImage: img).resizable().scaledToFill()
                    .frame(width: size, height: size).clipShape(Circle())
                    .overlay(Circle().stroke(Color.primary.opacity(0.08), lineWidth: 1))
            } else {
                Circle().fill(Color.surfaceMuted).frame(width: size, height: size)
                    .overlay { Text(String(check.displayName.prefix(1)).uppercased()).font(.system(size: size * 0.36, weight: .semibold)).foregroundStyle(.secondary) }
                    .overlay(Circle().stroke(Color.primary.opacity(0.06), lineWidth: 1))
            }
        }
    }
}

// MARK: - Add Crew Sheet (the primary flow for adding crew to a vessel)

// MARK: - Vessel Certificate Portfolio (full grouped view — pushed from summary)

struct VesselCertificatePortfolioView: View {
    @ObservedObject var vm: KYCViewModel
    let vesselId: String
    @State private var selectedDoc: CrewDocument?
    @State private var showAddDoc = false

    private var vessel: Vessel { vm.vessels.first(where: { $0.id == vesselId }) ?? Vessel(name: "") }

    var body: some View {
        let portfolio = vm.vesselDocumentPortfolio(for: vessel)
        let grouped = Dictionary(grouping: portfolio, by: { $0.type.category })
        let categories = VesselDocCategory.allCases.filter { grouped[$0] != nil }
        let readiness = vm.vesselDocReadiness(for: vessel)

        List {
            // Readiness header
            Section {
                ReadinessCard(completed: readiness.completed, total: readiness.total, expiringCount: readiness.expiring, expiredCount: readiness.expired, label: "certificates")
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            ForEach(categories) { category in
                Section {
                    ForEach(grouped[category] ?? []) { item in
                        certPortfolioRow(item)
                    }
                } header: { Text(category.rawValue) }
            }

            Section {
                Button { showAddDoc = true } label: {
                    Label("Add certificate", systemImage: "plus.circle").font(Typo.body).foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .background(Color.surface.ignoresSafeArea())
        .navigationTitle("Vessel Certificates")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedDoc) { doc in VesselDocDetailSheet(vm: vm, vesselId: vesselId, document: doc) }
        .sheet(isPresented: $showAddDoc) { VesselDocAddSheet(vm: vm, vesselId: vesselId) }
    }

    private func certPortfolioRow(_ item: KYCViewModel.VesselPortfolioItem) -> some View {
        Group {
            if let doc = item.document {
                Button { selectedDoc = doc } label: {
                    HStack(spacing: 0) {
                        RoundedRectangle(cornerRadius: 1.5).fill(doc.statusColor)
                            .frame(width: 3, height: 32).padding(.trailing, 12)
                        Image(systemName: item.type.icon).font(.system(size: 14)).foregroundStyle(doc.statusColor).frame(width: 22).padding(.trailing, 10)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.type.displayName).font(Typo.body).lineLimit(1).foregroundStyle(.primary)
                            HStack(spacing: 8) {
                                if let exp = doc.expiryDate { Text(exp.formatted(date: .abbreviated, time: .omitted)).font(Typo.meta).foregroundStyle(doc.statusColor) }
                                if let num = doc.documentNumber, !num.isEmpty { Text(num).font(Typo.meta).foregroundStyle(.secondary) }
                            }
                        }
                        Spacer()
                        if !doc.imagePaths.isEmpty { Image(systemName: "doc.fill").font(Typo.meta).foregroundStyle(.tertiary) }
                        Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(.quaternary)
                    }
                }
            } else {
                Button { showAddDoc = true } label: {
                    HStack(spacing: 0) {
                        RoundedRectangle(cornerRadius: 1.5).fill(item.required ? Color.review : Color.secondary.opacity(0.2))
                            .frame(width: 3, height: 32).padding(.trailing, 12)
                        Image(systemName: item.type.icon).font(.system(size: 14)).foregroundStyle(.quaternary).frame(width: 22).padding(.trailing, 10)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.type.displayName).font(Typo.body).lineLimit(1).foregroundStyle(.secondary)
                            Text(item.reason ?? (item.required ? "Required — missing" : "Optional"))
                                .font(Typo.meta).foregroundStyle(item.required ? Color.review : Color.secondary.opacity(0.4))
                        }
                        Spacer()
                        Image(systemName: "plus").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Vessel Document Detail

struct VesselDocDetailSheet: View {
    @ObservedObject var vm: KYCViewModel
    let vesselId: String
    let document: CrewDocument
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirm = false
    @State private var showRenew = false
    @State private var showHistory = false
    @State private var previewImage: UIImage?
    @State private var previewFilename: String?
    @State private var shareData: Data?
    @State private var shareFilename: String?

    private var allVersions: [CrewDocument] {
        let vessel = vm.vessels.first(where: { $0.id == vesselId })
        return (vessel?.documents ?? []).filter { $0.vesselDocType == document.vesselDocType }
    }
    private var hasHistory: Bool { allVersions.count > 1 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Spacer(minLength: 16)

                    // Status
                    Image(systemName: document.docIcon)
                        .font(.system(size: 40)).foregroundStyle(document.statusColor)
                    Text(document.displayName).font(Typo.context)
                    Text(document.statusLabel)
                        .font(Typo.meta).fontWeight(.semibold).foregroundStyle(document.statusColor)

                    // Document images / PDFs — tappable for preview + share
                    if !document.imagePaths.isEmpty {
                        ForEach(document.imagePaths, id: \.self) { path in
                            if let data = vm.loadDocumentImage(filename: path) {
                                let isPDF = path.lowercased().hasSuffix(".pdf") || data.prefix(5) == Data([0x25, 0x50, 0x44, 0x46, 0x2D])
                                Button {
                                    if isPDF {
                                        // Share PDF data directly via ActivityView
                                        shareData = data; shareFilename = path
                                    } else if let img = UIImage(data: data) {
                                        previewImage = img; previewFilename = path
                                    }
                                } label: {
                                    if isPDF, let pdfDoc = PDFDocument(data: data), let page = pdfDoc.page(at: 0) {
                                        let bounds = page.bounds(for: .mediaBox)
                                        let renderer = UIGraphicsImageRenderer(size: CGSize(width: bounds.width * 2, height: bounds.height * 2))
                                        let rendered = renderer.image { ctx in
                                            UIColor.white.setFill()
                                            ctx.fill(CGRect(origin: .zero, size: CGSize(width: bounds.width * 2, height: bounds.height * 2)))
                                            ctx.cgContext.translateBy(x: 0, y: bounds.height * 2)
                                            ctx.cgContext.scaleBy(x: 2, y: -2)
                                            page.draw(with: .mediaBox, to: ctx.cgContext)
                                        }
                                        VStack(spacing: 4) {
                                            Image(uiImage: rendered).resizable().scaledToFit()
                                                .frame(maxHeight: 300)
                                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                            HStack(spacing: 4) {
                                                Image(systemName: "doc.richtext").font(.system(size: 10))
                                                Text("PDF \u{2022} Tap to open").font(.system(size: 10))
                                            }.foregroundStyle(.secondary)
                                        }
                                    } else if !isPDF, let img = UIImage(data: data) {
                                        Image(uiImage: img).resizable().scaledToFit()
                                            .frame(maxHeight: 300)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                            .overlay(alignment: .bottomTrailing) {
                                                Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 10))
                                                    .padding(6).background(.ultraThinMaterial).clipShape(Circle()).padding(8)
                                            }
                                    }
                                }
                                .buttonStyle(.plain)
                            } else {
                                HStack(spacing: 8) {
                                    Image(systemName: "icloud.and.arrow.down").font(.system(size: 14)).foregroundStyle(.secondary)
                                    Text(path).font(Typo.meta).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "doc.slash").font(.system(size: 28)).foregroundStyle(.quaternary)
                            Text("No image attached").font(Typo.meta).foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 20)
                    }

                    // Metadata
                    VStack(spacing: 1) {
                        if let n = document.documentNumber, !n.isEmpty { detailRow("Number", n) }
                        if let exp = document.expiryDate { detailRow("Expires", exp.formatted(date: .long, time: .omitted)) }
                        if let iss = document.issuingAuthority, !iss.isEmpty { detailRow("Issued by", iss) }
                        if let notes = document.notes, !notes.isEmpty { detailRow("Notes", notes) }
                    }
                    .background(Color.surfaceMuted.opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 20)

                    // Renewal guidance card
                    if let vdt = document.vesselDocType, let guidance = vdt.renewalInfo,
                       document.status == .expiringSoon || document.status == .expired {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Renewal Steps", systemImage: "arrow.clockwise")
                                .font(Typo.body).fontWeight(.medium)
                            Text(guidance.activity).font(Typo.body)
                            HStack(spacing: 16) {
                                Label(guidance.leadTime, systemImage: "clock").font(Typo.meta)
                                Label(guidance.contactType, systemImage: "person").font(Typo.meta)
                            }.foregroundStyle(.secondary)
                            if let notes = guidance.notes {
                                Text(notes).font(Typo.meta).foregroundStyle(.tertiary)
                            }
                        }
                        .padding(14)
                        .background(Color.review.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 20)
                    }

                    // Renew button
                    if document.expiryDate != nil {
                        Button { showRenew = true } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.clockwise")
                                Text("Renew Certificate")
                            }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .padding(.horizontal, 20)
                    }

                    // Version history
                    if hasHistory {
                        Button { showHistory = true } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "clock.arrow.circlepath")
                                Text("Version History")
                                Spacer()
                                Text("\(allVersions.count)").font(Typo.meta).foregroundStyle(.tertiary)
                                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(.quaternary)
                            }.font(Typo.body).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 20)
                    }

                    // Delete
                    Button(role: .destructive) { showDeleteConfirm = true } label: {
                        Text("Remove Certificate").font(Typo.meta)
                    }
                    .padding(.top, 8)

                    Spacer(minLength: 32)
                }
            }
            .background(Color.surface.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $showRenew) {
                VesselDocAddSheet(vm: vm, vesselId: vesselId, renewingDocId: document.id)
            }
            .sheet(isPresented: $showHistory) {
                DocumentHistorySheet(allVersions: allVersions)
            }
            .alert("Remove Certificate", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Remove", role: .destructive) {
                    vm.removeVesselDocument(vesselId: vesselId, documentId: document.id)
                    dismiss()
                }
            } message: { Text("This will remove \(document.displayName) from the vessel.") }
            .fullScreenCover(isPresented: Binding(get: { previewImage != nil }, set: { if !$0 { previewImage = nil } })) {
                if let img = previewImage {
                    ImagePreviewView(image: img, filename: previewFilename ?? "", imagesDir: vm.imagesDir)
                }
            }
            .sheet(isPresented: Binding(get: { shareData != nil }, set: { if !$0 { shareData = nil } })) {
                if let data = shareData { ActivityView(items: [data]) }
            }
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(Typo.meta).foregroundStyle(.secondary).frame(width: 80, alignment: .leading)
            Text(value).font(Typo.body)
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

// MARK: - Document Version History

struct DocumentHistorySheet: View {
    let allVersions: [CrewDocument]
    @Environment(\.dismiss) private var dismiss

    // Sort: current (non-archived) first, then by renewedAt descending
    private var sorted: [CrewDocument] {
        allVersions.sorted { a, b in
            if a.isArchived != b.isArchived { return !a.isArchived }
            return (a.renewedAt ?? Date.distantFuture) > (b.renewedAt ?? Date.distantFuture)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(sorted) { doc in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(doc.displayName).font(Typo.body).fontWeight(doc.isArchived ? .regular : .semibold)
                            Spacer()
                            if doc.isArchived {
                                Text("Archived").font(Typo.meta).foregroundStyle(.tertiary)
                            } else {
                                Text("Current").font(Typo.meta).fontWeight(.medium).foregroundStyle(Color.clear_)
                            }
                        }
                        HStack(spacing: 12) {
                            if let num = doc.documentNumber, !num.isEmpty {
                                Label(num, systemImage: "number").font(Typo.meta).foregroundStyle(.secondary)
                            }
                            if let exp = doc.expiryDate {
                                Label(exp.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                                    .font(Typo.meta).foregroundStyle(doc.status == .expired ? Color.flagged : .secondary)
                            }
                        }
                        if let renewed = doc.renewedAt {
                            Text("Renewed \(renewed.formatted(date: .abbreviated, time: .omitted))")
                                .font(Typo.meta).foregroundStyle(.tertiary)
                        }
                        if let iss = doc.issuingAuthority, !iss.isEmpty {
                            Text(iss).font(Typo.meta).foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Version History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

// MARK: - Crew List Preview (FAL Form 5)

struct CrewListPreview: View {
    @ObservedObject var vm: KYCViewModel
    let vessel: Vessel
    @State private var pdfURL: URL?
    @State private var generating = true
    @State private var showShare = false

    var body: some View {
        Group {
            if generating {
                VStack(spacing: 12) { ProgressView(); Text("Generating crew list...").font(Typo.body).foregroundStyle(.secondary) }
            } else if let url = pdfURL {
                PDFKitView(url: url).ignoresSafeArea(edges: .bottom)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 32)).foregroundStyle(.quaternary)
                    Text("Could not generate crew list").font(Typo.body).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Crew List")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if pdfURL != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button { showShare = true } label: { Image(systemName: "square.and.arrow.up") }
                }
            }
        }
        .sheet(isPresented: $showShare) { if let url = pdfURL { ActivityView(items: [url]) } }
        .task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            await MainActor.run {
                pdfURL = vm.generateCrewList(vesselId: vessel.id)
                withAnimation { generating = false }
            }
        }
    }
}

// MARK: - Edit Vessel Sheet

struct EditVesselSheet: View {
    @ObservedObject var vm: KYCViewModel
    let vessel: Vessel
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var imo: String
    @State private var callSign: String
    @State private var flag: String
    @State private var port: String
    @State private var vesselType: VesselType?
    @State private var grossTonnage: String
    @State private var builder: String
    @State private var yearBuilt: String
    @State private var owner: String
    @State private var certExpiry: String
    @State private var regLength: String
    @State private var showFlagPicker = false
    @State private var selectedPhoto: PhotosPickerItem?

    init(vm: KYCViewModel, vessel: Vessel) {
        self.vm = vm; self.vessel = vessel
        _name = State(initialValue: vessel.name)
        _imo = State(initialValue: vessel.imoNumber)
        _callSign = State(initialValue: vessel.callSign)
        _flag = State(initialValue: vessel.flagState)
        _port = State(initialValue: vessel.portOfRegistry)
        _vesselType = State(initialValue: vessel.vesselType)
        _grossTonnage = State(initialValue: vessel.grossTonnage)
        _builder = State(initialValue: vessel.builder)
        _yearBuilt = State(initialValue: vessel.yearBuilt)
        _owner = State(initialValue: vessel.registeredOwner)
        _certExpiry = State(initialValue: vessel.certificateExpiry)
        _regLength = State(initialValue: vessel.registeredLength)
    }

    private var selectedFlag: (emoji: String, name: String, code: String, port: String)? {
        VesselSheet.flagStates.first { $0.code == flag }
    }

    var body: some View {
        NavigationStack {
            List {
                // Vessel photo
                Section("Photo") {
                    let photoData = vessel.photoFilename.flatMap { vm.loadDocumentImage(filename: $0) }
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        HStack(spacing: 14) {
                            if let data = photoData, let img = UIImage(data: data) {
                                Image(uiImage: img).resizable().scaledToFill()
                                    .frame(width: 64, height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            } else {
                                RoundedRectangle(cornerRadius: 10).fill(Color.surfaceMuted)
                                    .frame(width: 64, height: 64)
                                    .overlay { Image(systemName: "camera").foregroundStyle(.tertiary) }
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(photoData != nil ? "Change Photo" : "Add Photo").font(Typo.body)
                                Text("Tap to select from library").font(Typo.meta).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.quaternary)
                        }
                    }
                    .onChange(of: selectedPhoto) { _, item in
                        guard let item else { return }
                        Task {
                            if let data = try? await item.loadTransferable(type: Data.self) {
                                await MainActor.run { vm.saveVesselPhoto(vesselId: vessel.id, imageData: data) }
                            }
                        }
                    }

                    if vessel.photoFilename != nil {
                        Button(role: .destructive) { vm.deleteVesselPhoto(vesselId: vessel.id) } label: {
                            Text("Remove Photo").font(Typo.meta)
                        }
                    }
                }

                Section("Identity") {
                    row("Vessel Name", text: $name)
                    row("IMO Number", text: $imo)
                    row("Call Sign", text: $callSign)
                }
                Section("Registration") {
                    Button { showFlagPicker = true } label: {
                        HStack {
                            Text("Flag State").foregroundStyle(.primary)
                            Spacer()
                            if let f = selectedFlag { Text("\(f.emoji) \(f.name)").foregroundStyle(.secondary) }
                            else if !flag.isEmpty { Text(flag).foregroundStyle(.secondary) }
                            else { Text("Select").foregroundStyle(.tertiary) }
                        }.font(Typo.body)
                    }
                    row("Port of Registry", text: $port)
                    Picker("Vessel Type", selection: $vesselType) {
                        Text("Not set").tag(VesselType?.none)
                        ForEach(VesselType.allCases) { vt in Text(vt.rawValue).tag(VesselType?.some(vt)) }
                    }.font(Typo.body)
                }
                Section("Details") {
                    row("Gross Tonnage", text: $grossTonnage)
                    row("Registered Length", text: $regLength)
                    row("Builder", text: $builder)
                    row("Year Built", text: $yearBuilt)
                    row("Registered Owner", text: $owner)
                    row("CoR Expiry", text: $certExpiry)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Edit Vessel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save(); dismiss() }.fontWeight(.semibold) }
            }
            .sheet(isPresented: $showFlagPicker) {
                FlagStatePicker(flags: VesselSheet.flagStates, selected: flag) { selected in
                    flag = selected.code
                    if port.isEmpty { port = selected.port }
                    showFlagPicker = false
                }
            }
        }
    }

    private func row(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label).font(Typo.body)
            Spacer()
            TextField("", text: text).font(Typo.body).multilineTextAlignment(.trailing).foregroundStyle(.secondary)
        }
    }

    private func save() {
        var updated = vessel
        updated.name = name.trimmingCharacters(in: .whitespaces)
        updated.imoNumber = imo; updated.callSign = callSign
        updated.flagState = flag.uppercased(); updated.portOfRegistry = port
        updated.vesselType = vesselType; updated.grossTonnage = grossTonnage
        updated.registeredLength = regLength
        updated.builder = builder; updated.yearBuilt = yearBuilt
        updated.registeredOwner = owner; updated.certificateExpiry = certExpiry
        vm.updateVessel(updated)
    }
}

// MARK: - Add Compliance Sheet

struct AddComplianceSheet: View {
    @ObservedObject var vm: KYCViewModel
    let vesselId: String
    let onCreated: (KYCCheck) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var entityType: KYCCheck.EntityType = .owner
    @State private var name = ""
    @State private var regNumber = ""
    @State private var jurisdiction = ""
    @State private var ownershipPercent = ""
    @State private var step = 0
    @FocusState private var focused: Bool

    private let entityTypes: [KYCCheck.EntityType] = KYCCheck.EntityType.ownershipTypes

    var body: some View {
        NavigationStack {
            Group {
                if step == 0 { typeStep } else { detailsStep }
            }
            .animation(.smooth(duration: 0.25), value: step)
            .background(Color.surface.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { if step == 0 { dismiss() } else { withAnimation { step = 0 } } } label: {
                        Image(systemName: step == 0 ? "xmark" : "chevron.left").foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var typeStep: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 24) {
                Text("Compliance Check").font(Typo.context)
                Text("Verify vessel ownership and management").font(Typo.meta).foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    ForEach(entityTypes, id: \.self) { et in
                        Button {
                            entityType = et
                            withAnimation { step = 1 }
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: et.icon).font(.system(size: 18)).frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(et.rawValue).font(Typo.body).fontWeight(.medium)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(.quaternary)
                            }
                            .padding(14).background(Color.surfaceMuted)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }.foregroundStyle(.primary)
                    }
                }.padding(.horizontal, 32)
            }
            Spacer()
        }
    }

    private var detailsStep: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 32)
                Image(systemName: entityType.icon).font(.system(size: 32)).foregroundStyle(.quaternary)
                Text(entityType.isCorporate ? "Company name" : "Full name").font(Typo.context)

                TextField("Name", text: $name)
                    .font(.system(size: 22, weight: .semibold))
                    .multilineTextAlignment(.center).focused($focused)
                    .padding(.horizontal, 40)

                VStack(spacing: 12) {
                    if entityType.isCorporate || entityType == .owner {
                        smallField("Registration Number", text: $regNumber, prompt: "12345678")
                        smallField("Jurisdiction", text: $jurisdiction, prompt: "Marshall Islands")
                    }
                    if entityType.needsOwnership {
                        smallField("Ownership %", text: $ownershipPercent, prompt: "25")
                    }
                }.padding(.horizontal, 40)

                Button {
                    let check = vm.createCheck(customerName: name.trimmingCharacters(in: .whitespaces), entityType: entityType, vesselId: vesselId, registrationNumber: regNumber.isEmpty ? nil : regNumber, jurisdiction: jurisdiction.isEmpty ? nil : jurisdiction, ownershipPercent: Double(ownershipPercent))
                    onCreated(check)
                } label: { Text("Start Verification") }
                    .buttonStyle(PrimaryButtonStyle(isEnabled: !name.trimmingCharacters(in: .whitespaces).isEmpty))
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .padding(.horizontal, 40)

                Spacer(minLength: 32)
            }
        }
        .onAppear { focused = true }
    }

    private func smallField(_ label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(Typo.meta).foregroundStyle(.secondary)
            TextField(prompt, text: text).font(Typo.body).padding(12)
                .background(Color.surfaceMuted).clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

// MARK: - Add Crew Sheet (simplified: scan or invite)

struct AddCrewSheet: View {
    @ObservedObject var vm: KYCViewModel
    let vesselId: String
    let onCreated: (KYCCheck, Method) -> Void
    @Environment(\.dismiss) private var dismiss

    enum Method { case direct, invite }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()
                VStack(spacing: 28) {
                    if let vessel = vm.vessels.first(where: { $0.id == vesselId }) {
                        HStack(spacing: 8) {
                            Image(systemName: "ferry").font(Typo.meta)
                            Text(vessel.name).font(Typo.meta)
                        }.foregroundStyle(.secondary)
                    }

                    Text("Add Crew").font(Typo.context)

                    VStack(spacing: 10) {
                        Button {
                            let check = vm.createCheck(customerName: "Crew \(UUID().uuidString.prefix(4))", vesselId: vesselId)
                            onCreated(check, .direct)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "camera.viewfinder").font(.system(size: 20)).frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Scan Passport").font(Typo.body).fontWeight(.medium)
                                    Text("Verify identity now").font(Typo.meta).opacity(0.7)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).opacity(0.4)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                            .background(Color.primary).foregroundStyle(Color.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }

                        if AppConfiguration.hasWorkflow && vm.isOnline {
                            Button {
                                let check = vm.createCheck(customerName: "Crew \(UUID().uuidString.prefix(4))", vesselId: vesselId)
                                onCreated(check, .invite)
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: "paperplane").font(.system(size: 20)).frame(width: 28)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Send Invite").font(Typo.body).fontWeight(.medium)
                                        Text("They verify themselves remotely").font(Typo.meta)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).opacity(0.4)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                                .background(Color.surfaceMuted).foregroundStyle(.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }
                    }.padding(.horizontal, 32)
                }
                Spacer()
            }
            .background(Color.surface.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(.secondary) }
                }
            }
        }
    }

}

// MARK: - Dead code removed — old multi-step flow replaced by 2-button design above

// MARK: - Assign Existing Crew Sheet

struct AssignExistingSheet: View {
    @ObservedObject var vm: KYCViewModel
    let vesselId: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if vm.unassignedChecks.isEmpty {
                        Text("No unassigned crew members").font(Typo.meta).foregroundStyle(.secondary)
                    } else {
                        ForEach(vm.unassignedChecks) { check in
                            Button {
                                vm.assignCheckToVessel(checkId: check.id, vesselId: vesselId)
                                if vm.unassignedChecks.isEmpty { dismiss() }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(check.displayName).font(Typo.body)
                                        if let rank = check.crewRank { Text(rank.rawValue).font(Typo.meta).foregroundStyle(.secondary) }
                                    }
                                    Spacer()
                                    StatusBadge(status: check.status)
                                }
                            }
                        }
                    }
                } header: { Text("Tap to assign to this vessel") }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Assign Crew")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

// MARK: - Transfer Sheet

struct TransferSheet: View {
    @ObservedObject var vm: KYCViewModel
    let check: KYCCheck
    let currentVesselId: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Transfer \(check.displayName)").font(Typo.body)
                } header: { Text("Select destination vessel") }

                ForEach(vm.vessels.filter { $0.id != currentVesselId }) { vessel in
                    Button {
                        vm.assignCheckToVessel(checkId: check.id, vesselId: vessel.id)
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(vessel.name).font(Typo.body)
                                if let vt = vessel.vesselType { Text(vt.rawValue).font(Typo.meta).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(.quaternary)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Transfer Crew")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

// MARK: - Vessel Document Add Sheet

struct VesselDocAddSheet: View {
    @ObservedObject var vm: KYCViewModel
    let vesselId: String
    var renewingDocId: String? = nil
    @Environment(\.dismiss) private var dismiss

    // Flow: capture → analyze → review → save
    enum Step { case capture, analyzing, review, noDocument, manualClassify }
    @State private var step: Step = .capture
    @State private var capturedImage: Data?
    @State private var capturedPDF: Data?
    @State private var showCamera = false
    @State private var showFilePicker = false

    // AI extraction results
    @State private var detectedType: VesselDocType?
    @State private var docNumber = ""
    @State private var expiryDate = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    @State private var hasExpiry = true
    @State private var issuingAuthority = ""
    @State private var confidence = ""

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .capture: captureStep
                case .analyzing: analyzingStep
                case .review: reviewStep
                case .noDocument: noDocumentStep
                case .manualClassify: manualClassifyStep
                }
            }
            .animation(.smooth(duration: 0.25), value: step)
            .background(Color.surface.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { if step == .capture { dismiss() } else { withAnimation { step = .capture; capturedImage = nil; capturedPDF = nil } } } label: {
                        Image(systemName: step == .capture ? "xmark" : "chevron.left").foregroundStyle(.secondary)
                    }
                }
            }
            .fullScreenCover(isPresented: $showCamera) { CameraCapture(result: $capturedImage).ignoresSafeArea() }
            .sheet(isPresented: $showFilePicker) {
                DocumentFilePicker { url in
                    showFilePicker = false
                    guard let url else { return }
                    if url.startAccessingSecurityScopedResource() {
                        defer { url.stopAccessingSecurityScopedResource() }
                        let data = try? Data(contentsOf: url)
                        if url.pathExtension.lowercased() == "pdf" { capturedPDF = data } else { capturedImage = data }
                    }
                }
            }
            .onChange(of: capturedImage) { _, val in if val != nil { analyzeDocument() } }
            .onChange(of: capturedPDF) { _, val in if val != nil { analyzeDocument() } }
        }
    }

    // MARK: - Step 1: Capture

    private var captureStep: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 28) {
                Image(systemName: "doc.viewfinder").font(.system(size: 44)).foregroundStyle(.quaternary)
                Text("Add Certificate").font(Typo.context)
                Text("Take a photo or upload a file.\nAI will identify the document automatically.").font(Typo.meta).foregroundStyle(.secondary).multilineTextAlignment(.center)

                VStack(spacing: 10) {
                    Button { showCamera = true } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "camera").font(.system(size: 20)).frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Take Photo").font(Typo.body).fontWeight(.medium)
                                Text("Photograph the certificate").font(Typo.meta).opacity(0.7)
                            }
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                        .background(Color.primary).foregroundStyle(Color.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    Button { showFilePicker = true } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "doc.badge.plus").font(.system(size: 20)).frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Upload File").font(Typo.body).fontWeight(.medium)
                                Text("PDF, JPEG, or PNG").font(Typo.meta)
                            }
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                        .background(Color.surfaceMuted).foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }.padding(.horizontal, 32)
            }
            Spacer()
        }
    }

    // MARK: - Step 2: Analyzing

    private var analyzingStep: some View {
        VStack(spacing: 24) {
            Spacer()
            // Show thumbnail
            if let data = capturedImage, let img = UIImage(data: data) {
                Image(uiImage: img).resizable().scaledToFit().frame(maxHeight: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 40)
            }
            VStack(spacing: 8) {
                ProgressView().controlSize(.regular)
                Text("Analyzing document...").font(Typo.body).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: - Step 3: Review (AI classified)

    private var reviewStep: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Thumbnail
                if let data = capturedImage, let img = UIImage(data: data) {
                    Image(uiImage: img).resizable().scaledToFit().frame(maxHeight: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal, 32)
                }

                if let dt = detectedType {
                    Label("Identified: \(dt.displayName)", systemImage: "brain")
                        .font(Typo.meta).foregroundStyle(Color.clear_)
                }

                VStack(spacing: 1) {
                    // Type (editable)
                    HStack {
                        Text("Type").font(Typo.meta).foregroundStyle(.secondary).frame(width: 80, alignment: .leading)
                        Spacer()
                        Menu {
                            ForEach(VesselDocType.allCases) { vdt in
                                Button(vdt.displayName) { detectedType = vdt }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(detectedType?.displayName ?? "Select").font(Typo.body)
                                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9)).foregroundStyle(.secondary)
                            }
                        }
                    }.padding(.horizontal, 14).padding(.vertical, 10)
                    Divider()
                    reviewField("Number", text: $docNumber)
                    Divider()
                    reviewField("Issuer", text: $issuingAuthority)
                    Divider()
                    Toggle(isOn: $hasExpiry) { Text("Expiry").font(Typo.meta).foregroundStyle(.secondary) }
                        .tint(.primary).padding(.horizontal, 14).padding(.vertical, 8)
                    if hasExpiry { DatePicker("Date", selection: $expiryDate, displayedComponents: .date).font(Typo.meta).padding(.horizontal, 14).padding(.bottom, 8) }
                }
                .background(Color.surfaceMuted.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20)

                Button { saveFinal() } label: { Text("Save Certificate") }
                    .buttonStyle(PrimaryButtonStyle(isEnabled: detectedType != nil))
                    .disabled(detectedType == nil)
                    .padding(.horizontal, 32)

                Spacer(minLength: 32)
            }
            .padding(.top, 16)
        }
    }

    // MARK: - No Document Detected

    private var noDocumentStep: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "doc.questionmark").font(.system(size: 44)).foregroundStyle(.quaternary)
            Text("No document detected").font(Typo.context)
            Text("The image doesn't appear to contain a recognizable certificate.").font(Typo.meta).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 32)

            VStack(spacing: 10) {
                Button { withAnimation { step = .manualClassify } } label: { Text("Classify Manually") }
                    .buttonStyle(PrimaryButtonStyle()).padding(.horizontal, 40)
                Button { withAnimation { step = .capture; capturedImage = nil; capturedPDF = nil } } label: {
                    Text("Try Again").font(Typo.meta).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    // MARK: - Manual Classification

    private var manualClassifyStep: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Select Certificate Type").font(Typo.context).padding(.top, 20)

                VStack(spacing: 6) {
                    ForEach(VesselDocType.allCases) { vdt in
                        Button {
                            detectedType = vdt
                            withAnimation { step = .review }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: vdt.icon).font(.system(size: 14)).frame(width: 24)
                                Text(vdt.displayName).font(Typo.body)
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(.quaternary)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .background(Color.surfaceMuted)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }.foregroundStyle(.primary)
                    }
                }.padding(.horizontal, 24)

                Spacer(minLength: 32)
            }
        }
    }

    // MARK: - AI Analysis

    private func analyzeDocument() {
        withAnimation { step = .analyzing }

        Task {
            let imageData = capturedImage ?? capturedPDF
            guard let data = imageData else { await MainActor.run { step = .noDocument }; return }

            // Try Claude
            if !KeychainService.get(.claudeAPIKey).isNilOrEmpty {
                do {
                    let prompt = """
                    Analyze this maritime document. Return ONLY JSON:
                    {
                      "is_document": true/false,
                      "document_type": "one of: Class Certificate, Safety Management Certificate (SMC), ISM Document of Compliance, IOPP Certificate, International Tonnage Certificate, Cargo Ship Safety Certificate, International Load Line Certificate, Radio Safety Certificate, Civil Liability Certificate (CLC), Wreck Removal Certificate, Minimum Safe Manning Document, P&I Insurance Certificate, Other Vessel Certificate",
                      "certificate_number": "extracted number or null",
                      "expiry_date": "DD Month YYYY or null",
                      "issuing_authority": "name or null",
                      "confidence": "high/medium/low"
                    }
                    If this is not a maritime certificate, set is_document to false.
                    """

                    let text: String
                    if capturedPDF != nil {
                        text = try await ClaudeService.shared.extractDocument(imageData: data, prompt: prompt)
                    } else {
                        text = try await ClaudeService.shared.extractDocument(imageData: data, prompt: prompt)
                    }

                    var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if cleaned.hasPrefix("```json") { cleaned = String(cleaned.dropFirst(7)) }
                    if cleaned.hasPrefix("```") { cleaned = String(cleaned.dropFirst(3)) }
                    if cleaned.hasSuffix("```") { cleaned = String(cleaned.dropLast(3)) }
                    cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

                    if let jsonData = cleaned.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {

                        let isDoc = json["is_document"] as? Bool ?? false
                        guard isDoc else {
                            await MainActor.run { withAnimation { step = .noDocument } }
                            return
                        }

                        let typeName = json["document_type"] as? String ?? ""
                        let number = json["certificate_number"] as? String
                        let expiry = json["expiry_date"] as? String
                        let issuer = json["issuing_authority"] as? String
                        let conf = json["confidence"] as? String ?? "low"

                        let matched = VesselDocType.allCases.first { $0.rawValue.lowercased() == typeName.lowercased() }

                        let fmt = DateFormatter(); fmt.dateFormat = "dd MMMM yyyy"; fmt.locale = Locale(identifier: "en_US")
                        let expDate = expiry.flatMap { fmt.date(from: $0) }

                        await MainActor.run {
                            detectedType = matched
                            if let n = number { docNumber = n }
                            if let iss = issuer { issuingAuthority = iss }
                            if let d = expDate { expiryDate = d; hasExpiry = true }
                            confidence = conf

                            if matched != nil {
                                withAnimation { step = .review }
                            } else {
                                withAnimation { step = .manualClassify }
                            }
                        }
                        return
                    }
                } catch {
                    // Claude doc analysis failed — fall through to manual classify
                }
            } else {
                // No Claude API key — skip AI analysis
            }

            // No Claude or failed — ask for manual classification
            await MainActor.run { withAnimation { step = .manualClassify } }
        }
    }

    // MARK: - Save

    private func saveFinal() {
        guard let vdt = detectedType else { return }
        var paths: [String] = []
        let fileData = capturedImage ?? capturedPDF
        if let data = fileData {
            let ext = capturedPDF != nil ? "pdf" : "jpg"
            let filename = "\(vesselId)_\(vdt.rawValue.prefix(10).replacingOccurrences(of: " ", with: "_"))_\(UUID().uuidString.prefix(6)).\(ext)"
            try? data.write(to: vm.imagesDir.appendingPathComponent(filename))
            paths.append(filename)
            vm.queueFileForSync(filename: filename, vesselId: vesselId)
        }
        let doc = CrewDocument(vesselDocType: vdt, imagePaths: paths,
            documentNumber: docNumber.isEmpty ? nil : docNumber,
            expiryDate: hasExpiry ? expiryDate : nil,
            issuingAuthority: issuingAuthority.isEmpty ? nil : issuingAuthority)
        if let oldId = renewingDocId {
            vm.renewVesselDocument(vesselId: vesselId, oldDocId: oldId, newDoc: doc)
        } else {
            vm.addVesselDocument(to: vesselId, document: doc)
        }
        dismiss()
    }

    private func reviewField(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label).font(Typo.meta).foregroundStyle(.secondary).frame(width: 80, alignment: .leading)
            TextField("", text: text).font(Typo.body).multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

// MARK: - Document File Picker

struct DocumentFilePicker: UIViewControllerRepresentable {
    let onPick: (URL?) -> Void
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf, .image, .jpeg, .png])
        picker.delegate = context.coordinator; return picker
    }
    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL?) -> Void
        init(onPick: @escaping (URL?) -> Void) { self.onPick = onPick }
        func documentPicker(_ c: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { onPick(urls.first) }
        func documentPickerWasCancelled(_ c: UIDocumentPickerViewController) { onPick(nil) }
    }
}
