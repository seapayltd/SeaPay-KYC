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
    private var hasResults: Bool { c.rawIDResponse != nil }

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
    @State private var resultTab = 0 // 0=identity, 1=compliance, 2=address
    @State private var expandedHits: Set<Int> = []

    // Review
    @State private var editedName = ""; @State private var showAMLRerun = false
    @State private var reviewReason = ""; @State private var showReviewSheet = false; @State private var pendingReview: KYCCheck.ReviewDecision?
    @State private var notes = ""

    // PDF
    @State private var pdfURL: URL?; @State private var showPDF = false; @State private var showShare = false

    var body: some View {
        NavigationStack {
            Group {
                if hasResults { resultsView }
                else if busy { processingView }
                else { configView }
            }
            .background(Color.surface.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { Text(c.customerName).font(Typo.body) }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { saveNotes(); dismiss() } }
                if hasResults {
                    ToolbarItem(placement: .primaryAction) {
                        Button { pdfURL = vm.generateReport(checkId: c.id); if pdfURL != nil { showPDF = true } } label: {
                            Image(systemName: "square.and.arrow.up").font(.body)
                        }
                    }
                }
            }
            .onAppear { notes = c.agentNotes ?? ""; if let d = c.expectedDocType { docType = d }; if let d = c.investigationDepth { depth = d }; if hasResults { loadResults() } }
            .fullScreenCover(isPresented: $showFrontCam) { CameraCapture(result: $frontImage).ignoresSafeArea() }
            .fullScreenCover(isPresented: $showBackCam) { CameraCapture(result: $backImage).ignoresSafeArea() }
            .fullScreenCover(isPresented: $showPoACam) { CameraCapture(result: $poaImage).ignoresSafeArea() }
            .sheet(isPresented: $showFrontFile) { FilePicker { url in frontImage = loadFile(url, forAPI: true) } }
            .sheet(isPresented: $showBackFile) { FilePicker { url in backImage = loadFile(url, forAPI: true) } }
            .sheet(isPresented: $showPoAFile) { FilePicker { url in poaImage = loadFile(url, forAPI: false) } }
            .sheet(isPresented: $showPDF) { if let url = pdfURL { PDFPreviewSheet(url: url, onShare: { showShare = true }) } }
            .sheet(isPresented: $showShare) { if let url = pdfURL { ActivityView(items: [url]) } }
            .alert("Re-run Screening", isPresented: $showAMLRerun) {
                TextField("Full name", text: $editedName)
                Button("Screen") { Task { await rerunAML() } }; Button("Cancel", role: .cancel) {}
            } message: { Text("Edit the name and re-run compliance screening.") }
            .alert("Review Decision", isPresented: $showReviewSheet) {
                TextField("Reason", text: $reviewReason)
                if let d = pendingReview { Button(d.rawValue) { vm.submitReview(checkId: c.id, decision: d, reason: reviewReason); reviewReason = "" } }
                Button("Cancel", role: .cancel) { reviewReason = "" }
            } message: { Text("Recorded in the audit trail and PDF report.") }
        }
    }

    private func saveNotes() { if !notes.isEmpty && notes != (c.agentNotes ?? "") { vm.updateAgentNotes(checkId: c.id, notes: notes) } }

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
            // Pinned verdict
            if !amlRunning && !poaRunning {
                VerdictBanner(status: c.status).padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 4)
            } else {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(amlRunning ? "Running compliance screening..." : "Verifying address...").font(Typo.meta).foregroundStyle(.secondary)
                    Spacer()
                }.padding(.horizontal, 20).padding(.vertical, 12)
            }

            // Tabs
            Picker("", selection: $resultTab) {
                Text("Identity").tag(0)
                Text("Compliance").tag(1)
                if c.poaStatus != nil || depth.includesPoA { Text("Address").tag(2) }
            }
            .pickerStyle(.segmented).padding(.horizontal, 16).padding(.bottom, 8)

            // Tab content
            TabView(selection: $resultTab) {
                identityTab.tag(0)
                complianceTab.tag(1)
                addressTab.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // Pinned actions
            if !amlRunning && !poaRunning {
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

    // ── Identity Tab ──
    private var identityTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let id = idResult {
                    if let dt = id.documentType {
                        Text(dt.replacingOccurrences(of: "_", with: " ").capitalized).font(Typo.context)
                    }
                    if !id.extractedFullName.isEmpty { DataRow(label: "Name", value: id.extractedFullName, bold: true) }
                    if let v = id.documentNumber { DataRow(label: "Number", value: v) }
                    if let v = id.dateOfBirth { DataRow(label: "DOB", value: v + (id.age.map { " (\($0))" } ?? "")) }
                    if let v = id.nationality { DataRow(label: "Nationality", value: v.uppercased()) }
                    if let v = id.issuingCountry { DataRow(label: "Issued by", value: v) }
                    if let v = id.expiryDate { DataRow(label: "Expires", value: v, color: expired(v) ? .flagged : nil) }
                    if let v = id.formattedAddress ?? id.address, !v.isEmpty { DataRow(label: "Address", value: v) }
                    if let w = id.warnings, !w.isEmpty {
                        Divider()
                        ForEach(Array(w.enumerated()), id: \.offset) { _, w in
                            Text(w.shortDescription ?? w.risk ?? "").font(Typo.meta).foregroundStyle(Color.review)
                        }
                    }
                }
                // Images
                if let paths = c.documentImagePaths, !paths.isEmpty {
                    Divider()
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(paths, id: \.self) { fn in
                                if let d = vm.loadDocumentImage(filename: fn), let img = UIImage(data: d) {
                                    Image(uiImage: img).resizable().scaledToFill().frame(width: 80, height: 54).clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                    }
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
            .padding(20)
        }
    }

    // ── Compliance Tab ──
    private var complianceTab: some View {
        ScrollView {
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
                    Text("No compliance data").font(Typo.meta).foregroundStyle(.quaternary)
                }
            }
            .padding(20)
        }
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

    // ── Address Tab ──
    private var addressTab: some View {
        ScrollView {
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
            .padding(20)
        }
    }

    // ═══════════════════════════════════════════
    // MARK: - Review Buttons (pinned)
    // ═══════════════════════════════════════════

    private func reviewButton(_ label: String, _ color: Color, _ decision: KYCCheck.ReviewDecision) -> some View {
        Button { pendingReview = decision; showReviewSheet = true } label: {
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
        if let raw = c.rawIDResponse, let d = raw.data(using: .utf8) { idResult = try? JSONDecoder().decode(IDVerificationResponse.self, from: d).idVerification }
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
        imgError = nil; guard url.startAccessingSecurityScopedResource() else { return nil }; defer { url.stopAccessingSecurityScopedResource() }
        guard let data = try? Data(contentsOf: url) else { return nil }
        if isPDF(data) { if forAPI { guard let img = renderPDF(data), let j = img.jpegData(compressionQuality: 0.85) else { return nil }; return j } else { return data.count <= 15*1024*1024 ? data : nil } }
        let r = ImageValidator.validate(data); if r.isValid, let c = r.compressedData { return c }; imgError = r.error?.localizedDescription; return nil
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
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController { let p = UIDocumentPickerViewController(forOpeningContentTypes: [.jpeg, .png, .heic, .tiff, .webP, .pdf], asCopy: true); p.delegate = context.coordinator; return p }
    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Co { Co(self) }
    class Co: NSObject, UIDocumentPickerDelegate { let parent: FilePicker; init(_ p: FilePicker) { parent = p }
        func documentPicker(_ c: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { if let u = urls.first { parent.onPick(u) }; parent.dismiss() }
        func documentPickerWasCancelled(_ c: UIDocumentPickerViewController) { parent.dismiss() } }
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
