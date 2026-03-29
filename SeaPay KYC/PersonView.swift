//
//  PersonView.swift
//  OceanCheck
//
//  Full-screen person view — pushed via NavigationLink.
//  Routes to config (pre-verification) or results (post-verification).
//

import SwiftUI
import PhotosUI

/// Wrapper type so person navigation doesn't collide with vessel ID navigation (both String)
struct PersonNavID: Hashable {
    let checkId: String
}

struct PersonView: View {
    @ObservedObject var vm: KYCViewModel
    let checkId: String

    private var c: KYCCheck { vm.checks.first(where: { $0.id == checkId }) ?? KYCCheck(id: checkId, customerId: "", customerName: "Unknown", agentId: "", agentName: "", checkType: .idVerification, status: .pending, entityType: .seafarer, createdAt: Date()) }
    private var hasResults: Bool { c.rawIDResponse != nil || c.completedAt != nil }
    private var isExpiredSession: Bool { c.sessionId != nil && c.status == .incomplete && c.completedAt != nil }

    var body: some View {
        Group {
            if hasResults && !isExpiredSession {
                PersonResultsView(vm: vm, checkId: checkId)
            } else {
                PersonConfigView(vm: vm, checkId: checkId)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { Text(c.displayName).font(Typo.body).lineLimit(1) }
        }
        .background(Color.surface.ignoresSafeArea())
    }
}

// MARK: - Config View (pre-verification)

struct PersonConfigView: View {
    @ObservedObject var vm: KYCViewModel
    let checkId: String

    private var c: KYCCheck { vm.checks.first(where: { $0.id == checkId }) ?? KYCCheck(id: checkId, customerId: "", customerName: "Unknown", agentId: "", agentName: "", checkType: .idVerification, status: .pending, entityType: .seafarer, createdAt: Date()) }
    private var isWaiting: Bool { c.sessionId != nil && c.completedAt == nil && c.rawIDResponse == nil }
    private var isExpired: Bool { c.sessionId != nil && c.status == .incomplete && c.completedAt != nil }

    @State private var docType: KYCCheck.IDDocType = .passport
    @State private var depth: KYCCheck.InvestigationDepth = .idAml
    @State private var monitoring = false
    @State private var frontImage: Data?; @State private var backImage: Data?; @State private var poaImage: Data?
    @State private var showFrontCam = false; @State private var showBackCam = false; @State private var showPoACam = false
    @State private var showFrontFile = false; @State private var showBackFile = false; @State private var showPoAFile = false
    @State private var selFront: PhotosPickerItem?; @State private var selBack: PhotosPickerItem?; @State private var selPoA: PhotosPickerItem?
    @State private var busy = false; @State private var progressText = ""; @State private var error: String?
    @State private var notes = ""
    @State private var showInvite = false

    var body: some View {
        Group {
            if isExpired { expiredView }
            else if isWaiting { waitingView }
            else if busy { processingView }
            else { configBody }
        }
        .onAppear { notes = c.agentNotes ?? ""; if let d = c.expectedDocType { docType = d }; if let d = c.investigationDepth { depth = d } }
        .fullScreenCover(isPresented: $showFrontCam) { CameraCapture(result: $frontImage).ignoresSafeArea() }
        .fullScreenCover(isPresented: $showBackCam) { CameraCapture(result: $backImage).ignoresSafeArea() }
        .fullScreenCover(isPresented: $showPoACam) { CameraCapture(result: $poaImage).ignoresSafeArea() }
        .sheet(isPresented: $showFrontFile) { FilePicker { url in frontImage = loadFile(url) } }
        .sheet(isPresented: $showBackFile) { FilePicker { url in backImage = loadFile(url) } }
        .sheet(isPresented: $showPoAFile) { FilePicker { url in poaImage = loadFile(url) } }
    }

    // MARK: - Config

    private var configBody: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    // Document type card
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader("Document")
                        HStack(spacing: 8) {
                            ForEach(KYCCheck.IDDocType.allCases) { dt in
                                Button { withAnimation(.spring(response: 0.2)) { docType = dt } } label: {
                                    VStack(spacing: 4) {
                                        Image(systemName: dt.icon).font(.system(size: 18))
                                        Text(dt.rawValue).font(Typo.meta).lineLimit(1).minimumScaleFactor(0.7)
                                    }
                                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                                    .background(docType == dt ? Color.primary : Color.surfaceMuted)
                                    .foregroundStyle(docType == dt ? Color.surface : .primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(16).background(Color.surfaceMuted.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    // Scope card
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader("Scope")
                        Picker("", selection: $depth) { ForEach(KYCCheck.InvestigationDepth.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                        if depth.includesAML { Toggle(isOn: $monitoring) { Text("Continuous monitoring").font(Typo.meta) }.tint(.primary) }
                    }
                    .padding(16).background(Color.surfaceMuted.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    // Upload card
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader("Documents")
                        slot("Front", data: frontImage, cam: $showFrontCam, file: $showFrontFile, photo: $selFront, required: true)
                            .onChange(of: selFront) { _, v in Task { frontImage = await loadPhoto(v) } }
                        slot(docType.needsBack ? "Back" : "Back (optional)", data: backImage, cam: $showBackCam, file: $showBackFile, photo: $selBack, required: docType.needsBack)
                            .onChange(of: selBack) { _, v in Task { backImage = await loadPhoto(v) } }
                        if depth.includesPoA {
                            slot("Proof of Address", data: poaImage, cam: $showPoACam, file: $showPoAFile, photo: $selPoA, required: true)
                                .onChange(of: selPoA) { _, v in Task { poaImage = await loadPhoto(v) } }
                        }
                    }
                    .padding(16).background(Color.surfaceMuted.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    if let e = error { Text(e).font(Typo.meta).foregroundStyle(Color.flagged) }

                    // Notes
                    VStack(alignment: .leading, spacing: 6) {
                        SectionHeader("Notes")
                        TextField("Observations...", text: $notes, axis: .vertical).font(Typo.meta).lineLimit(2...4)
                            .padding(10).background(Color.surfaceMuted).clipShape(RoundedRectangle(cornerRadius: 10))
                        if notes != (c.agentNotes ?? "") && !notes.isEmpty {
                            Button("Save") { vm.updateAgentNotes(checkId: c.id, notes: notes) }.font(Typo.meta)
                        }
                    }

                    Spacer(minLength: 80)
                }
                .padding(.horizontal, 16).padding(.top, 12)
            }

            // Pinned verify button
            VStack(spacing: 0) {
                Divider()
                let ready = frontImage != nil && (!docType.needsBack || backImage != nil) && (!depth.includesPoA || poaImage != nil)
                Button { vm.configureCheck(checkId: c.id, docType: docType, depth: depth); Task { await runPipeline() } } label: { Text("Verify") }
                    .buttonStyle(PrimaryButtonStyle(isEnabled: ready)).disabled(!ready)
                    .padding(.horizontal, 24).padding(.vertical, 10)
            }
            .background(.ultraThinMaterial)
        }
    }

    // MARK: - States

    private var processingView: some View {
        VStack(spacing: 16) { Spacer(); ProgressView().controlSize(.large); Text(progressText).font(Typo.body).foregroundStyle(.secondary); Spacer() }
    }

    private var waitingView: some View {
        VStack(spacing: 20) {
            Spacer()
            Circle().fill(Color.primary.opacity(0.04)).frame(width: 80, height: 80).overlay { ProgressView().controlSize(.regular) }
            Text("Waiting for verification").font(Typo.context)
            Text("The subject will verify via the link you shared.").font(Typo.meta).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 32)
            Spacer()
            Button { showInvite = true } label: { Text("Send New Invite") }.buttonStyle(PrimaryButtonStyle()).padding(.horizontal, 48)
            Spacer()
        }.sheet(isPresented: $showInvite) { InviteSheet(vm: vm, check: c) }
    }

    private var expiredView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "clock.badge.xmark").font(.system(size: 48)).foregroundStyle(.quaternary)
            Text("Session Expired").font(Typo.context)
            Text("Send a new invite to restart.").font(Typo.meta).foregroundStyle(.secondary)
            Spacer()
            Button { showInvite = true } label: { Text("Send New Invite") }.buttonStyle(PrimaryButtonStyle()).padding(.horizontal, 48)
            Spacer()
        }.sheet(isPresented: $showInvite) { InviteSheet(vm: vm, check: c) }
    }

    // MARK: - Pipeline

    private func runPipeline() async {
        guard let front = frontImage else { return }
        busy = true; error = nil; progressText = "Scanning document..."
        do {
            _ = try await vm.runIDScan(checkId: c.id, frontImage: front, backImage: backImage)
            busy = false
            if depth.includesAML {
                progressText = "Checking compliance..."
                do { _ = try await vm.runAMLScreening(checkId: c.id, monitoring: monitoring) } catch { self.error = "AML: \(error.localizedDescription)" }
            } else { vm.finalizeIDOnly(checkId: c.id) }
            if depth.includesPoA, let img = poaImage {
                progressText = "Verifying address..."
                do { _ = try await vm.runPoA(checkId: c.id, documentImage: img, expectedName: c.extractedName, expectedAddress: nil) { _ in } } catch { self.error = "PoA: \(error.localizedDescription)" }
            }
        } catch { self.error = error.localizedDescription; busy = false }
    }

    // MARK: - Upload Helpers

    private func slot(_ title: String, data: Data?, cam: Binding<Bool>, file: Binding<Bool>, photo: Binding<PhotosPickerItem?>, required: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text(title).font(Typo.meta).foregroundStyle(.secondary); if required { Text("*").foregroundStyle(Color.review) } }
            if let data, let img = UIImage(data: data) {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: img).resizable().scaledToFit().frame(maxHeight: 120).frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 10))
                    Menu {
                        Button { cam.wrappedValue = true } label: { Label("Camera", systemImage: "camera") }
                        PhotosPicker(selection: photo, matching: .images) { Label("Photos", systemImage: "photo") }
                        Button { file.wrappedValue = true } label: { Label("File", systemImage: "folder") }
                    } label: { Image(systemName: "pencil.circle.fill").font(.title2).foregroundStyle(.white, .primary).padding(4) }
                }
            } else {
                HStack(spacing: 10) {
                    Button { cam.wrappedValue = true } label: {
                        VStack(spacing: 6) { Image(systemName: "camera.fill").font(.body); Text("Camera").font(Typo.meta) }
                            .frame(maxWidth: .infinity).frame(height: 80).background(Color.surfaceMuted).clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    PhotosPicker(selection: photo, matching: .images) {
                        VStack(spacing: 6) { Image(systemName: "photo").font(.body); Text("Photos").font(Typo.meta) }
                            .frame(maxWidth: .infinity).frame(height: 80).background(Color.surfaceMuted).clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    Button { file.wrappedValue = true } label: {
                        VStack(spacing: 6) { Image(systemName: "folder").font(.body); Text("File").font(Typo.meta) }
                            .frame(maxWidth: .infinity).frame(height: 80).background(Color.surfaceMuted).clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }.buttonStyle(.plain)
            }
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async -> Data? {
        guard let item else { return nil }; return try? await item.loadTransferable(type: Data.self)
    }

    private func loadFile(_ url: URL) -> Data? {
        if url.startAccessingSecurityScopedResource() { defer { url.stopAccessingSecurityScopedResource() }; return try? Data(contentsOf: url) }
        return try? Data(contentsOf: url)
    }
}
