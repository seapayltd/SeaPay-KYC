//
//  PersonResultsView.swift
//  OceanCheck
//
//  Post-verification person profile. Jony Ive design language:
//  monochrome base, status-only color, strict Typo tokens, breathing layout.
//

import SwiftUI
import PhotosUI

struct PersonResultsView: View {
    @ObservedObject var vm: KYCViewModel
    let checkId: String

    private var c: KYCCheck { vm.checks.first(where: { $0.id == checkId }) ?? KYCCheck(id: checkId, customerId: "", customerName: "Unknown", agentId: "", agentName: "", checkType: .idVerification, status: .pending, entityType: .seafarer, createdAt: Date()) }
    private var isCollaborator: Bool { UserDefaults.standard.bool(forKey: "isCollaborator") && AppConfiguration.apiKey.isEmpty }

    @State private var expanded: Set<String> = ["identity"]
    @State private var notes = ""
    @State private var showContactEditor = false
    @State private var showProfileCam = false
    @State private var profileData: Data?
    @State private var selProfilePhoto: PhotosPickerItem?
    @State private var showVCard = false
    @State private var vCardURL: URL?
    @State private var showForcePoA = false
    @State private var forcePoAReason = ""
    @State private var pendingReview: KYCCheck.ReviewDecision?
    @State private var reviewReason = ""
    @State private var showChangeOpts = false
    @State private var showAMLRerun = false
    @State private var editedName = ""
    @State private var previewImage: UIImage?
    @State private var previewName: String?
    @State private var poaRunning = false
    @State private var amlRunning = false
    @State private var idResult: IDResult?
    @State private var amlResult: AMLResult?
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            scrollBody
            if !amlRunning && !poaRunning && !isCollaborator { pinnedReviewBar }
        }
        .onAppear { loadResults(); notes = c.agentNotes ?? "" }
        .toolbar { toolbarMenu }
        .onChange(of: profileData) { _, d in if let d { vm.setProfilePhoto(checkId: checkId, imageData: d) } }
        .onChange(of: selProfilePhoto) { _, item in
            guard let item else { return }
            loadPhotoFromLibrary(item)
        }
        .fullScreenCover(isPresented: $showProfileCam) { CameraCapture(result: $profileData).ignoresSafeArea() }
        .fullScreenCover(isPresented: Binding(get: { previewImage != nil }, set: { if !$0 { previewImage = nil } })) {
            if let img = previewImage { ImagePreviewView(image: img, filename: previewName ?? "", imagesDir: vm.imagesDir) }
        }
        .sheet(isPresented: $showContactEditor) { ContactEditorSheet(vm: vm, checkId: checkId, check: c).presentationDetents([.large]) }
        .sheet(isPresented: $showVCard) { if let url = vCardURL { ActivityView(items: [url]) } }
        .sheet(item: $pendingReview) { d in
            ReviewCeremonyView(personName: c.displayName, documentType: c.documentType?.replacingOccurrences(of: "_", with: " ").capitalized, amlStatus: c.amlStatus,
                decision: d == .approved ? .approve : d == .declined ? .decline : .flag, reason: $reviewReason,
                onConfirm: { vm.submitReview(checkId: checkId, decision: d, reason: reviewReason); reviewReason = "" }).presentationDetents([.medium])
        }
        .alert("Re-run Screening", isPresented: $showAMLRerun) {
            TextField("Full name", text: $editedName); Button("Screen") { Task { await rerunAML() } }; Button("Cancel", role: .cancel) {}
        } message: { Text("Edit the name and re-run compliance screening.") }
        .alert("Override Address", isPresented: $showForcePoA) {
            TextField("Reason", text: $forcePoAReason)
            Button("Approve") { vm.forceApprovePoA(checkId: checkId, reason: forcePoAReason.isEmpty ? "Agent override" : forcePoAReason); Haptics.success(); forcePoAReason = "" }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Override the automated address verification.") }
    }

    // MARK: - Scroll Body

    private var scrollBody: some View {
        ScrollView { VStack(spacing: 0) { hero; quickActions; cards; notesArea; Spacer(minLength: 80) } }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 10) {
            // Avatar — agent can tap to change photo
            if !isCollaborator {
                Menu {
                    Button { showProfileCam = true } label: { Label("Take Photo", systemImage: "camera") }
                    PhotosPicker(selection: $selProfilePhoto, matching: .images) { Label("Choose from Library", systemImage: "photo") }
                } label: {
                    avatar(72)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "camera.fill").font(.system(size: 8)).foregroundStyle(.white)
                                .frame(width: 20, height: 20).background(Color.primary).clipShape(Circle())
                                .offset(x: 2, y: 2)
                        }
                }
            } else { avatar(72) }

            // Name + flag
            HStack(spacing: 6) {
                if let f = c.nationalityFlag { Text(f).font(.system(size: 18)) }
                Text(c.displayName).font(Typo.title).lineLimit(2).multilineTextAlignment(.center)
            }

            // Role + metadata — centered
            HStack(spacing: 6) { rolePill; docPill; datePill }

            StatusBadge(status: c.status)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 16)
    }

    // MARK: - Quick Actions (Apple Contacts style)

    private var quickActions: some View {
        HStack(spacing: 16) {
            if let p = c.phoneNumber, !p.isEmpty { actionCircle("phone.fill", "Call") { if let u = URL(string: "tel:\(p)") { UIApplication.shared.open(u) } } }
            if let e = c.emailAddress, !e.isEmpty { actionCircle("envelope.fill", "Email") { if let u = URL(string: "mailto:\(e)") { UIApplication.shared.open(u) } } }
            if c.phoneNumber != nil || c.emailAddress != nil { actionCircle("person.crop.rectangle", "vCard") { exportVCard() } }
            NavigationLink { DocumentPortfolioView(vm: vm, checkId: checkId) } label: { actionLabel("folder.fill", "Docs") }
            NavigationLink { PDFReportView(vm: vm, checkId: checkId) } label: { actionLabel("doc.text.fill", "Report") }
        }
        .padding(.horizontal, 20).padding(.bottom, 20)
    }

    private func actionCircle(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { actionLabel(icon, label) }.buttonStyle(.plain)
    }

    private func actionLabel(_ icon: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 16))
                .frame(width: 44, height: 44)
                .background(Color.surfaceMuted).clipShape(Circle())
                .foregroundStyle(.secondary)
            Text(label).font(Typo.meta).foregroundStyle(.secondary)
        }
    }

    // MARK: - Section Cards

    private var cards: some View {
        VStack(spacing: 10) { identityCard; complianceCard; addressCard; detailsCard }
            .padding(.horizontal, 16)
    }

    private var identityCard: some View {
        card("Identity") { idRows }
    }

    private var complianceCard: some View {
        card("Compliance") { amlRows }
    }

    private var addressCard: some View {
        card("Address") { poaRows }
    }

    private var detailsCard: some View {
        card("Personal Details") { detailRows }
    }

    private func card<C: View>(_ title: String, @ViewBuilder content: @escaping () -> C) -> some View {
        ExpandableSection(title, isExpanded: Binding(
            get: { expanded.contains(title) },
            set: { if $0 { expanded.insert(title) } else { expanded.remove(title) } }
        )) { content().padding(.bottom, 6) }
        .padding(.horizontal, 16).padding(.vertical, 4)
        .background(Color.surfaceMuted.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Identity Rows

    @ViewBuilder private var idRows: some View {
        if let id = idResult {
            if let dt = id.documentType { Text(dt.replacingOccurrences(of: "_", with: " ").capitalized).font(Typo.context) }
            if !id.extractedFullName.isEmpty { DataRow(label: "Name", value: id.extractedFullName, bold: true) }
            if let v = id.documentNumber { DataRow(label: "Number", value: v) }
            if let v = id.dateOfBirth { DataRow(label: "DOB", value: v + (id.age.map { " (\($0))" } ?? "")) }
            if let v = id.nationality { DataRow(label: "Nationality", value: v.uppercased()) }
            if let v = id.issuingCountry ?? id.issuingStateName ?? id.issuingState { DataRow(label: "Issued by", value: v) }
            if let v = id.expiryDate { DataRow(label: "Expires", value: v) }
            if let v = id.gender { DataRow(label: "Gender", value: v) }
        } else {
            if let v = c.extractedName, !v.isEmpty { DataRow(label: "Name", value: v, bold: true) }
            if let v = c.documentNumber { DataRow(label: "Number", value: v) }
            if let v = c.nationality { DataRow(label: "Nationality", value: v.uppercased()) }
            if let v = c.expiryDate { DataRow(label: "Expires", value: v) }
        }
        thumbRow
    }

    @ViewBuilder private var thumbRow: some View {
        if !isCollaborator, let paths = c.documentImagePaths, !paths.isEmpty {
            Divider()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(paths, id: \.self) { fn in
                        if let d = vm.loadDocumentImage(filename: fn), let img = UIImage(data: d) {
                            Button { previewImage = img; previewName = fn } label: {
                                Image(uiImage: img).resizable().scaledToFill().frame(width: 72, height: 48).clipShape(RoundedRectangle(cornerRadius: 8))
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Compliance Rows

    @ViewBuilder private var amlRows: some View {
        if let aml = amlResult {
            DataRow(label: "Status", value: aml.status ?? "Unknown", color: (aml.status == "Approved" || aml.status == "Clear") ? .clear_ : .flagged, bold: true)
            if let s = aml.score { HStack { DataRow(label: "Score", value: "\(s)"); Spacer(); RiskGauge(score: s, size: 36) } }
            if let h = aml.totalHits { DataRow(label: "Hits", value: "\(h)") }
        } else if let s = c.amlStatus {
            DataRow(label: "AML", value: s, color: (s == "Approved" || s == "Clear") ? .clear_ : .flagged, bold: true)
        } else { Text("No compliance data").font(Typo.meta).foregroundStyle(.quaternary) }
        if !isCollaborator {
            Button { editedName = c.extractedName ?? c.customerName; showAMLRerun = true } label: {
                Text("Re-run Screening").font(Typo.meta).foregroundStyle(.secondary)
            }.buttonStyle(.plain).padding(.top, 4)
        }
    }

    // MARK: - Address Rows

    @ViewBuilder private var poaRows: some View {
        if poaRunning { HStack(spacing: 8) { ProgressView(); Text("Verifying...").font(Typo.meta).foregroundStyle(.secondary) } }
        else if let poa = c.poaStatus {
            DataRow(label: "Status", value: poa, color: poa == "Approved" ? .clear_ : .flagged, bold: true)
            if let a = c.poaAddress { DataRow(label: "Address", value: a) }
            if let i = c.poaIssuer { DataRow(label: "Issuer", value: i) }
            if poa != "Approved" && !isCollaborator {
                HStack(spacing: 8) {
                    Button("Override") { showForcePoA = true }.buttonStyle(SecondaryButtonStyle())
                    Button("Resubmit") { vm.clearPoA(checkId: checkId) }.buttonStyle(SecondaryButtonStyle())
                }.padding(.top, 4)
            }
        } else if !isCollaborator {
            Text("No proof of address").font(Typo.meta).foregroundStyle(.quaternary)
        } else { Text("No address data").font(Typo.meta).foregroundStyle(.quaternary) }
    }

    // MARK: - Details Rows (contact + contract unified)

    @ViewBuilder private var detailRows: some View {
        // Contact
        if let p = c.phoneNumber, !p.isEmpty { TappableDataRow(label: "Phone", value: p, icon: "phone.fill") { if let u = URL(string: "tel:\(p)") { UIApplication.shared.open(u) } } }
        if let e = c.emailAddress, !e.isEmpty { TappableDataRow(label: "Email", value: e, icon: "envelope.fill") { if let u = URL(string: "mailto:\(e)") { UIApplication.shared.open(u) } } }
        if let ec = c.emergencyContact { DataRow(label: "Emergency", value: "\(ec.name) · \(ec.relationship)") }
        if let nok = c.nextOfKin { DataRow(label: "Next of Kin", value: "\(nok.name) · \(nok.relationship)") }
        contactContractDivider
        // Contract
        if let s = c.availabilityStatus { DataRow(label: "Status", value: s.rawValue) }
        if let s = c.contractStartDate { DataRow(label: "Start", value: s.formatted(date: .abbreviated, time: .omitted)) }
        if let e = c.contractEndDate { DataRow(label: "End", value: e.formatted(date: .abbreviated, time: .omitted), color: e < Date() ? .flagged : nil) }
        if let w = c.wages { DataRow(label: "Wages", value: "\(w) \(c.currency ?? "USD")", bold: true) }
        if let mlc = c.mlcCompliant { DataRow(label: "MLC 2006", value: mlc ? "Compliant" : "Non-Compliant", color: mlc ? .clear_ : .flagged) }
        // Actions
        if !isCollaborator {
            Divider().padding(.vertical, 4)
            Button { showContactEditor = true } label: { Text("Edit Details").font(Typo.meta).foregroundStyle(.secondary) }.buttonStyle(.plain)
        }
    }

    @ViewBuilder private var contactContractDivider: some View {
        if c.phoneNumber != nil || c.emailAddress != nil || c.emergencyContact != nil {
            if c.availabilityStatus != nil || c.contractStartDate != nil || c.wages != nil {
                Divider().padding(.vertical, 4)
            }
        }
    }

    // Nav cards removed — Docs + Report are now in Quick Actions circles

    // MARK: - Notes

    @ViewBuilder private var notesArea: some View {
        if !isCollaborator || !(c.agentNotes ?? "").isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("NOTES").font(Typo.meta).foregroundStyle(.secondary).tracking(0.6)
                TextField("Observations...", text: $notes, axis: .vertical).font(Typo.meta).lineLimit(2...4)
                    .padding(10).background(Color.surfaceMuted).clipShape(RoundedRectangle(cornerRadius: 10)).disabled(isCollaborator)
                if !isCollaborator && notes != (c.agentNotes ?? "") && !notes.isEmpty {
                    Button("Save") { vm.updateAgentNotes(checkId: checkId, notes: notes) }.font(Typo.meta)
                }
            }.padding(.horizontal, 20).padding(.top, 16)
        }
    }

    // MARK: - Review Bar

    private var pinnedReviewBar: some View {
        VStack(spacing: 0) {
            Divider()
            if let decision = c.reviewDecision {
                // Show current decision prominently + change option
                HStack {
                    HStack(spacing: 6) {
                        Circle().fill(decision == .approved ? Color.clear_ : decision == .flagged ? Color.flagged : Color.review)
                            .frame(width: 8, height: 8)
                        Text(decision.rawValue).font(Typo.body)
                            .foregroundStyle(decision == .approved ? Color.clear_ : decision == .flagged ? Color.flagged : Color.review)
                    }
                    Spacer()
                    Button { withAnimation(.smooth(duration: 0.2)) { showChangeOpts.toggle() } } label: {
                        Text("Change").font(Typo.body).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 10)
                if showChangeOpts { reviewBtns.padding(.horizontal, 16).padding(.bottom, 8).transition(.opacity) }
            } else {
                reviewBtns.padding(.horizontal, 16).padding(.vertical, 10)
            }
        }.background(.ultraThinMaterial)
    }

    private var reviewBtns: some View {
        HStack(spacing: 8) {
            rBtn("Approve", .clear_, .approved); rBtn("Flag", .flagged, .flagged); rBtn("Decline", .review, .declined)
        }
    }

    private func rBtn(_ label: String, _ color: Color, _ d: KYCCheck.ReviewDecision) -> some View {
        Button { pendingReview = d } label: {
            Text(label).font(Typo.body).frame(maxWidth: .infinity).padding(.vertical, 10)
                .background(color.opacity(0.08)).foregroundStyle(color).clipShape(RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain)
    }

    // MARK: - Pills

    @ViewBuilder private var docPill: some View { if let dt = c.documentType { MetadataPill(icon: nil, text: dt.replacingOccurrences(of: "_", with: " ").capitalized) } }
    @ViewBuilder private var datePill: some View { if let d = c.completedAt { MetadataPill(icon: nil, text: d.formatted(date: .abbreviated, time: .omitted)) } }

    private var rolePill: some View {
        Menu {
            Section("Crew") { ForEach(CrewRank.allCases) { r in Button(r.rawValue) { vm.updateEntityType(checkId: checkId, entityType: .seafarer); vm.setCrewRank(r, for: checkId) } } }
            Section("Shore-Based") { ForEach(KYCCheck.EntityType.shoreBasedTypes, id: \.self) { et in Button { vm.updateEntityType(checkId: checkId, entityType: et) } label: { Label(et.rawValue, systemImage: et.icon) } } }
            Section("Ownership") { ForEach(KYCCheck.EntityType.ownershipTypes, id: \.self) { et in Button { vm.updateEntityType(checkId: checkId, entityType: et) } label: { Label(et.rawValue, systemImage: et.icon) } } }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: c.entityType.icon).font(.system(size: 10))
                Text(c.entityType.category == .crew ? (c.crewRank?.rawValue ?? "Set Rank") : c.entityType.rawValue).font(Typo.meta)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8))
            }
            .foregroundStyle(c.entityType.category == .crew && c.crewRank == nil ? Color.review : .secondary)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(c.entityType.category == .crew && c.crewRank == nil ? Color.review.opacity(0.08) : Color.surfaceMuted)
            .clipShape(Capsule())
        }
    }

    // MARK: - Toolbar Menu

    @ToolbarContentBuilder private var toolbarMenu: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                if !isCollaborator {
                    Button { showProfileCam = true } label: { Label("Take Photo", systemImage: "camera") }
                    PhotosPicker(selection: $selProfilePhoto, matching: .images) { Label("Choose from Library", systemImage: "photo") }
                    Divider()
                    Button { showContactEditor = true } label: { Label("Edit Details", systemImage: "pencil") }
                    Button { editedName = c.extractedName ?? c.customerName; showAMLRerun = true } label: { Label("Re-run AML", systemImage: "arrow.counterclockwise") }
                }
            } label: { Image(systemName: "ellipsis.circle").font(.system(size: 17)) }
        }
    }

    // MARK: - Avatar

    private func avatar(_ size: CGFloat) -> some View {
        Group {
            if let photo = c.profilePhoto, let data = vm.loadDocumentImage(filename: photo), let img = UIImage(data: data) {
                Image(uiImage: img).resizable().scaledToFill().frame(width: size, height: size).clipShape(Circle())
            } else {
                Circle().fill(Color.surfaceMuted).frame(width: size, height: size)
                    .overlay { Text(String(c.customerName.prefix(1)).uppercased()).font(.system(size: size * 0.38, weight: .medium)).foregroundStyle(.secondary) }
            }
        }
    }

    // MARK: - Actions

    private func loadPhotoFromLibrary(_ item: PhotosPickerItem) {
        Task { @MainActor in
            if let photo = try? await item.loadTransferable(type: ProfileImageTransfer.self) {
                vm.setProfilePhoto(checkId: checkId, imageData: photo.data)
            }
        }
    }

    private func exportVCard() {
        guard let data = vm.generateVCard(for: c) else { return }
        // Sanitize filename: strip diacritics, remove non-ASCII, replace spaces
        let safe = c.displayName
            .folding(options: .diacriticInsensitive, locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
        let filename = (safe.isEmpty ? "contact" : safe) + ".vcf"
        let url = vm.imagesDir.appendingPathComponent(filename)
        try? data.write(to: url)
        vCardURL = url; showVCard = true; Haptics.light()
    }

    private func rerunAML() async {
        amlRunning = true; error = nil
        do {
            let opts = VerificationAPIService.AMLOptions(includeAdverseMedia: true, includeMonitoring: false)
            let (resp, raw) = try await VerificationAPIService.shared.screenAML(fullName: editedName, dateOfBirth: c.dateOfBirth, nationality: vm.toISO2(c.nationality), documentNumber: c.documentNumber, vendorData: checkId, options: opts)
            amlResult = resp.aml; vm.updateAML(checkId: checkId, result: resp.aml, rawJSON: String(data: raw, encoding: .utf8) ?? "")
        } catch { self.error = error.localizedDescription }
        amlRunning = false
    }

    private func loadResults() {
        if let raw = c.rawIDResponse, let d = raw.data(using: .utf8) {
            if let decoded = try? JSONDecoder().decode(IDVerificationResponse.self, from: d).idVerification { idResult = decoded }
            else if let decision = try? JSONDecoder().decode(SessionDecision.self, from: d) { idResult = decision.idVerifications?.first; if amlResult == nil { amlResult = decision.aml?.first } }
        }
        if let raw = c.rawAMLResponse, let d = raw.data(using: .utf8) { amlResult = try? JSONDecoder().decode(AMLScreeningResponse.self, from: d).aml }
    }
}

// MARK: - Profile Image Transfer (reliable PhotosPicker loading)

import UniformTypeIdentifiers

private struct ProfileImageTransfer: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        // .image is the abstract supertype — PhotosPicker always provides this
        DataRepresentation(importedContentType: .image) { data in
            // Convert whatever format (HEIC, PNG, JPEG, TIFF) to JPEG
            guard let image = UIImage(data: data) else {
                return ProfileImageTransfer(data: data)
            }
            let jpeg = image.jpegData(compressionQuality: 0.85) ?? data
            return ProfileImageTransfer(data: jpeg)
        }
    }
}
