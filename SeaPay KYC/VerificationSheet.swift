//
//  VerificationSheet.swift
//  SeaPay KYC
//
//  Sequential flow:
//  1. Choose document type
//  2. Choose investigation depth + monitoring
//  3. Upload documents
//  4. Results & manage
//

import SwiftUI
import PhotosUI
import QuickLook
import UniformTypeIdentifiers

struct VerificationSheet: View {
    @ObservedObject var vm: KYCViewModel
    let check: KYCCheck
    @Environment(\.dismiss) private var dismiss

    private var c: KYCCheck { vm.checks.first(where: { $0.id == check.id }) ?? check }
    private var hasResults: Bool { c.rawIDResponse != nil }

    // Step tracking
    @State private var step: Step = .docType

    enum Step: Int, CaseIterable { case docType, depth, upload, results }

    // Step 1
    @State private var docType: KYCCheck.IDDocType = .passport

    // Step 2
    @State private var depth: KYCCheck.InvestigationDepth = .idAml
    @State private var monitoring = false

    // Step 3
    @State private var frontImage: Data?
    @State private var backImage: Data?
    @State private var poaImage: Data?
    @State private var showFrontCam = false; @State private var showBackCam = false; @State private var showPoACam = false
    @State private var showFrontFile = false; @State private var showBackFile = false; @State private var showPoAFile = false
    @State private var selFrontPhoto: PhotosPickerItem?; @State private var selBackPhoto: PhotosPickerItem?; @State private var selPoAPhoto: PhotosPickerItem?
    @State private var imgError: String?

    // Processing
    @State private var busy = false; @State private var progressText = ""; @State private var error: String?

    // Step 4 results
    @State private var idResult: IDResult?; @State private var amlResult: AMLResult?
    @State private var pdfURL: URL?; @State private var showShare = false; @State private var showPDFPreview = false
    @State private var showNameMismatch = false; @State private var mismatch: (String, String)?
    @State private var showDocMismatch = false; @State private var detectedType = ""
    @State private var editedName = ""; @State private var showAMLRerun = false
    @State private var expandedHits: Set<Int> = []
    @State private var reviewReason = ""; @State private var showReviewSheet = false; @State private var pendingReview: KYCCheck.ReviewDecision?
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Group {
                if hasResults { resultsView }
                else { steppedView }
            }
            .background(Color.surfaceRaised.ignoresSafeArea())
            .navigationTitle(hasResults ? "Results" : stepTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { saveAndClose() }
                }
            }
            .onAppear { initState() }
            .fullScreenCover(isPresented: $showFrontCam) { CameraCapture(result: $frontImage).ignoresSafeArea() }
            .fullScreenCover(isPresented: $showBackCam) { CameraCapture(result: $backImage).ignoresSafeArea() }
            .fullScreenCover(isPresented: $showPoACam) { CameraCapture(result: $poaImage).ignoresSafeArea() }
            .sheet(isPresented: $showFrontFile) { FilePicker { url in frontImage = loadFile(url, forAPI: true) } }
            .sheet(isPresented: $showBackFile) { FilePicker { url in backImage = loadFile(url, forAPI: true) } }
            .sheet(isPresented: $showPoAFile) { FilePicker { url in poaImage = loadFile(url, forAPI: false) } }
            .sheet(isPresented: $showPDFPreview) {
                if let url = pdfURL { PDFPreviewView(url: url, onShare: { showShare = true }) }
            }
            .sheet(isPresented: $showShare) { if let url = pdfURL { ActivityView(items: [url]) } }
            .alert("Name Mismatch", isPresented: $showNameMismatch) { Button("OK") {} } message: { if let m = mismatch { Text("Entered: \(m.0)\nOn ID: \(m.1)") } }
            .alert("Document Type", isPresented: $showDocMismatch) { Button("OK") {} } message: { Text("Expected \(docType.rawValue) but detected \(detectedType).") }
            .alert("Review Decision", isPresented: $showReviewSheet) {
                TextField("Reason", text: $reviewReason)
                if let d = pendingReview { Button(d.rawValue) { vm.submitReview(checkId: c.id, decision: d, reason: reviewReason); reviewReason = "" } }
                Button("Cancel", role: .cancel) { reviewReason = "" }
            } message: { Text("This is recorded in the audit trail and PDF report.") }
            .alert("Re-run AML", isPresented: $showAMLRerun) {
                TextField("Full name", text: $editedName)
                Button("Screen") { Task { await rerunAML() } }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Edit the name and re-run compliance screening.") }
        }
    }

    private var stepTitle: String {
        switch step {
        case .docType: return "Document Type"
        case .depth: return "Investigation"
        case .upload: return "Upload"
        case .results: return "Results"
        }
    }

    private func initState() {
        notes = c.agentNotes ?? ""
        if let d = c.expectedDocType { docType = d }
        if let d = c.investigationDepth { depth = d }
        if hasResults { step = .results }
    }

    private func saveAndClose() {
        if !notes.isEmpty && notes != (c.agentNotes ?? "") { vm.updateAgentNotes(checkId: c.id, notes: notes) }
        dismiss()
    }

    // ═══════════════════════════════════════════
    // MARK: - Stepped Flow
    // ═══════════════════════════════════════════

    private var steppedView: some View {
        VStack(spacing: 0) {
            // Progress dots
            HStack(spacing: 8) {
                ForEach(0..<4) { i in
                    Circle().fill(i <= step.rawValue ? Color.brand : Color.brand.opacity(0.15))
                        .frame(width: i == step.rawValue ? 10 : 8, height: i == step.rawValue ? 10 : 8)
                        .animation(.spring(response: 0.3), value: step)
                }
            }
            .padding(.top, 12).padding(.bottom, 4)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    Text(c.customerName).font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.top, 8)

                    Group {
                        switch step {
                        case .docType: stepDocType
                        case .depth: stepDepth
                        case .upload: stepUpload
                        case .results: EmptyView()
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                    .id(step)
                }
                .padding(.bottom, 40)
            }
            .animation(.smooth(duration: 0.3), value: step)
        }
    }

    // ── STEP 1: Document Type ──

    private var stepDocType: some View {
        VStack(spacing: 16) {
            Text("What document will the customer present?").font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)

            ForEach(KYCCheck.IDDocType.allCases) { dt in
                Button {
                    withAnimation(.spring(response: 0.25)) { docType = dt }
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: dt.icon).font(.title3).foregroundStyle(docType == dt ? .white : Color.brand)
                            .frame(width: 44, height: 44)
                            .background(docType == dt ? Color.brand : Color.brand.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dt.rawValue).font(.subheadline.weight(.semibold))
                            Text(dt.scanHint).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: docType == dt ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(docType == dt ? Color.brand : Color.secondary.opacity(0.3))
                    }
                    .padding(14)
                    .background(docType == dt ? Color.brand.opacity(0.05) : Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(docType == dt ? Color.brand.opacity(0.3) : Color.clear, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            Button { withAnimation { step = .depth } } label: { Label("Next", systemImage: "arrow.right") }
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.horizontal, 20)
    }

    // ── STEP 2: Investigation Depth ──

    private var stepDepth: some View {
        VStack(spacing: 16) {
            Text("How deep should the investigation go?").font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)

            ForEach(KYCCheck.InvestigationDepth.allCases) { d in
                Button {
                    withAnimation(.spring(response: 0.25)) { depth = d }
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: d.icon).font(.title3).foregroundStyle(depth == d ? .white : Color.brand)
                            .frame(width: 44, height: 44)
                            .background(depth == d ? Color.brand : Color.brand.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.rawValue).font(.subheadline.weight(.semibold))
                            Text(d.description).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: depth == d ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(depth == d ? Color.brand : Color.secondary.opacity(0.3))
                    }
                    .padding(14)
                    .background(depth == d ? Color.brand.opacity(0.05) : Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(depth == d ? Color.brand.opacity(0.3) : Color.clear, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            if depth.includesAML {
                Toggle(isOn: $monitoring) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Continuous Monitoring").font(.caption.weight(.medium))
                        Text("Alerts when the subject's risk profile changes").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }.tint(Color.brand)
            }

            HStack(spacing: 10) {
                Button { withAnimation { step = .docType } } label: { Text("Back").frame(maxWidth: .infinity) }.buttonStyle(SecondaryButtonStyle())
                Button { vm.configureCheck(checkId: c.id, docType: docType, depth: depth); withAnimation { step = .upload } } label: { Label("Next", systemImage: "arrow.right").frame(maxWidth: .infinity) }.buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(.horizontal, 20)
    }

    // ── STEP 3: Upload ──

    private var stepUpload: some View {
        VStack(spacing: 14) {
            // ID front
            docSlot("Front of \(docType.rawValue)", data: frontImage, cam: $showFrontCam, filePicker: $showFrontFile, photoPicker: $selFrontPhoto, required: true)
                .onChange(of: selFrontPhoto) { _, v in Task { frontImage = await loadPhoto(v) } }

            // ID back
            let needsBack = docType.needsBack
            docSlot(needsBack ? "Back of \(docType.rawValue)" : "Back (optional)", data: backImage, cam: $showBackCam, filePicker: $showBackFile, photoPicker: $selBackPhoto, required: needsBack)
                .onChange(of: selBackPhoto) { _, v in Task { backImage = await loadPhoto(v) } }

            // PoA document
            if depth.includesPoA {
                Divider()
                Text("Proof of Address").font(.caption.weight(.semibold)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                docSlot("Utility bill, bank statement, or official letter", data: poaImage, cam: $showPoACam, filePicker: $showPoAFile, photoPicker: $selPoAPhoto, required: true)
                    .onChange(of: selPoAPhoto) { _, v in Task { poaImage = await loadPhoto(v) } }
            }

            if let e = imgError { Label(e, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(Color.warning) }
            if let e = error {
                HStack(alignment: .top, spacing: 8) { Image(systemName: "xmark.circle.fill").foregroundStyle(Color.fail); Text(e).font(.caption) }
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color.fail.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 10))
            }

            if busy {
                VStack(spacing: 10) { ProgressView(); Text(progressText).font(.subheadline.weight(.medium)).foregroundStyle(Color.brand) }.padding(.vertical, 16)
            }

            HStack(spacing: 10) {
                Button { withAnimation { step = .depth } } label: { Text("Back").frame(maxWidth: .infinity) }.buttonStyle(SecondaryButtonStyle()).disabled(busy)

                let ready = frontImage != nil && (!needsBack || backImage != nil) && (!depth.includesPoA || poaImage != nil)
                Button { Task { await runPipeline() } } label: { Label("Verify", systemImage: "checkmark.shield.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(PrimaryButtonStyle(isEnabled: ready && !busy)).disabled(!ready || busy)
                    .accessibilityLabel("Start verification")
                    .accessibilityHint("Scans the uploaded documents and runs all selected checks")
            }
        }
        .padding(.horizontal, 20)
    }

    // ═══════════════════════════════════════════
    // MARK: - Results View (step 4 / reopened)
    // ═══════════════════════════════════════════

    private var resultsView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                // Header
                HStack(spacing: 14) {
                    Image(systemName: c.expectedDocType?.icon ?? "doc").font(.title3.weight(.medium)).foregroundStyle(.white)
                        .frame(width: 44, height: 44).background(Color.brand.gradient).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) { Text(c.customerName).font(.headline); Text(c.expectedDocType?.rawValue ?? "").font(.caption).foregroundStyle(.secondary) }
                    Spacer(); StatusBadge(status: c.status)
                }.padding(.horizontal, 20).padding(.top, 8)

                // Verdict
                if anyCheckRunning {
                    HStack(spacing: 14) {
                        ProgressView().controlSize(.small)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Verification In Progress").font(.headline)
                            Text(amlRunning ? "Running compliance screening..." : "Verifying address document...")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(16).background(Color.brand.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 20)
                } else {
                    VerdictBanner(status: c.status).padding(.horizontal, 20)
                }

                // ID card
                if let id = idResult ?? loadedIDResult { idCard(id) }

                // AML card or in-progress indicator
                if amlRunning {
                    CardView {
                        HStack(spacing: 14) {
                            ProgressView()
                            VStack(alignment: .leading, spacing: 2) {
                                Text("AML Screening in Progress").font(.caption.weight(.semibold))
                                Text("Checking sanctions, PEP, and adverse media databases...").font(.system(size: 9)).foregroundStyle(.secondary)
                            }
                        }
                    }.padding(.horizontal, 20)
                } else if let aml = amlResult ?? loadedAMLResult {
                    amlCardView(aml)
                    Button { editedName = c.extractedName ?? ""; showAMLRerun = true } label: {
                        Label("Re-run screening", systemImage: "arrow.clockwise").font(.caption)
                    }.foregroundStyle(Color.brand).padding(.horizontal, 20)
                } else if depth.includesAML && c.amlStatus == nil {
                    CardView {
                        HStack(spacing: 10) {
                            Image(systemName: "clock").foregroundStyle(.secondary)
                            Text("AML screening pending...").font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.horizontal, 20)
                }

                // PoA
                if poaRunning {
                    CardView {
                        HStack(spacing: 14) {
                            ProgressView()
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Address Verification in Progress").font(.caption.weight(.semibold))
                                Text("Analysing document, extracting address data...").font(.system(size: 9)).foregroundStyle(.secondary)
                            }
                        }
                    }.padding(.horizontal, 20)
                } else if let poa = c.poaStatus {
                    CardView {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader("Address Verification", icon: "house.fill")
                            DataRow(label: "Status", value: poa, color: poa == "Approved" ? Color.pass : poa == "Declined" ? Color.fail : Color.warning, bold: true)
                            if let a = c.poaAddress { DataRow(label: "Address", value: a) }
                            if let i = c.poaIssuer { DataRow(label: "Issuer", value: i) }
                            if let w = c.poaWarnings, !w.isEmpty { Divider()
                                ForEach(w, id: \.self) { w in Label(w, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(Color.warning) }
                            }
                        }
                    }.padding(.horizontal, 20)
                } else if depth.includesPoA && c.poaStatus == nil && !amlRunning {
                    CardView {
                        HStack(spacing: 10) {
                            Image(systemName: "clock").foregroundStyle(.secondary)
                            Text("Address verification pending...").font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.horizontal, 20)
                }

                // Review section (blocked while any check runs)
                if !anyCheckRunning {
                    reviewSection
                } else {
                    CardView {
                        HStack(spacing: 10) {
                            Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary)
                            Text("Review available after all checks complete").font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.horizontal, 20)
                }

                // Notes
                VStack(alignment: .leading, spacing: 6) {
                    Text("Agent Notes").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    TextField("Observations...", text: $notes, axis: .vertical).lineLimit(2...4).font(.caption)
                        .padding(12).background(Color.surfaceMuted).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    if notes != (c.agentNotes ?? "") && !notes.isEmpty {
                        Button("Save") { vm.updateAgentNotes(checkId: c.id, notes: notes) }.font(.caption.weight(.semibold)).foregroundStyle(Color.brand)
                    }
                }.padding(.horizontal, 20)

                // Images
                if let paths = c.documentImagePaths, !paths.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(paths, id: \.self) { fn in
                                if let d = vm.loadDocumentImage(filename: fn), let img = UIImage(data: d) {
                                    Image(uiImage: img).resizable().scaledToFill().frame(width: 100, height: 66)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous)).shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                                }
                            }
                        }.padding(.horizontal, 20)
                    }
                }

                // API data
                if c.rawIDResponse != nil || c.rawAMLResponse != nil {
                    DisclosureGroup { VStack(alignment: .leading, spacing: 8) {
                        if let r = c.rawIDResponse { jsonBlock("ID", r) }
                        if let r = c.rawAMLResponse { jsonBlock("AML", r) }
                        if let r = c.rawPoAResponse { jsonBlock("PoA", r) }
                    } } label: { Label("API Data", systemImage: "chevron.left.forwardslash.chevron.right").font(.caption.weight(.medium)).foregroundStyle(.secondary) }
                        .padding(.horizontal, 20)
                }

                // Report
                VStack(spacing: 8) {
                    Button {
                        pdfURL = vm.generateReport(checkId: c.id)
                        if pdfURL != nil { showPDFPreview = true }
                    } label: {
                        Label("View PDF Report", systemImage: "doc.richtext")
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    if pdfURL != nil {
                        Button { showShare = true } label: {
                            Label("Share Report", systemImage: "square.and.arrow.up")
                                .font(.subheadline)
                        }
                        .foregroundStyle(Color.brand)
                    }
                }
                .padding(.horizontal, 20)

                Spacer(minLength: 30)
            }
            .padding(.vertical, 12)
            .animation(.smooth(duration: 0.35), value: c.status)
            .animation(.smooth(duration: 0.35), value: amlRunning)
            .animation(.smooth(duration: 0.35), value: poaRunning)
            .animation(.smooth(duration: 0.35), value: c.amlStatus)
            .animation(.smooth(duration: 0.35), value: c.poaStatus)
        }
    }

    // ═══════════════════════════════════════════
    // MARK: - Pipeline
    // ═══════════════════════════════════════════

    @State private var amlRunning = false
    @State private var poaRunning = false

    private var anyCheckRunning: Bool { amlRunning || poaRunning }

    private func runPipeline() async {
        guard let front = frontImage else { return }
        busy = true; error = nil; progressText = "Scanning document..."

        do {
            // ── STEP A: ID scan ──
            let idScan = try await vm.runIDScan(checkId: c.id, frontImage: front, backImage: backImage)
            idResult = idScan.idResult

            if let m = idScan.nameMismatch { mismatch = m; showNameMismatch = true }
            if let det = idScan.idResult?.documentType {
                let d = det.lowercased().replacingOccurrences(of: "_", with: " "), e = docType.rawValue.lowercased()
                if !d.contains(e) && !e.contains(d) { detectedType = det.replacingOccurrences(of: "_", with: " ").capitalized; showDocMismatch = true }
            }

            // Show results immediately — ID card visible, AML/PoA show spinners
            busy = false; progressText = ""
            withAnimation { step = .results }

            // ── STEP B: AML (auto, visible as in-progress) ──
            if depth.includesAML {
                amlRunning = true
                do {
                    let aml = try await vm.runAMLScreening(checkId: c.id, monitoring: monitoring)
                    amlResult = aml
                } catch {
                    self.error = "AML screening failed: \(error.localizedDescription)"
                }
                amlRunning = false
            } else {
                vm.finalizeIDOnly(checkId: c.id)
            }

            // ── STEP C: PoA (auto after AML, visible as in-progress) ──
            if depth.includesPoA, let poaImg = poaImage {
                poaRunning = true
                do {
                    _ = try await vm.runPoA(checkId: c.id, documentImage: poaImg, expectedName: c.extractedName, expectedAddress: nil) { _ in }
                } catch {
                    self.error = "Address verification failed: \(error.localizedDescription)"
                }
                poaRunning = false
            }

        } catch {
            self.error = error.localizedDescription
            busy = false; progressText = ""
        }
    }

    private func rerunAML() async {
        busy = true; error = nil; progressText = "Re-running screening..."
        do {
            let opts = VerificationAPIService.AMLOptions(includeAdverseMedia: true, includeMonitoring: monitoring)
            let (resp, raw) = try await VerificationAPIService.shared.screenAML(fullName: editedName, dateOfBirth: c.dateOfBirth, nationality: vm.toISO2(c.nationality), documentNumber: c.documentNumber, vendorData: c.id, options: opts)
            amlResult = resp.aml
            vm.updateAML(checkId: c.id, result: resp.aml, rawJSON: String(data: raw, encoding: .utf8) ?? "")
        } catch { self.error = error.localizedDescription }
        busy = false; progressText = ""
    }

    // ═══════════════════════════════════════════
    // MARK: - Review Section
    // ═══════════════════════════════════════════

    private var reviewSection: some View {
        CardView {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("Agent Review", icon: "person.badge.shield.checkmark")
                if let d = c.reviewDecision {
                    HStack(spacing: 10) {
                        Image(systemName: d == .approved ? "checkmark.seal.fill" : d == .declined ? "xmark.seal.fill" : "flag.fill")
                            .foregroundStyle(d == .approved ? Color.pass : d == .declined ? Color.fail : Color.warning)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Manually \(d.rawValue)").font(.caption.weight(.semibold))
                            if let by = c.reviewedBy, let at = c.reviewedAt { Text("by \(by), \(at.formatted(date: .abbreviated, time: .shortened))").font(.system(size: 9)).foregroundStyle(.secondary) }
                            if let r = c.reviewReason, !r.isEmpty { Text(r).font(.caption).foregroundStyle(.secondary).italic() }
                        }
                    }
                    Divider()
                }
                HStack(spacing: 8) {
                    reviewBtn("Approve", "checkmark", Color.pass, .approved)
                    reviewBtn("Flag", "flag", Color.warning, .flagged)
                    reviewBtn("Decline", "xmark", Color.fail, .declined)
                }.buttonStyle(.plain)
            }
        }.padding(.horizontal, 20)
    }

    private func reviewBtn(_ label: String, _ icon: String, _ color: Color, _ decision: KYCCheck.ReviewDecision) -> some View {
        Button { pendingReview = decision; showReviewSheet = true } label: {
            Label(label, systemImage: icon).font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity).padding(.vertical, 10)
                .background(color.opacity(0.1)).foregroundStyle(color)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    // ═══════════════════════════════════════════
    // MARK: - Loaded Results
    // ═══════════════════════════════════════════

    private var loadedIDResult: IDResult? {
        guard let raw = c.rawIDResponse, let d = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(IDVerificationResponse.self, from: d).idVerification
    }
    private var loadedAMLResult: AMLResult? {
        guard let raw = c.rawAMLResponse, let d = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(AMLScreeningResponse.self, from: d).aml
    }

    // ═══════════════════════════════════════════
    // MARK: - ID Card
    // ═══════════════════════════════════════════

    private func idCard(_ id: IDResult) -> some View {
        CardView {
            VStack(alignment: .leading, spacing: 8) {
                if let dt = id.documentType {
                    HStack(spacing: 8) {
                        Image(systemName: docIcon(dt)).foregroundStyle(Color.brand)
                        Text(dt.replacingOccurrences(of: "_", with: " ").capitalized).font(.subheadline.bold())
                        Spacer()
                        if let s = id.status {
                            Text(s).font(.system(size: 10, weight: .bold)).padding(.horizontal, 8).padding(.vertical, 3)
                                .background((s == "Approved" ? Color.pass : Color.fail).opacity(0.12)).foregroundStyle(s == "Approved" ? Color.pass : Color.fail).clipShape(Capsule())
                        }
                    }
                    Divider()
                }
                if !id.extractedFullName.isEmpty { DataRow(label: "Name", value: id.extractedFullName, bold: true) }
                if let v = id.documentNumber { DataRow(label: "Doc No.", value: v) }
                if let v = id.dateOfBirth { DataRow(label: "DOB", value: v + (id.age.map { " (\($0))" } ?? "")) }
                if let v = id.gender { DataRow(label: "Gender", value: v) }
                if let v = id.nationality { DataRow(label: "Nationality", value: v.uppercased()) }
                if let v = id.issuingCountry { DataRow(label: "Issuing", value: v) }
                if let v = id.expiryDate { DataRow(label: "Expires", value: v, color: expired(v) ? Color.fail : nil) }
                if let v = id.formattedAddress ?? id.address, !v.isEmpty { DataRow(label: "Address", value: v) }
                if let w = id.warnings, !w.isEmpty { Divider()
                    ForEach(Array(w.enumerated()), id: \.offset) { _, w in
                        Label(w.shortDescription ?? w.risk ?? "Warning", systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(Color.warning)
                    }
                }
            }
        }.padding(.horizontal, 20)
    }

    // ═══════════════════════════════════════════
    // MARK: - AML Card (full)
    // ═══════════════════════════════════════════

    private func amlCardView(_ aml: AMLResult) -> some View {
        VStack(spacing: 12) {
            // Summary card
            CardView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        SectionHeader("Compliance Screening", icon: "shield.checkered")
                        Spacer()
                        if let s = aml.status {
                            Text(s).font(.system(size: 10, weight: .bold)).padding(.horizontal, 8).padding(.vertical, 3)
                                .background((s == "Approved" ? Color.pass : s == "Declined" ? Color.fail : Color.warning).opacity(0.12))
                                .foregroundStyle(s == "Approved" ? Color.pass : s == "Declined" ? Color.fail : Color.warning).clipShape(Capsule())
                        }
                    }

                    if let score = aml.score {
                        HStack(spacing: 16) {
                            RiskGauge(score: score, size: 72)
                            VStack(alignment: .leading, spacing: 6) {
                                if let h = aml.totalHits {
                                    HStack(spacing: 4) {
                                        Text("\(h)").font(.title3.bold().monospacedDigit())
                                        Text(h == 1 ? "match found" : "matches found").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                if c.amlMonitoring == true {
                                    HStack(spacing: 4) {
                                        Image(systemName: "bell.badge.fill").font(.caption2).foregroundStyle(Color.brand)
                                        Text("Continuous monitoring active").font(.system(size: 9)).foregroundStyle(Color.brand)
                                    }
                                }
                            }
                            Spacer()
                        }
                    }
                }
            }.padding(.horizontal, 20)

            // Individual hit cards — one per match, full width
            if let hits = aml.hits, !hits.isEmpty {
                ForEach(Array(hits.prefix(10).enumerated()), id: \.offset) { idx, hit in
                    amlHitCard(hit, index: idx + 1)
                }
            }
        }
    }

    private func amlHitCard(_ hit: AMLHit, index: Int) -> some View {
        let isExpanded = expandedHits.contains(index)

        return VStack(alignment: .leading, spacing: 0) {
            // Header — always visible, tappable
            Button {
                withAnimation(.smooth(duration: 0.25)) {
                    if isExpanded { expandedHits.remove(index) } else { expandedHits.insert(index) }
                }
            } label: {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("#\(index)").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                            Text(hit.caption ?? "Unknown Entity").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                .lineLimit(isExpanded ? nil : 1)
                        }
                        // Dataset tags
                        if let ds = hit.datasets, !ds.isEmpty {
                            FlowLayout(spacing: 4) {
                                ForEach(ds, id: \.self) { d in
                                    Text(d).font(.system(size: 8, weight: .semibold))
                                        .padding(.horizontal, 7).padding(.vertical, 3)
                                        .background(dsColor(d).opacity(0.1))
                                        .foregroundStyle(dsColor(d))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 4) {
                        if let ms = hit.matchScore {
                            VStack(spacing: 1) {
                                Text("\(ms)%").font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundStyle(ms > 80 ? Color.fail : ms > 50 ? Color.warning : .secondary)
                                Text("match").font(.system(size: 8)).foregroundStyle(.secondary)
                            }
                        }
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(14)

            // Expanded detail — tap to reveal
            if isExpanded {
                // Risk score
                if let rs = hit.riskScore {
                    HStack {
                        Divider().frame(height: 1)
                    }
                    HStack(spacing: 14) {
                        DataRow(label: "Risk Score", value: "\(Int(rs))/100", color: rs > 70 ? Color.fail : rs > 40 ? Color.warning : Color.pass)
                        if let rv = hit.reviewStatus {
                            DataRow(label: "Review", value: rv)
                        }
                    }.padding(.horizontal, 14)
                }

                // Score breakdown bar
                if let sb = hit.scoreBreakdown {
                    VStack(spacing: 6) {
                        Divider()
                        HStack(spacing: 0) {
                            scoreBar("Name", sb.nameScore, Color.brand)
                            scoreBar("DOB", sb.dobScore, .purple)
                            scoreBar("Country", sb.countryScore, .teal)
                        }
                        .padding(.horizontal, 14).padding(.bottom, 6)
                    }
                }

                // PEP matches
                if let peps = hit.pepMatches, !peps.isEmpty {
                    detailSection("Politically Exposed Person", icon: "building.columns.fill", color: .purple) {
                        ForEach(Array(peps.enumerated()), id: \.offset) { _, pep in
                            VStack(alignment: .leading, spacing: 4) {
                                if let pos = pep.pepPosition { Text(pos).font(.caption.weight(.semibold)) }
                                if let name = pep.matchedName { Text("Matched: \(name)").font(.system(size: 10)).foregroundStyle(.secondary) }
                                if let list = pep.listName { Text("List: \(list)").font(.system(size: 10)).foregroundStyle(.secondary) }
                                if let desc = pep.description, !desc.isEmpty { Text(desc).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(6) }
                            }
                        }
                    }
                }

                // Sanction matches
                if let sxns = hit.sanctionMatches, !sxns.isEmpty {
                    detailSection("Sanctions", icon: "exclamationmark.octagon.fill", color: Color.fail) {
                        ForEach(Array(sxns.enumerated()), id: \.offset) { _, sxn in
                            VStack(alignment: .leading, spacing: 4) {
                                if let name = sxn.matchedName { Text(name).font(.caption.weight(.semibold)) }
                                if let desc = sxn.description, !desc.isEmpty { Text(desc).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(6) }
                                if let reason = sxn.reason { Text("Legal basis: \(reason)").font(.system(size: 10)).italic().foregroundStyle(.secondary) }
                                if let url = sxn.sourceUrl, let link = URL(string: url) { Link(url, destination: link).font(.system(size: 9)).lineLimit(1) }
                            }
                        }
                    }
                }

                // Adverse media
                if let media = hit.adverseMediaMatches, !media.isEmpty {
                    detailSection("Adverse Media", icon: "newspaper.fill", color: Color.warning) {
                        ForEach(Array(media.enumerated()), id: \.offset) { _, m in
                            VStack(alignment: .leading, spacing: 5) {
                                if let h = m.headline { Text(h).font(.caption.weight(.semibold)) }
                                if let s = m.summary, !s.isEmpty { Text(s).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(6) }
                                HStack(spacing: 8) {
                                    if let sent = m.sentiment {
                                        HStack(spacing: 3) {
                                            Circle().fill(sent.lowercased() == "negative" ? Color.fail : sent.lowercased() == "positive" ? Color.pass : Color.warning).frame(width: 6, height: 6)
                                            Text(sent.capitalized).font(.system(size: 9))
                                        }
                                    }
                                    if let d = m.publicationDate { Text(String(d.prefix(10))).font(.system(size: 9)).foregroundStyle(.secondary) }
                                }
                                if let url = m.sourceUrl, let link = URL(string: url) { Link(url, destination: link).font(.system(size: 9)).lineLimit(1) }
                            }
                        }
                    }
                }

                // Timeline
                if hit.firstSeen != nil || hit.lastSeen != nil {
                    VStack(spacing: 0) {
                        Divider()
                        HStack(spacing: 12) {
                            if let f = hit.firstSeen { HStack(spacing: 3) { Text("First seen").font(.system(size: 8)).foregroundStyle(.secondary); Text(String(f.prefix(10))).font(.system(size: 8, weight: .medium)) } }
                            if let l = hit.lastSeen { HStack(spacing: 3) { Text("Last seen").font(.system(size: 8)).foregroundStyle(.secondary); Text(String(l.prefix(10))).font(.system(size: 8, weight: .medium)) } }
                            Spacer()
                            if let rs = hit.reviewStatus { Text(rs).font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary) }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                    }
                }
            } else {
                // Collapsed — show a brief summary line
                if hit.pepMatches?.isEmpty == false || hit.sanctionMatches?.isEmpty == false || hit.adverseMediaMatches?.isEmpty == false {
                    HStack(spacing: 6) {
                        if let peps = hit.pepMatches, !peps.isEmpty { Label("\(peps.count) PEP", systemImage: "building.columns.fill").font(.system(size: 9)).foregroundStyle(.purple) }
                        if let sxns = hit.sanctionMatches, !sxns.isEmpty { Label("\(sxns.count) Sanction", systemImage: "exclamationmark.octagon.fill").font(.system(size: 9)).foregroundStyle(Color.fail) }
                        if let media = hit.adverseMediaMatches, !media.isEmpty { Label("\(media.count) Media", systemImage: "newspaper.fill").font(.system(size: 9)).foregroundStyle(Color.warning) }
                        Spacer()
                        Text("Tap for details").font(.system(size: 8)).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14).padding(.bottom, 10)
                }
            }
        }
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 10, y: 3)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.warning.opacity(0.15), lineWidth: 0.5))
        .padding(.horizontal, 20)
    }

    private func detailSection<Content: View>(_ title: String, icon: String, color: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: icon).font(.system(size: 10)).foregroundStyle(color)
                    Text(title).font(.system(size: 10, weight: .bold)).foregroundStyle(color)
                }
                content()
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.03))
        }
    }

    private func scoreBar(_ label: String, _ score: Int?, _ color: Color) -> some View {
        VStack(spacing: 3) {
            if let s = score {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2).fill(color.opacity(0.12)).frame(height: 6)
                        RoundedRectangle(cornerRadius: 2).fill(color).frame(width: geo.size.width * CGFloat(max(0, min(abs(s), 100))) / 100, height: 6)
                    }
                }.frame(height: 6)
                HStack(spacing: 2) {
                    Text("\(s)").font(.system(size: 9, weight: .bold, design: .rounded)).foregroundStyle(color)
                    Text(label).font(.system(size: 8)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // ═══════════════════════════════════════════
    // MARK: - Components
    // ═══════════════════════════════════════════

    private func docSlot(_ title: String, data: Data?, cam: Binding<Bool>, filePicker: Binding<Bool>, photoPicker: Binding<PhotosPickerItem?>, required: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) { Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary); if required { Text("*").foregroundStyle(Color.warning) }; Spacer()
                if data != nil { Text(isPDF(data) ? "PDF" : "Image").font(.system(size: 8, weight: .bold)).padding(.horizontal, 6).padding(.vertical, 2).background(Color.brand.opacity(0.1)).foregroundStyle(Color.brand).clipShape(Capsule()) } }
            if let data {
                ZStack(alignment: .bottomTrailing) {
                    if let img = previewImage(data) { Image(uiImage: img).resizable().scaledToFit().frame(maxHeight: 140).frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous)).shadow(color: .black.opacity(0.1), radius: 6, y: 3) }
                    else { HStack(spacing: 8) { Image(systemName: "doc.fill").font(.title3).foregroundStyle(Color.brand); Text("\(data.count / 1024) KB").font(.caption2).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).padding(14).background(Color.surfaceMuted).clipShape(RoundedRectangle(cornerRadius: 12)) }
                    Menu { Button { cam.wrappedValue = true } label: { Label("Camera", systemImage: "camera") }; PhotosPicker(selection: photoPicker, matching: .images) { Label("Photos", systemImage: "photo") }; Button { filePicker.wrappedValue = true } label: { Label("File", systemImage: "folder") } } label: { Image(systemName: "pencil.circle.fill").font(.title3).foregroundStyle(.white, Color.brand).shadow(radius: 4).padding(6) }
                }
            } else {
                HStack(spacing: 8) {
                    Button { cam.wrappedValue = true } label: { VStack(spacing: 4) { Image(systemName: "camera.fill").font(.system(size: 16)); Text("Camera").font(.system(size: 9, weight: .medium)) }.frame(maxWidth: .infinity).frame(height: 64).background(Color.brand.opacity(0.06)).foregroundStyle(Color.brand).clipShape(RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.brand.opacity(0.15))) }
                    PhotosPicker(selection: photoPicker, matching: .images) { VStack(spacing: 4) { Image(systemName: "photo.fill").font(.system(size: 16)); Text("Photos").font(.system(size: 9, weight: .medium)) }.frame(maxWidth: .infinity).frame(height: 64).background(Color.surfaceMuted).foregroundStyle(.secondary).clipShape(RoundedRectangle(cornerRadius: 12)) }
                    Button { filePicker.wrappedValue = true } label: { VStack(spacing: 4) { Image(systemName: "folder.fill").font(.system(size: 16)); Text("File").font(.system(size: 9, weight: .medium)) }.frame(maxWidth: .infinity).frame(height: 64).background(Color.surfaceMuted).foregroundStyle(.secondary).clipShape(RoundedRectangle(cornerRadius: 12)) }
                }
            }
        }
    }

    private func jsonBlock(_ t: String, _ raw: String) -> some View {
        VStack(alignment: .leading, spacing: 3) { Text(t).font(.caption.bold())
            ScrollView(.horizontal) { Text(prettyJSON(raw)).font(.system(size: 8, design: .monospaced)).foregroundStyle(.tertiary) }.frame(maxHeight: 180).padding(8).background(Color.surfaceMuted).clipShape(RoundedRectangle(cornerRadius: 8)) }
    }

    // ═══════════════════════════════════════════
    // MARK: - Helpers
    // ═══════════════════════════════════════════

    private func prettyJSON(_ raw: String) -> String { guard let d = raw.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d), let f = try? JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .sortedKeys]), let s = String(data: f, encoding: .utf8) else { return raw }; return s }
    private func docIcon(_ t: String) -> String { let l = t.lowercased(); if l.contains("passport") { return "book.closed.fill" }; if l.contains("driver") { return "car.fill" }; if l.contains("residence") { return "building.2.fill" }; return "person.text.rectangle.fill" }
    private func expired(_ s: String) -> Bool { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.date(from: s).map { $0 < Date() } ?? false }
    private func isPDF(_ data: Data?) -> Bool { guard let d = data, d.count > 4 else { return false }; let h = [UInt8](d.prefix(4)); return h[0] == 0x25 && h[1] == 0x50 && h[2] == 0x44 && h[3] == 0x46 }
    private func previewImage(_ data: Data) -> UIImage? { if let img = UIImage(data: data) { return img }; return renderPDF(data) }
    private func renderPDF(_ data: Data) -> UIImage? { guard let p = CGDataProvider(data: data as CFData), let doc = CGPDFDocument(p), let pg = doc.page(at: 1) else { return nil }; let r = pg.getBoxRect(.mediaBox); let s: CGFloat = 2; let sz = CGSize(width: r.width * s, height: r.height * s); return UIGraphicsImageRenderer(size: sz).image { c in UIColor.white.setFill(); c.fill(CGRect(origin: .zero, size: sz)); c.cgContext.translateBy(x: 0, y: sz.height); c.cgContext.scaleBy(x: s, y: -s); c.cgContext.drawPDFPage(pg) } }
    private func dsColor(_ n: String) -> Color { let l = n.lowercased(); if l.contains("sanction") { return Color.fail }; if l.contains("pep") { return .purple }; if l.contains("adverse") || l.contains("media") { return Color.warning }; return .secondary }

    @MainActor private func loadPhoto(_ item: PhotosPickerItem?) async -> Data? {
        guard let item else { return nil }; imgError = nil
        do { guard let d = try await item.loadTransferable(type: Data.self) else { return nil }; let r = ImageValidator.validate(d); if r.isValid, let c = r.compressedData { return c }; imgError = r.error?.localizedDescription } catch { imgError = "Failed to load" }; return nil
    }

    private func loadFile(_ url: URL, forAPI: Bool) -> Data? {
        imgError = nil; guard url.startAccessingSecurityScopedResource() else { imgError = "Cannot access file"; return nil }; defer { url.stopAccessingSecurityScopedResource() }
        guard let data = try? Data(contentsOf: url) else { imgError = "Cannot read file"; return nil }
        if url.pathExtension.lowercased() == "pdf" || isPDF(data) { if forAPI { guard let img = renderPDF(data), let j = img.jpegData(compressionQuality: 0.85) else { imgError = "Could not render PDF"; return nil }; return j } else { if data.count > 15*1024*1024 { imgError = "PDF exceeds 15MB"; return nil }; return data } }
        let r = ImageValidator.validate(data); if r.isValid, let c = r.compressedData { return c }; imgError = r.error?.localizedDescription; return nil
    }
}

// MARK: - Camera / File Picker / Share

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
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController { let p = UIDocumentPickerViewController(forOpeningContentTypes: [.jpeg, .png, .heic, .tiff, .webP, .pdf], asCopy: true); p.delegate = context.coordinator; return p }
    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Co { Co(self) }
    class Co: NSObject, UIDocumentPickerDelegate { let parent: FilePicker; init(_ p: FilePicker) { parent = p }
        func documentPicker(_ c: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { if let u = urls.first { parent.onPick(u) }; parent.dismiss() }
        func documentPickerWasCancelled(_ c: UIDocumentPickerViewController) { parent.dismiss() } }
}

// MARK: - PDF Preview

import PDFKit

struct PDFPreviewView: View {
    let url: URL
    var onShare: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PDFKitView(url: url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Report")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { onShare() }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
        }
    }
}

struct PDFKitView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.document = PDFDocument(url: url)
        pdfView.backgroundColor = UIColor.systemGroupedBackground
        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        if pdfView.document?.documentURL != url {
            pdfView.document = PDFDocument(url: url)
        }
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
