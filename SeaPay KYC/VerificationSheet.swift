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

    // Results — pipeline needs these for configView
    @State private var idResult: IDResult?; @State private var amlResult: AMLResult?
    @State private var expandedSections: Set<String> = ["identity"]
    @State private var notes = ""


    var body: some View {
        NavigationStack {
            bodyContent
        }
    }

    private var bodyContent: some View {
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

    private var resultsView: some View {
        PersonResultsView(vm: vm, checkId: c.id)
    }

    // Results view code is in PersonResultsView.swift

    // Keeping expandBinding for configView usage
    private func expandBinding(_ key: String) -> Binding<Bool> {
        Binding(get: { expandedSections.contains(key) }, set: { if $0 { expandedSections.insert(key) } else { expandedSections.remove(key) } })
    }

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

    // rerunAML, exportVCard, runPoAOnly moved to PersonResultsView.swift

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
            // Wait for push animation to fully complete before generating PDF
            try? await Task.sleep(nanoseconds: 450_000_000)
            // Generate PDF — this is CPU-heavy, keep the spinner visible until done
            let url = vm.generateReport(checkId: checkId)
            withAnimation(.easeInOut(duration: 0.2)) { pdfURL = url }
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

// MARK: - Contact & Contract Editor (Jony Ive flow)

struct ContactEditorSheet: View {
    @ObservedObject var vm: KYCViewModel
    let checkId: String
    let check: KYCCheck
    @Environment(\.dismiss) private var dismiss

    @State private var phone = ""; @State private var email = ""
    @State private var ecName = ""; @State private var ecPhone = ""; @State private var ecRelation = ""
    @State private var nokName = ""; @State private var nokRelation = ""
    @State private var availability: KYCCheck.AvailabilityStatus?
    @State private var hasStart = false; @State private var hasEnd = false
    @State private var contractStart = Date()
    @State private var contractEnd = Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date()
    @State private var wages = ""; @State private var currency = "USD"
    @State private var hoursOfWork = ""; @State private var leaveEntitlement = ""
    @State private var portOfEngagement = ""; @State private var manningAgency = ""
    @State private var cbaReference = ""; @State private var repatriationPort = ""
    @State private var mlcCompliant: Bool? = nil
    @State private var showSEAFilePicker = false
    @State private var seaExtracting = false; @State private var seaError: String?

    private let currencies = ["USD", "EUR", "GBP", "NOK", "SGD", "AED", "PHP", "INR"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                editorScroll
                saveBar
            }
            .background(Color.surface.ignoresSafeArea())
            .navigationTitle("Personal Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear { loadExisting() }
            .sheet(isPresented: $showSEAFilePicker) {
                FilePicker { url in
                    let data: Data? = url.startAccessingSecurityScopedResource()
                        ? { defer { url.stopAccessingSecurityScopedResource() }; return try? Data(contentsOf: url) }()
                        : try? Data(contentsOf: url)
                    if let data { Task { await extractSEA(data) } }
                }
            }
        }
    }

    // MARK: - Scroll Content

    private var editorScroll: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                seaUploadCard
                contactCard
                emergencyCard
                contractCard
                wagesCard
                maritimeCard
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 20)
        }
    }

    // MARK: - SEA Upload Card

    private var seaUploadCard: some View {
        VStack(spacing: 8) {
            if seaExtracting {
                HStack(spacing: 10) { ProgressView().controlSize(.small); Text("Reading contract...").font(Typo.meta).foregroundStyle(.secondary) }
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
            } else {
                Button { showSEAFilePicker = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "doc.text.viewfinder").font(.system(size: 20)).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Upload Employment Agreement").font(Typo.body)
                            Text("Auto-fills all fields from PDF or photo").font(Typo.meta).foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.quaternary)
                    }
                    .padding(14)
                }
                .buttonStyle(.plain)
            }
            if let e = seaError { Text(e).font(Typo.meta).foregroundStyle(Color.flagged).padding(.horizontal, 14) }
        }
        .background(Color.surfaceMuted.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Contact Card

    private var contactCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Contact")
            ef("Phone", text: $phone, prompt: "+30 697 123 4567", keyboard: .phonePad)
            ef("Email", text: $email, prompt: "name@example.com", keyboard: .emailAddress)
        }
        .padding(14)
        .background(Color.surfaceMuted.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Emergency Card

    private var emergencyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Emergency & Next of Kin")
            ef("Emergency Name", text: $ecName, prompt: "Full name")
            HStack(spacing: 10) {
                ef("Phone", text: $ecPhone, prompt: "+30 697...", keyboard: .phonePad)
                ef("Relation", text: $ecRelation, prompt: "Spouse")
            }
            Divider().padding(.vertical, 2)
            HStack(spacing: 10) {
                ef("Next of Kin", text: $nokName, prompt: "Full name")
                ef("Relation", text: $nokRelation, prompt: "Spouse")
            }
        }
        .padding(14)
        .background(Color.surfaceMuted.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Contract Card

    private var contractCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Contract")
            // Availability pills
            HStack(spacing: 6) {
                ForEach(KYCCheck.AvailabilityStatus.allCases) { s in
                    Button { availability = availability == s ? nil : s } label: {
                        Text(s.rawValue).font(Typo.meta)
                            .foregroundStyle(availability == s ? .primary : .secondary)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(availability == s ? Color.primary.opacity(0.08) : Color.surfaceMuted)
                            .clipShape(Capsule())
                    }.buttonStyle(.plain)
                }
            }
            // Dates
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Start", isOn: $hasStart).font(Typo.meta).tint(.primary)
                    if hasStart { DatePicker("", selection: $contractStart, displayedComponents: .date).labelsHidden() }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("End", isOn: $hasEnd).font(Typo.meta).tint(.primary)
                    if hasEnd { DatePicker("", selection: $contractEnd, displayedComponents: .date).labelsHidden() }
                }
            }
        }
        .padding(14)
        .background(Color.surfaceMuted.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Wages Card

    private var wagesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Wages & Terms")
            HStack(spacing: 10) {
                ef("Amount", text: $wages, prompt: "3500.00", keyboard: .decimalPad)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Currency").font(Typo.meta).foregroundStyle(.tertiary)
                    Menu {
                        ForEach(currencies, id: \.self) { c in Button(c) { currency = c } }
                    } label: {
                        HStack(spacing: 4) { Text(currency).font(Typo.body); Image(systemName: "chevron.up.chevron.down").font(.system(size: 8)) }
                            .foregroundStyle(.primary).padding(11).frame(minWidth: 80)
                            .background(Color.surfaceMuted).clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            HStack(spacing: 10) {
                ef("Hours/Day", text: $hoursOfWork, prompt: "8")
                ef("Leave/Month", text: $leaveEntitlement, prompt: "2.5 days")
            }
        }
        .padding(14)
        .background(Color.surfaceMuted.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Maritime Card

    private var maritimeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Maritime")
            HStack(spacing: 10) {
                ef("Port", text: $portOfEngagement, prompt: "Manila")
                ef("Repatriation", text: $repatriationPort, prompt: "Home port")
            }
            ef("Manning Agency", text: $manningAgency, prompt: "Agency name")
            ef("CBA Reference", text: $cbaReference, prompt: "ITF TCC, etc.")
            // MLC
            HStack {
                Text("MLC 2006").font(Typo.meta).foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 0) {
                    mlcPill("Yes", value: true); mlcPill("No", value: false); mlcPill("—", value: nil)
                }.clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(14)
        .background(Color.surfaceMuted.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Save Bar

    private var saveBar: some View {
        VStack(spacing: 0) {
            Divider()
            Button { save(); dismiss() } label: { Text("Save") }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 24).padding(.vertical, 10)
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Helpers

    private func ef(_ label: String, text: Binding<String>, prompt: String, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(Typo.meta).foregroundStyle(.tertiary)
            TextField(prompt, text: text)
                .font(Typo.body).keyboardType(keyboard).autocorrectionDisabled()
                .textInputAutocapitalization(keyboard == .emailAddress ? .never : .words)
                .padding(11).background(Color.surfaceMuted).clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func mlcPill(_ label: String, value: Bool?) -> some View {
        Button { mlcCompliant = value } label: {
            Text(label).font(Typo.meta)
                .foregroundStyle(mlcCompliant == value ? .primary : .secondary)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(mlcCompliant == value ? Color.primary.opacity(0.08) : Color.surfaceMuted)
        }.buttonStyle(.plain)
    }

    // MARK: - SEA Extraction

    private func extractSEA(_ data: Data) async {
        seaExtracting = true; seaError = nil
        do {
            let sea = try await ClaudeService.shared.extractSEA(documentData: data)
            // Auto-fill fields from extraction
            if let v = sea.phoneNumber, !v.isEmpty, phone.isEmpty { phone = v }
            if let v = sea.emailAddress, !v.isEmpty, email.isEmpty { email = v }
            if let v = sea.emergencyContactName, !v.isEmpty, ecName.isEmpty {
                ecName = v; ecPhone = sea.emergencyContactPhone ?? ""; ecRelation = sea.emergencyContactRelation ?? ""
            }
            if let v = sea.nextOfKinName, !v.isEmpty, nokName.isEmpty {
                nokName = v; nokRelation = sea.nextOfKinRelation ?? ""
            }
            if let v = sea.wages, !v.isEmpty, wages.isEmpty { wages = v }
            if let v = sea.currency, !v.isEmpty { currency = v }
            if let v = sea.hoursOfWork, !v.isEmpty, hoursOfWork.isEmpty { hoursOfWork = v }
            if let v = sea.leaveEntitlement, !v.isEmpty, leaveEntitlement.isEmpty { leaveEntitlement = v }
            if let v = sea.portOfEngagement, !v.isEmpty, portOfEngagement.isEmpty { portOfEngagement = v }
            if let v = sea.manningAgency, !v.isEmpty, manningAgency.isEmpty { manningAgency = v }
            if let v = sea.cbaReference, !v.isEmpty, cbaReference.isEmpty { cbaReference = v }
            if let v = sea.repatriationPort, !v.isEmpty, repatriationPort.isEmpty { repatriationPort = v }
            if let v = sea.mlcCompliant { mlcCompliant = v }
            let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
            if let s = sea.contractStart, let d = fmt.date(from: s), !hasStart { hasStart = true; contractStart = d }
            if let e = sea.contractEnd, let d = fmt.date(from: e), !hasEnd { hasEnd = true; contractEnd = d }
            Haptics.success()
        } catch {
            seaError = "Extraction failed: \(error.localizedDescription)"
        }
        seaExtracting = false
    }

    // MARK: - Load / Save

    private func loadExisting() {
        phone = check.phoneNumber ?? ""
        email = check.emailAddress ?? ""
        if let ec = check.emergencyContact { ecName = ec.name; ecPhone = ec.phone; ecRelation = ec.relationship }
        if let nok = check.nextOfKin { nokName = nok.name; nokRelation = nok.relationship }
        availability = check.availabilityStatus
        if let s = check.contractStartDate { hasStart = true; contractStart = s }
        if let e = check.contractEndDate { hasEnd = true; contractEnd = e }
        wages = check.wages ?? ""; currency = check.currency ?? "USD"
        hoursOfWork = check.hoursOfWork ?? ""; leaveEntitlement = check.leaveEntitlement ?? ""
        portOfEngagement = check.portOfEngagement ?? ""; manningAgency = check.manningAgency ?? ""
        cbaReference = check.cbaReference ?? ""; repatriationPort = check.repatriationPort ?? ""
        mlcCompliant = check.mlcCompliant
    }

    private func save() {
        vm.updatePhoneNumber(checkId: checkId, phone: phone)
        vm.updateEmailAddress(checkId: checkId, email: email)
        vm.updateEmergencyContact(checkId: checkId, contact: ecName.isEmpty ? nil : EmergencyContact(name: ecName, phone: ecPhone, relationship: ecRelation))
        vm.updateNextOfKin(checkId: checkId, kin: nokName.isEmpty ? nil : NextOfKin(name: nokName, relationship: nokRelation))
        vm.updateAvailabilityStatus(checkId: checkId, status: availability)
        vm.updateContractDates(checkId: checkId, start: hasStart ? contractStart : nil, end: hasEnd ? contractEnd : nil)
        // SEA fields — direct update
        guard let i = vm.checks.firstIndex(where: { $0.id == checkId }) else { return }
        vm.checks[i].wages = wages.isEmpty ? nil : wages
        vm.checks[i].currency = currency
        vm.checks[i].hoursOfWork = hoursOfWork.isEmpty ? nil : hoursOfWork
        vm.checks[i].leaveEntitlement = leaveEntitlement.isEmpty ? nil : leaveEntitlement
        vm.checks[i].portOfEngagement = portOfEngagement.isEmpty ? nil : portOfEngagement
        vm.checks[i].manningAgency = manningAgency.isEmpty ? nil : manningAgency
        vm.checks[i].cbaReference = cbaReference.isEmpty ? nil : cbaReference
        vm.checks[i].repatriationPort = repatriationPort.isEmpty ? nil : repatriationPort
        vm.checks[i].mlcCompliant = mlcCompliant
        vm.saveChecks()
        if let vid = vm.checks[i].vesselId { vm.autoPushVessel(vesselId: vid) }
        Haptics.success()
    }
}

// MARK: - Photo Library Transferable

struct PhotoTransferable: Transferable {
    let data: Data
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .jpeg) { data in
            PhotoTransferable(data: data)
        }
        DataRepresentation(importedContentType: .png) { data in
            PhotoTransferable(data: data)
        }
        DataRepresentation(importedContentType: .heic) { data in
            if let img = UIImage(data: data), let jpeg = img.jpegData(compressionQuality: 0.85) {
                return PhotoTransferable(data: jpeg)
            }
            return PhotoTransferable(data: data)
        }
        DataRepresentation(importedContentType: .image) { data in
            if let img = UIImage(data: data), let jpeg = img.jpegData(compressionQuality: 0.85) {
                return PhotoTransferable(data: jpeg)
            }
            return PhotoTransferable(data: data)
        }
    }
}
