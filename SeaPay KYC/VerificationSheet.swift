//
//  VerificationSheet.swift
//  OceanCheck
//
//  Redesign: stepped config, then tabbed results (Identity|Compliance|Address).
//  Verdict + actions pinned. Export in toolbar. Breathing AML hits.
//

import SwiftUI
import PhotosUI
import QuickLook
import UniformTypeIdentifiers
import PDFKit

struct VerificationSheet: View {
    @ObservedObject var vm: KYCViewModel
    let check: KYCCheck
    @Environment(\.dismiss) private var dismiss

    private var c: KYCCheck { vm.checks.first(where: { $0.id == check.id }) ?? check }
    private var hasResults: Bool { c.rawIDResponse != nil || c.completedAt != nil }
    private var isWaitingForInvite: Bool { c.sessionId != nil && c.completedAt == nil && c.rawIDResponse == nil }
    private var isCollaborator: Bool { UserDefaults.standard.bool(forKey: "isCollaborator") && AppConfiguration.apiKey.isEmpty }
    @State private var previewImage: UIImage?
    @State private var previewFilename: String?
    private var isExpiredSession: Bool { c.sessionId != nil && c.status == .incomplete && c.completedAt != nil }

    // Config
    @State private var step: ConfigStep = .docType
    enum ConfigStep: Int { case docType, depth, upload }
    @State private var docType: KYCCheck.IDDocType = .passport
    @State private var depth: KYCCheck.InvestigationDepth = .idAml
    @State private var monitoring = false

    // Capture
    @State private var frontImage: Data?; @State private var backImage: Data?; @State private var poaImage: Data?
    @State private var showFrontCam = false; @State private var showBackCam = false; @State private var showPoACam = false
    @State private var showFrontFile = false; @State private var showBackFile = false; @State private var showPoAFile = false
    @State private var selFrontPhoto: PhotosPickerItem?; @State private var selBackPhoto: PhotosPickerItem?; @State private var selPoAPhoto: PhotosPickerItem?
    @State private var imgError: String?

    // Processing
    @State private var busy = false; @State private var progressText = ""; @State private var error: String?
    @State private var amlRunning = false; @State private var poaRunning = false

    // Results
    @State private var idResult: IDResult?; @State private var amlResult: AMLResult?
    @State private var expandedHits: Set<Int> = []
    @State private var expandedSections: Set<String> = ["identity", "compliance", "address"]

    // Review
    @State private var editedName = ""; @State private var showAMLRerun = false
    @State private var reviewReason = ""; @State private var pendingReview: KYCCheck.ReviewDecision?; @State private var showChangeOptions = false
    @State private var notes = ""


    var body: some View {
        NavigationStack {
            Group {
                if hasResults && !isExpiredSession { resultsView }
                else if isExpiredSession { expiredSessionView }
                else if isWaitingForInvite { inviteWaitingView }
                else if busy { processingView }
                else { configView }
            }
            .background(Color.surface.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { Text(c.displayName).font(Typo.body) }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { saveNotes(); dismiss() } }
            }
            .onAppear { notes = c.agentNotes ?? ""; if let d = c.expectedDocType { docType = d }; if let d = c.investigationDepth { depth = d }; if hasResults { loadResults() } }
            .fullScreenCover(isPresented: $showFrontCam) { CameraCapture(result: $frontImage).ignoresSafeArea() }
            .fullScreenCover(isPresented: $showBackCam) { CameraCapture(result: $backImage).ignoresSafeArea() }
            .fullScreenCover(isPresented: $showPoACam) { CameraCapture(result: $poaImage).ignoresSafeArea() }
            .sheet(isPresented: $showFrontFile) { FilePicker { url in frontImage = loadFile(url, forAPI: true) } }
            .sheet(isPresented: $showBackFile) { FilePicker { url in backImage = loadFile(url, forAPI: true) } }
            .sheet(isPresented: $showPoAFile) { FilePicker { url in poaImage = loadFile(url, forAPI: false) } }
            .alert("Re-run Screening", isPresented: $showAMLRerun) {
                TextField("Full name", text: $editedName)
                Button("Screen") { Task { await rerunAML() } }; Button("Cancel", role: .cancel) {}
            } message: { Text("Edit the name and re-run compliance screening.") }
            .sheet(item: $pendingReview) { decision in
                ReviewCeremonyView(
                    personName: c.displayName,
                    documentType: c.documentType?.replacingOccurrences(of: "_", with: " ").capitalized,
                    amlStatus: c.amlStatus,
                    decision: decision == .approved ? .approve : decision == .declined ? .decline : .flag,
                    reason: $reviewReason,
                    onConfirm: { vm.submitReview(checkId: c.id, decision: decision, reason: reviewReason); reviewReason = "" }
                )
                .presentationDetents([.medium])
            }
            .fullScreenCover(item: Binding(
                get: { previewImage.map { ImagePreviewItem(image: $0, filename: previewFilename ?? "") } },
                set: { if $0 == nil { previewImage = nil } }
            )) { item in
                ImagePreviewView(image: item.image, filename: item.filename, imagesDir: vm.imagesDir)
            }
        }
    }

    private func saveNotes() { if !notes.isEmpty && notes != (c.agentNotes ?? "") { vm.updateAgentNotes(checkId: c.id, notes: notes) } }

    // ═══════════════════════════════════════════
    // MARK: - Invite Waiting
    // ═══════════════════════════════════════════

    @State private var showResendShare = false

    private var inviteWaitingView: some View {
        VStack(spacing: 20) {
            Spacer()
            Circle().fill(Color.primary.opacity(0.04)).frame(width: 80, height: 80)
                .overlay { ProgressView().controlSize(.regular) }
            VStack(spacing: 6) {
                Text("Waiting for verification").font(Typo.context)
                Text("Results appear here when \(c.customerName) completes the process.")
                    .font(Typo.meta).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 40)
            }

            // Elapsed time
            let elapsed = Int(Date().timeIntervalSince(c.createdAt) / 60)
            Text(elapsed < 60
                 ? "Invite sent \(max(elapsed, 1)) minute\(elapsed == 1 ? "" : "s") ago"
                 : "Invite sent \(elapsed / 60) hour\(elapsed / 60 == 1 ? "" : "s") ago")
                .font(Typo.meta).foregroundStyle(.tertiary)

            // Polling error display
            if let err = vm.pollingError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle").font(Typo.meta)
                    Text(err).font(Typo.meta)
                }
                .foregroundStyle(Color.flagged)
                .padding(.horizontal, 32)
            }

            VStack(spacing: 10) {
                if let url = c.hostedVerifyURL, !url.isEmpty {
                    Button { showResendShare = true } label: { Text("Re-share Link") }
                        .buttonStyle(SecondaryButtonStyle()).padding(.horizontal, 48)
                    .sheet(isPresented: $showResendShare) {
                        ActivityView(items: [url])
                    }
                }

                // Cancel option
                Button {
                    vm.cancelInviteSession(checkId: c.id)
                } label: {
                    Text("Cancel Verification").font(Typo.meta).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .onChange(of: hasResults) { _, newValue in
            if newValue && !isExpiredSession { Haptics.success() }
        }
    }

    // ═══════════════════════════════════════════
    // MARK: - Expired Session
    // ═══════════════════════════════════════════

    @State private var showResendInvite = false

    private var expiredSessionView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "clock.badge.xmark").font(.system(size: 48)).foregroundStyle(Color.review)
            Text("Session Expired").font(Typo.context)
            Text("The verification link has expired. Send a new invite to verify \(c.displayName).")
                .font(Typo.meta).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 32)

            Button { showResendInvite = true } label: { Text("Send New Invite") }
                .buttonStyle(PrimaryButtonStyle()).padding(.horizontal, 48)
            Spacer()
        }
        .sheet(isPresented: $showResendInvite) {
            InviteSheet(vm: vm, check: c)
        }
    }

    // ═══════════════════════════════════════════
    // MARK: - Config (steps 1-3 merged to feel lighter)
    // ═══════════════════════════════════════════

    private var configView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                // Document type — compact chips
                VStack(alignment: .leading, spacing: 10) {
                    Text("DOCUMENT").font(Typo.meta).foregroundStyle(.secondary).tracking(0.8)
                    HStack(spacing: 8) {
                        ForEach(KYCCheck.IDDocType.allCases) { dt in
                            Button { withAnimation(.spring(response: 0.2)) { docType = dt } } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: dt.icon).font(.system(size: 18))
                                    Text(dt.rawValue).font(.system(size: 9, weight: docType == dt ? .bold : .regular)).lineLimit(1).minimumScaleFactor(0.7)
                                }
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(docType == dt ? Color.primary : Color.surfaceMuted)
                                .foregroundStyle(docType == dt ? Color.surface : .primary)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }.buttonStyle(.plain)
                        }
                    }
                }

                // Scope — segmented
                VStack(alignment: .leading, spacing: 10) {
                    Text("SCOPE").font(Typo.meta).foregroundStyle(.secondary).tracking(0.8)
                    Picker("", selection: $depth) {
                        ForEach(KYCCheck.InvestigationDepth.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)

                    if depth.includesAML {
                        Toggle(isOn: $monitoring) {
                            Text("Continuous monitoring").font(Typo.meta)
                        }.tint(.primary)
                    }
                }

                // Upload
                VStack(alignment: .leading, spacing: 10) {
                    Text("DOCUMENTS").font(Typo.meta).foregroundStyle(.secondary).tracking(0.8)

                    slot("Front", data: frontImage, cam: $showFrontCam, file: $showFrontFile, photo: $selFrontPhoto, required: true)
                        .onChange(of: selFrontPhoto) { _, v in Task { frontImage = await loadPhoto(v) } }

                    slot(docType.needsBack ? "Back" : "Back (optional)", data: backImage, cam: $showBackCam, file: $showBackFile, photo: $selBackPhoto, required: docType.needsBack)
                        .onChange(of: selBackPhoto) { _, v in Task { backImage = await loadPhoto(v) } }

                    if depth.includesPoA {
                        slot("Proof of Address", data: poaImage, cam: $showPoACam, file: $showPoAFile, photo: $selPoAPhoto, required: true)
                            .onChange(of: selPoAPhoto) { _, v in Task { poaImage = await loadPhoto(v) } }
                    }
                }

                if let e = imgError { Text(e).font(Typo.meta).foregroundStyle(Color.flagged) }
                if let e = error { Text(e).font(Typo.meta).foregroundStyle(Color.flagged) }

                let ready = frontImage != nil && (!docType.needsBack || backImage != nil) && (!depth.includesPoA || poaImage != nil)
                Button { vm.configureCheck(checkId: c.id, docType: docType, depth: depth); Task { await runPipeline() } } label: {
                    Text("Verify")
                }
                .buttonStyle(PrimaryButtonStyle(isEnabled: ready))
                .disabled(!ready)
            }
            .padding(20)
        }
    }

    // ═══════════════════════════════════════════
    // MARK: - Processing
    // ═══════════════════════════════════════════

    private var processingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView().controlSize(.large)
            Text(progressText).font(Typo.body).foregroundStyle(.secondary)
            Spacer()
        }
    }

    // ═══════════════════════════════════════════
    // MARK: - Results (tabbed: Identity | Compliance | Address)
    // ═══════════════════════════════════════════

    private var resultsView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    // Hero header
                    VStack(spacing: 8) {
                        HStack(spacing: 10) {
                            Text(c.displayName).font(Typo.hero)
                            StatusBadge(status: c.status)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(c.displayName), \(c.status.accessibilityDescription)")
                        // Role pill (tappable menu)
                        HStack(spacing: 6) {
                            Menu {
                                Section("Crew") {
                                    ForEach(CrewRank.allCases) { r in
                                        Button { vm.updateEntityType(checkId: c.id, entityType: .seafarer); vm.setCrewRank(r, for: c.id) } label: {
                                            HStack { Text(r.rawValue); if c.entityType == .seafarer && c.crewRank == r { Image(systemName: "checkmark") } }
                                        }
                                    }
                                }
                                Section("Shore-Based") {
                                    ForEach(KYCCheck.EntityType.shoreBasedTypes, id: \.self) { et in
                                        Button { vm.updateEntityType(checkId: c.id, entityType: et) } label: {
                                            HStack { Label(et.rawValue, systemImage: et.icon); if c.entityType == et { Image(systemName: "checkmark") } }
                                        }
                                    }
                                }
                                Section("Ownership") {
                                    ForEach(KYCCheck.EntityType.ownershipTypes, id: \.self) { et in
                                        Button { vm.updateEntityType(checkId: c.id, entityType: et) } label: {
                                            HStack { Label(et.rawValue, systemImage: et.icon); if c.entityType == et { Image(systemName: "checkmark") } }
                                        }
                                    }
                                }
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

                            if let dt = c.documentType {
                                MetadataPill(icon: nil, text: dt.replacingOccurrences(of: "_", with: " ").capitalized)
                            }
                            if let date = c.completedAt {
                                MetadataPill(icon: nil, text: date.formatted(date: .abbreviated, time: .omitted))
                            }
                        }
                    }
                    .padding(.horizontal, 20).padding(.top, 8)

                    // Processing indicator
                    if amlRunning || poaRunning {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text(amlRunning ? "Checking compliance..." : "Verifying address...").font(Typo.meta).foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 20).padding(.vertical, 12)
                        .background(Color.surfaceMuted.opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal, 16)
                    }

                    // Verdict with review audit trail
                    if !amlRunning && !poaRunning {
                        VerdictBanner(
                            status: c.status,
                            reviewDecision: c.reviewDecision,
                            reviewedBy: c.reviewedBy,
                            reviewedAt: c.reviewedAt,
                            reviewReason: c.reviewReason
                        )
                        .padding(.horizontal, 16)
                    }

                    // Identity section
                    ExpandableSection("Identity", isExpanded: expandBinding("identity")) {
                        identityContent.padding(.bottom, 8)
                    }
                    .padding(.horizontal, 20)

                    // Compliance section
                    ExpandableSection("Compliance", isExpanded: expandBinding("compliance")) {
                        complianceContent.padding(.bottom, 8)
                    }
                    .padding(.horizontal, 20)

                    // Address section
                    if c.poaStatus != nil || depth.includesPoA {
                        ExpandableSection("Address", isExpanded: expandBinding("address")) {
                            addressContent.padding(.bottom, 8)
                        }
                        .padding(.horizontal, 20)
                    }

                    // Document Portfolio + PDF Report cards
                    VStack(spacing: 8) {
                        NavigationLink {
                            DocumentPortfolioView(vm: vm, checkId: c.id)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "folder")
                                Text("Document Portfolio")
                                Spacer()
                                let docs = c.documents ?? []
                                let valid = docs.filter { $0.status == .valid }.count
                                Text("\(valid)/\(docs.count)").font(Typo.meta).foregroundStyle(.secondary)
                                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                            }
                            .font(Typo.body)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12).padding(.horizontal, 16)
                            .background(Color.surfaceMuted)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }

                        NavigationLink {
                            PDFReportView(vm: vm, checkId: c.id)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "doc.text")
                                Text("PDF Report")
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                            }
                            .font(Typo.body)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12).padding(.horizontal, 16)
                            .background(Color.surfaceMuted)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .padding(.horizontal, 16)

                    Spacer(minLength: 80)
                }
            }

            // Pinned review bar (agents only — collaborators see read-only)
            if !amlRunning && !poaRunning && hasResults && !isCollaborator {
                if c.reviewDecision != nil {
                    // Decision already made — show change options
                    VStack(spacing: 6) {
                        Button { withAnimation(.smooth(duration: 0.2)) { showChangeOptions.toggle() } } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 11))
                                Text("Change Decision").font(Typo.meta)
                            }
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                        }
                        if showChangeOptions {
                            HStack(spacing: 8) {
                                reviewButton("Approve", Color.clear_, .approved)
                                reviewButton("Flag", Color.flagged, .flagged)
                                reviewButton("Decline", Color.review, .declined)
                            }
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 6)
                    .background(.bar)
                } else {
                    // No decision yet — show 3 review buttons
                    HStack(spacing: 8) {
                        reviewButton("Approve", Color.clear_, .approved)
                        reviewButton("Flag", Color.flagged, .flagged)
                        reviewButton("Decline", Color.review, .declined)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.bar)
                }
            }
        }
    }

    private func expandBinding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { expandedSections.contains(key) },
            set: { if $0 { expandedSections.insert(key) } else { expandedSections.remove(key) } }
        )
    }

    // ── Identity Content ──
    private var identityContent: some View {
            VStack(alignment: .leading, spacing: 12) {
                if let id = idResult {
                    if let dt = id.documentType {
                        Text(dt.replacingOccurrences(of: "_", with: " ").capitalized).font(Typo.context)
                    }
                    if !id.extractedFullName.isEmpty { DataRow(label: "Name", value: id.extractedFullName, bold: true) }
                    if let v = id.documentNumber { DataRow(label: "Number", value: v) }
                    if let v = id.dateOfBirth { DataRow(label: "DOB", value: v + (id.age.map { " (\($0))" } ?? "")) }
                    if let v = id.nationality { DataRow(label: "Nationality", value: v.uppercased()) }
                    if let v = id.issuingCountry ?? id.issuingStateName ?? id.issuingState { DataRow(label: "Issued by", value: v) }
                    if let v = id.expiryDate { DataRow(label: "Expires", value: v, color: expired(v) ? .flagged : nil) }
                    if let v = id.dateOfIssue { DataRow(label: "Issued", value: v) }
                    if let v = id.gender { DataRow(label: "Gender", value: v) }
                    if let v = id.placeOfBirth { DataRow(label: "Place of birth", value: v) }
                    if let v = id.personalNumber { DataRow(label: "Personal No.", value: v) }
                    if let v = id.formattedAddress ?? id.address, !v.isEmpty { DataRow(label: "Address", value: v) }
                    if let w = id.warnings, !w.isEmpty {
                        Divider()
                        ForEach(Array(w.enumerated()), id: \.offset) { _, w in
                            Text(w.shortDescription ?? w.risk ?? "").font(Typo.meta).foregroundStyle(Color.review)
                        }
                    }
                } else {
                    // Fallback: show data extracted from session decision
                    if let dt = c.documentType {
                        Text(dt.replacingOccurrences(of: "_", with: " ").capitalized).font(Typo.context)
                    }
                    if let v = c.extractedName, !v.isEmpty { DataRow(label: "Name", value: v, bold: true) }
                    if let v = c.documentNumber { DataRow(label: "Number", value: v) }
                    if let v = c.dateOfBirth { DataRow(label: "DOB", value: v) }
                    if let v = c.nationality { DataRow(label: "Nationality", value: v.uppercased()) }
                    if let v = c.issuingCountry { DataRow(label: "Issued by", value: v) }
                    if let v = c.expiryDate { DataRow(label: "Expires", value: v) }
                    if let v = c.documentIssueDate { DataRow(label: "Issued", value: v) }
                    if let v = c.gender { DataRow(label: "Gender", value: v) }
                    if let v = c.placeOfBirth { DataRow(label: "Place of birth", value: v) }
                    if let v = c.personalNumber { DataRow(label: "Personal No.", value: v) }
                    if let v = c.extractedAddress, !v.isEmpty { DataRow(label: "Address", value: v) }
                }
                // Images (hidden for collaborators — PII)
                if !isCollaborator, let paths = c.documentImagePaths, !paths.isEmpty {
                    Divider()
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(paths, id: \.self) { fn in
                                if let d = vm.loadDocumentImage(filename: fn), let img = UIImage(data: d) {
                                    Button {
                                        previewImage = img; previewFilename = fn
                                    } label: {
                                        Image(uiImage: img).resizable().scaledToFill().frame(width: 80, height: 54).clipShape(RoundedRectangle(cornerRadius: 8))
                                            .overlay(alignment: .bottomTrailing) {
                                                Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 7))
                                                    .padding(3).background(.ultraThinMaterial).clipShape(Circle()).padding(3)
                                            }
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                // Invite-based verification info
                if c.sessionId != nil && (c.documentImagePaths == nil || c.documentImagePaths?.isEmpty == true) {
                    HStack(spacing: 10) {
                        Image(systemName: "info.circle").font(Typo.meta).foregroundStyle(.secondary)
                        Text("Document verified remotely via Didit. Images processed server-side.").font(Typo.meta).foregroundStyle(.secondary)
                    }
                    .padding(10).background(Color.surfaceMuted).clipShape(RoundedRectangle(cornerRadius: 8))
                }

                // Notes
                VStack(alignment: .leading, spacing: 6) {
                    Text("NOTES").font(Typo.meta).foregroundStyle(.secondary).tracking(0.8)
                    TextField("Observations...", text: $notes, axis: .vertical).font(Typo.meta).lineLimit(2...4)
                        .padding(10).background(Color.surfaceMuted).clipShape(RoundedRectangle(cornerRadius: 10))
                    if notes != (c.agentNotes ?? "") && !notes.isEmpty {
                        Button("Save") { vm.updateAgentNotes(checkId: c.id, notes: notes) }.font(Typo.meta)
                    }
                }
            }

    }

    // ── Compliance Content ──
    private var complianceContent: some View {
            VStack(alignment: .leading, spacing: 14) {
                if amlRunning {
                    HStack(spacing: 10) { ProgressView(); Text("Screening in progress...").font(Typo.meta).foregroundStyle(.secondary) }
                } else if let aml = amlResult {
                    // Summary
                    HStack(spacing: 16) {
                        if let s = aml.score { RiskGauge(score: s, size: 64) }
                        VStack(alignment: .leading, spacing: 4) {
                            if let s = aml.status { Text(s).font(Typo.context).foregroundStyle(s == "Approved" ? Color.clear_ : s == "Declined" ? Color.flagged : Color.review) }
                            if let h = aml.totalHits, h > 0 { Text("\(h) match\(h == 1 ? "" : "es")").font(Typo.meta).foregroundStyle(.secondary) }
                            if c.amlMonitoring == true { Text("Monitoring active").font(Typo.meta).foregroundStyle(.secondary) }
                        }
                        Spacer()
                    }

                    // Hits — breathing: plain language collapsed, clean expanded
                    if let hits = aml.hits, !hits.isEmpty {
                        Divider()
                        ForEach(Array(hits.prefix(10).enumerated()), id: \.offset) { idx, hit in
                            hitView(hit, idx: idx)
                        }
                    }

                    Button { editedName = c.extractedName ?? ""; showAMLRerun = true } label: {
                        Text("Re-run screening").font(Typo.meta)
                    }.foregroundStyle(.secondary)
                } else {
                    // AML not yet run — offer to run it
                    VStack(spacing: 16) {
                        Image(systemName: "shield.checkered").font(.system(size: 36)).foregroundStyle(.quaternary)
                        Text("AML screening not performed").font(Typo.body).foregroundStyle(.secondary)

                        if c.extractedName != nil {
                            Button { Task { await runInitialAML() } } label: {
                                Text("Run AML Screening")
                            }
                            .buttonStyle(PrimaryButtonStyle()).padding(.horizontal, 24)
                        } else {
                            Text("Complete identity verification first").font(Typo.meta).foregroundStyle(.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 24)
                }
            }

    }

    private func runInitialAML() async {
        amlRunning = true
        do {
            let result = try await vm.runAMLScreening(checkId: c.id)
            amlResult = result
        } catch {
            // AML screening failed — silently handled, user sees no result
        }
        amlRunning = false
    }

    // ── Hit View (proposal #5: breathing) ──
    private func hitView(_ hit: AMLHit, idx: Int) -> some View {
        let expanded = expandedHits.contains(idx)
        return VStack(alignment: .leading, spacing: 0) {
            // Collapsed: entity name + plain language summary
            Button {
                withAnimation(.smooth(duration: 0.2)) { if expanded { expandedHits.remove(idx) } else { expandedHits.insert(idx) } }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(hit.caption ?? "Unknown").font(Typo.body)
                        Text(hitSummary(hit)).font(Typo.meta).foregroundStyle(.secondary).lineLimit(expanded ? nil : 1)
                    }
                    Spacer()
                    if let ms = hit.matchScore { Text("\(ms)%").font(Typo.meta).foregroundStyle(ms > 80 ? Color.flagged : Color.review) }
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }.buttonStyle(.plain)

            // Expanded: clean two-column
            if expanded {
                VStack(alignment: .leading, spacing: 8) {
                    if let ds = hit.datasets, !ds.isEmpty { DataRow(label: "Categories", value: ds.joined(separator: ", ")) }
                    if let sb = hit.scoreBreakdown {
                        let parts = [sb.nameScore.map { "Name \($0)" }, sb.dobScore.map { "DOB \($0)" }, sb.countryScore.map { "Country \($0)" }].compactMap { $0 }
                        if !parts.isEmpty { DataRow(label: "Scoring", value: parts.joined(separator: " · ")) }
                    }
                    if let peps = hit.pepMatches, !peps.isEmpty { ForEach(Array(peps.prefix(3).enumerated()), id: \.offset) { _, p in if let pos = p.pepPosition { DataRow(label: "PEP", value: pos) } } }
                    if let sxns = hit.sanctionMatches, !sxns.isEmpty { ForEach(Array(sxns.prefix(3).enumerated()), id: \.offset) { _, s in
                        if let d = s.description { DataRow(label: "Sanction", value: String(d.prefix(120))) }
                        if let url = s.sourceUrl, let link = URL(string: url) { Link(url, destination: link).font(Typo.meta).lineLimit(1) }
                    } }
                    if let media = hit.adverseMediaMatches, !media.isEmpty { ForEach(Array(media.prefix(3).enumerated()), id: \.offset) { _, m in
                        if let h = m.headline { DataRow(label: "Media", value: String(h.prefix(120))) }
                        if let url = m.sourceUrl, let link = URL(string: url) { Link(url, destination: link).font(Typo.meta).lineLimit(1) }
                    } }
                }
                .padding(.top, 8).padding(.leading, 4)
                .transition(.opacity)
            }
        }
        .padding(.vertical, 10)
    }

    /// Plain language one-liner for a hit (proposal #5)
    private func hitSummary(_ hit: AMLHit) -> String {
        if let pep = hit.pepMatches?.first?.pepPosition { return "Possible PEP — \(pep)" }
        if let sxn = hit.sanctionMatches?.first { return "Sanction — \(sxn.reason ?? sxn.description ?? "listed")" }
        if let m = hit.adverseMediaMatches?.first?.headline { return "Media — \(m)" }
        if let ds = hit.datasets, !ds.isEmpty { return ds.joined(separator: ", ") }
        return "Watchlist match"
    }

    // ── Address Content ──
    private var addressContent: some View {
            VStack(alignment: .leading, spacing: 12) {
                if poaRunning {
                    HStack(spacing: 10) { ProgressView(); Text("Verifying address...").font(Typo.meta).foregroundStyle(.secondary) }
                } else if let poa = c.poaStatus {
                    DataRow(label: "Status", value: poa, color: poa == "Approved" ? Color.clear_ : Color.flagged, bold: true)
                    if let a = c.poaAddress { DataRow(label: "Address", value: a) }
                    if let i = c.poaIssuer { DataRow(label: "Issuer", value: i) }
                } else {
                    Text("No address data").font(Typo.meta).foregroundStyle(.quaternary)
                }
            }
    }

    // ═══════════════════════════════════════════
    // MARK: - Review Buttons (pinned)
    // ═══════════════════════════════════════════

    private func reviewButton(_ label: String, _ color: Color, _ decision: KYCCheck.ReviewDecision) -> some View {
        Button { pendingReview = decision } label: {
            Text(label).font(.system(size: 12, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 10)
                .background(color.opacity(0.08)).foregroundStyle(color)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain)
    }

    // ═══════════════════════════════════════════
    // MARK: - Pipeline
    // ═══════════════════════════════════════════

    private func runPipeline() async {
        guard let front = frontImage else { return }
        busy = true; error = nil; progressText = "Scanning document..."
        do {
            let idScan = try await vm.runIDScan(checkId: c.id, frontImage: front, backImage: backImage)
            idResult = idScan.idResult
            busy = false
            // AML auto-runs
            if depth.includesAML {
                amlRunning = true
                do { amlResult = try await vm.runAMLScreening(checkId: c.id, monitoring: monitoring) } catch { self.error = "AML: \(error.localizedDescription)" }
                amlRunning = false
            } else { vm.finalizeIDOnly(checkId: c.id) }
            // PoA
            if depth.includesPoA, let img = poaImage {
                poaRunning = true
                do { _ = try await vm.runPoA(checkId: c.id, documentImage: img, expectedName: c.extractedName, expectedAddress: nil) { _ in } } catch { self.error = "PoA: \(error.localizedDescription)" }
                poaRunning = false
            }
        } catch { self.error = error.localizedDescription; busy = false }
    }

    private func rerunAML() async {
        amlRunning = true; error = nil
        do {
            let opts = VerificationAPIService.AMLOptions(includeAdverseMedia: true, includeMonitoring: monitoring)
            let (resp, raw) = try await VerificationAPIService.shared.screenAML(fullName: editedName, dateOfBirth: c.dateOfBirth, nationality: vm.toISO2(c.nationality), documentNumber: c.documentNumber, vendorData: c.id, options: opts)
            amlResult = resp.aml; vm.updateAML(checkId: c.id, result: resp.aml, rawJSON: String(data: raw, encoding: .utf8) ?? "")
        } catch { self.error = error.localizedDescription }
        amlRunning = false
    }

    private func loadResults() {
        if let raw = c.rawIDResponse, let d = raw.data(using: .utf8) {
            // Try standalone ID response first
            if let decoded = try? JSONDecoder().decode(IDVerificationResponse.self, from: d).idVerification {
                idResult = decoded
            }
            // Fall back to session decision (invite-based checks store this format)
            else if let decision = try? JSONDecoder().decode(SessionDecision.self, from: d) {
                idResult = decision.idVerifications?.first
                if amlResult == nil { amlResult = decision.aml?.first }
            }
        }
        if let raw = c.rawAMLResponse, let d = raw.data(using: .utf8) { amlResult = try? JSONDecoder().decode(AMLScreeningResponse.self, from: d).aml }
    }

    // ═══════════════════════════════════════════
    // MARK: - Upload Slot
    // ═══════════════════════════════════════════

    private func slot(_ title: String, data: Data?, cam: Binding<Bool>, file: Binding<Bool>, photo: Binding<PhotosPickerItem?>, required: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text(title).font(Typo.meta).foregroundStyle(.secondary); if required { Text("*").foregroundStyle(Color.review) } }
            if let data, let img = UIImage(data: data) ?? renderPDF(data) {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: img).resizable().scaledToFit().frame(maxHeight: 120).frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 10))
                    Menu { Button { cam.wrappedValue = true } label: { Label("Camera", systemImage: "camera") }; PhotosPicker(selection: photo, matching: .images) { Label("Photos", systemImage: "photo") }; Button { file.wrappedValue = true } label: { Label("File", systemImage: "folder") }
                    } label: { Image(systemName: "pencil.circle.fill").font(.title3).foregroundStyle(.white, .primary).padding(4) }
                }
            } else {
                HStack(spacing: 6) {
                    Button { cam.wrappedValue = true } label: { miniBtn("camera.fill", "Camera") }
                    PhotosPicker(selection: photo, matching: .images) { miniBtn("photo.fill", "Photos") }
                    Button { file.wrappedValue = true } label: { miniBtn("folder.fill", "File") }
                }
            }
        }
    }

    private func miniBtn(_ icon: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 14))
            Text(label).font(.system(size: 8, weight: .medium))
        }
        .frame(maxWidth: .infinity).frame(height: 52)
        .background(Color.surfaceMuted).foregroundStyle(.primary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // ═══════════════════════════════════════════
    // MARK: - Helpers
    // ═══════════════════════════════════════════

    private func expired(_ s: String) -> Bool { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.date(from: s).map { $0 < Date() } ?? false }
    private func isPDF(_ d: Data?) -> Bool { guard let d, d.count > 4 else { return false }; let h = [UInt8](d.prefix(4)); return h[0]==0x25 && h[1]==0x50 && h[2]==0x44 && h[3]==0x46 }
    private func renderPDF(_ data: Data) -> UIImage? { guard let p = CGDataProvider(data: data as CFData), let doc = CGPDFDocument(p), let pg = doc.page(at: 1) else { return nil }; let r = pg.getBoxRect(.mediaBox); let s: CGFloat = 2; let sz = CGSize(width: r.width*s, height: r.height*s); return UIGraphicsImageRenderer(size: sz).image { c in UIColor.white.setFill(); c.fill(CGRect(origin: .zero, size: sz)); c.cgContext.translateBy(x: 0, y: sz.height); c.cgContext.scaleBy(x: s, y: -s); c.cgContext.drawPDFPage(pg) } }

    @MainActor private func loadPhoto(_ item: PhotosPickerItem?) async -> Data? {
        guard let item else { return nil }; imgError = nil
        do { guard let d = try await item.loadTransferable(type: Data.self) else { return nil }; let r = ImageValidator.validate(d); if r.isValid, let c = r.compressedData { return c }; imgError = r.error?.localizedDescription } catch { imgError = "Failed" }; return nil
    }

    private func loadFile(_ url: URL, forAPI: Bool) -> Data? {
        imgError = nil
        guard url.startAccessingSecurityScopedResource() else { imgError = "Cannot access file"; return nil }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let data = try? Data(contentsOf: url) else { imgError = "Cannot read file"; return nil }
        // File loaded successfully
        if isPDF(data) {
            if forAPI {
                // Render PDF page to JPEG for the verification API
                guard let img = renderPDF(data) else { imgError = "Cannot render PDF"; return nil }
                guard let jpeg = img.jpegData(compressionQuality: 0.90) else { imgError = "Cannot convert to JPEG"; return nil }
                // PDF rendered to JPEG for API submission
                return jpeg
            } else {
                return data.count <= 15*1024*1024 ? data : nil
            }
        }
        let r = ImageValidator.validate(data)
        if r.isValid, let c = r.compressedData { return c }
        imgError = r.error?.localizedDescription
        return nil
    }
}

// MARK: - Camera / File Picker / PDF Preview / Share

struct CameraCapture: UIViewControllerRepresentable {
    @Binding var result: Data?; @Environment(\.dismiss) private var dismiss
    func makeUIViewController(context: Context) -> UIImagePickerController { let p = UIImagePickerController(); p.sourceType = .camera; p.delegate = context.coordinator; return p }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> C { C(self) }
    class C: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraCapture; init(_ p: CameraCapture) { parent = p }
        func imagePickerController(_ p: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) { if let img = info[.originalImage] as? UIImage { let v = ImageValidator.validate(img.jpegData(compressionQuality: 0.85) ?? Data()); parent.result = v.compressedData ?? img.jpegData(compressionQuality: 0.8) }; parent.dismiss() }
        func imagePickerControllerDidCancel(_ p: UIImagePickerController) { parent.dismiss() }
    }
}

struct FilePicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void; @Environment(\.dismiss) private var dismiss
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [.jpeg, .png, .heic, .tiff, .webP, .pdf, .image]
        let p = UIDocumentPickerViewController(forOpeningContentTypes: types)
        p.delegate = context.coordinator
        p.allowsMultipleSelection = false
        return p
    }
    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Co { Co(self) }
    class Co: NSObject, UIDocumentPickerDelegate { let parent: FilePicker; init(_ p: FilePicker) { parent = p }
        func documentPicker(_ c: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { if let u = urls.first { parent.onPick(u) }; parent.dismiss() }
        func documentPickerWasCancelled(_ c: UIDocumentPickerViewController) { parent.dismiss() } }
}

// MARK: - PDF Report (pushed, not sheeted — always works)

struct PDFReportView: View {
    @ObservedObject var vm: KYCViewModel
    let checkId: String
    @State private var pdfURL: URL?
    @State private var showShare = false

    var body: some View {
        Group {
            if let url = pdfURL {
                PDFKitView(url: url).ignoresSafeArea(edges: .bottom)
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Generating report...").font(Typo.meta).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Report").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if pdfURL != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button { showShare = true } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .sheet(isPresented: $showShare) {
            if let url = pdfURL { ActivityView(items: [url]) }
        }
        .task {
            // Generate on a slight delay so the push animation completes first
            try? await Task.sleep(nanoseconds: 100_000_000)
            pdfURL = vm.generateReport(checkId: checkId)
        }
    }
}

struct PDFPreviewSheet: View {
    let url: URL; var onShare: () -> Void; @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            PDFKitView(url: url).ignoresSafeArea(edges: .bottom)
                .navigationTitle("Report").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                    ToolbarItem(placement: .primaryAction) { Button { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { onShare() } } label: { Image(systemName: "square.and.arrow.up") } }
                }
        }
    }
}
struct PDFKitView: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> PDFView { let v = PDFView(); v.autoScales = true; v.document = PDFDocument(url: url); return v }
    func updateUIView(_ v: PDFView, context: Context) {}
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
