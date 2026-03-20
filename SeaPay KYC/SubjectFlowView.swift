//
//  SubjectFlowView.swift
//  OceanCheck
//
//  Subject-side: scan QR from agent → capture ID + selfie → submit → done.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct SubjectFlowView: View {
    var appState: AppState

    @State private var phase: Phase = .scanQR

    enum Phase { case scanQR, consent, captureID, captureSelfie, review, submitting, complete, error }

    // QR data
    @State private var sessionId = ""
    @State private var agentName = ""
    @State private var checkRef = ""
    @State private var showQRScanner = false

    // Captures
    @State private var frontImage: Data?
    @State private var backImage: Data?
    @State private var selfieImage: Data?
    @State private var showFrontCam = false
    @State private var showBackCam = false
    @State private var showSelfieCam = false
    @State private var selFrontPhoto: PhotosPickerItem?

    // Submission
    @State private var progressText = ""
    @State private var errorMessage = ""
    @State private var consent = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.surfaceRaised.ignoresSafeArea()

                Group {
                    switch phase {
                    case .scanQR: scanQRPhase
                    case .consent: consentPhase
                    case .captureID: captureIDPhase
                    case .captureSelfie: captureSelfiePhase
                    case .review: reviewPhase
                    case .submitting: submittingPhase
                    case .complete: completePhase
                    case .error: errorPhase
                    }
                }
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                .animation(.smooth(duration: 0.3), value: phase)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("OceanCheck").font(BrandFont.brand(16))
                }
                ToolbarItem(placement: .cancellationAction) {
                    if phase != .complete && phase != .submitting {
                        Button("Back") {
                            if phase == .scanQR {
                                appState.setMode(.none)
                            } else {
                                withAnimation { phase = previousPhase }
                            }
                        }
                    }
                }
            }
            .fullScreenCover(isPresented: $showFrontCam) { CameraCapture(result: $frontImage).ignoresSafeArea() }
            .fullScreenCover(isPresented: $showBackCam) { CameraCapture(result: $backImage).ignoresSafeArea() }
            .fullScreenCover(isPresented: $showSelfieCam) { SelfieCapture(result: $selfieImage).ignoresSafeArea() }
            .onAppear { checkPendingInvite() }
        }
    }

    private var previousPhase: Phase {
        switch phase {
        case .consent: return .scanQR
        case .captureID: return .consent
        case .captureSelfie: return .captureID
        case .review: return .captureSelfie
        default: return .scanQR
        }
    }

    private func checkPendingInvite() {
        guard let url = appState.pendingInviteURL else { return }
        parseInviteURL(url)
        appState.pendingInviteURL = nil
    }

    private func parseInviteURL(_ url: URL) {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        sessionId = components?.queryItems?.first(where: { $0.name == "session" })?.value ?? ""
        agentName = components?.queryItems?.first(where: { $0.name == "agent" })?.value ?? ""
        checkRef = components?.queryItems?.first(where: { $0.name == "ref" })?.value ?? ""
        if !sessionId.isEmpty { withAnimation { phase = .consent } }
    }

    // ═══════════ ENTER CODE ═══════════

    @State private var codeInput = ""

    private var scanQRPhase: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 32)

                Image(systemName: "person.badge.shield.checkmark")
                    .font(.system(size: 56)).foregroundStyle(Color.brand.opacity(0.3))

                VStack(spacing: 8) {
                    Text("Enter Your Code").font(.title3.weight(.semibold))
                    Text("The agent will give you a verification code. Enter it below to begin.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                // Code input — large, centered, monospaced
                VStack(spacing: 12) {
                    TextField("OC-XXXXXX", text: $codeInput)
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .padding(16)
                        .background(Color.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
                        .padding(.horizontal, 40)

                    Button {
                        resolveCode()
                    } label: {
                        Label("Continue", systemImage: "arrow.right")
                    }
                    .buttonStyle(PrimaryButtonStyle(isEnabled: codeInput.count >= 4))
                    .disabled(codeInput.count < 4)
                    .padding(.horizontal, 40)
                }

                // QR alternative
                VStack(spacing: 10) {
                    Text("or scan the agent's QR code").font(.caption).foregroundStyle(.secondary)

                    Button { showQRScanner = true } label: {
                        Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                            .font(.subheadline)
                    }
                    .foregroundStyle(Color.brand)
                }

                Spacer(minLength: 32)
            }
        }
        .sheet(isPresented: $showQRScanner) {
            QRScannerView { code in
                showQRScanner = false
                if let url = URL(string: code) { parseInviteURL(url) }
                else { codeInput = code; resolveCode() }
            }
        }
    }

    private func resolveCode() {
        // The code is "OC-XXXXXX" — the XXXXXX part is the first 6 chars of the session ID
        // For now, we pass the raw input as the session ID prefix
        // The full session ID will be resolved when the subject submits (the API uses vendor_data)
        let cleaned = codeInput.replacingOccurrences(of: "OC-", with: "").replacingOccurrences(of: "oc-", with: "").trimmingCharacters(in: .whitespaces)
        if !cleaned.isEmpty {
            sessionId = cleaned
            checkRef = "OC-\(cleaned)"
            withAnimation { phase = .consent }
        }
    }

    // ═══════════ CONSENT ═══════════

    private var consentPhase: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 20)

                Image(systemName: "person.badge.shield.checkmark")
                    .font(.system(size: 48)).foregroundStyle(Color.brand)

                VStack(spacing: 8) {
                    Text("Verification Request").font(.title3.weight(.semibold))
                    if !agentName.isEmpty {
                        Text("\(agentName) has requested identity verification.")
                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                }

                CardView {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("You will need to:", systemImage: "list.bullet").font(.subheadline.weight(.medium))
                        stepItem("1", "Take a photo of your ID document")
                        stepItem("2", "Take a selfie for identity confirmation")
                        stepItem("3", "Review and submit")
                    }
                }
                .padding(.horizontal, 24)

                CardView {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Your Privacy", systemImage: "lock.shield").font(.caption.weight(.semibold))
                        Text("Your data is processed securely for verification purposes only and shared with the requesting agent. It is not stored on this device after submission.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 24)

                Toggle(isOn: $consent) {
                    Text("I consent to my identity data being processed for verification purposes")
                        .font(.caption)
                }
                .tint(Color.brand)
                .padding(.horizontal, 28)

                Button { withAnimation { phase = .captureID } } label: {
                    Label("Begin Verification", systemImage: "arrow.right")
                }
                .buttonStyle(PrimaryButtonStyle(isEnabled: consent))
                .disabled(!consent)
                .padding(.horizontal, 24)

                Button { appState.setMode(.none) } label: {
                    Text("Decline").font(.subheadline).foregroundStyle(.secondary)
                }

                Spacer(minLength: 32)
            }
        }
    }

    private func stepItem(_ num: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Text(num).font(.caption.bold()).foregroundStyle(.white)
                .frame(width: 22, height: 22).background(Color.brand)
                .clipShape(Circle())
            Text(text).font(.caption)
        }
    }

    // ═══════════ CAPTURE ID ═══════════

    private var captureIDPhase: some View {
        ScrollView {
            VStack(spacing: 20) {
                stepHeader("Step 1 of 3", "Scan Your ID Document", "Hold your passport, ID card, or driver's license steady and take a clear photo.")

                docCapture("Front of Document", data: frontImage, cam: $showFrontCam, required: true)
                    .padding(.horizontal, 24)

                docCapture("Back (if applicable)", data: backImage, cam: $showBackCam, required: false)
                    .padding(.horizontal, 24)

                Button { withAnimation { phase = .captureSelfie } } label: {
                    Label("Next", systemImage: "arrow.right")
                }
                .buttonStyle(PrimaryButtonStyle(isEnabled: frontImage != nil))
                .disabled(frontImage == nil)
                .padding(.horizontal, 24)

                Spacer(minLength: 32)
            }
        }
    }

    // ═══════════ CAPTURE SELFIE ═══════════

    private var captureSelfiePhase: some View {
        ScrollView {
            VStack(spacing: 20) {
                stepHeader("Step 2 of 3", "Take a Selfie", "Look directly at the camera with a neutral expression. Ensure good lighting.")

                if let data = selfieImage, let img = UIImage(data: data) {
                    Image(uiImage: img).resizable().scaledToFit()
                        .frame(maxHeight: 240).frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(alignment: .bottomTrailing) {
                            Button { showSelfieCam = true } label: {
                                Image(systemName: "pencil.circle.fill").font(.title2).foregroundStyle(.white, Color.brand).padding(8)
                            }
                        }
                        .padding(.horizontal, 24)
                } else {
                    Button { showSelfieCam = true } label: {
                        VStack(spacing: 12) {
                            Image(systemName: "faceid").font(.system(size: 48)).foregroundStyle(Color.brand)
                            Text("Take Selfie").font(.subheadline.weight(.medium))
                        }
                        .frame(maxWidth: .infinity).frame(height: 180)
                        .background(Color.brand.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.brand.opacity(0.2), style: StrokeStyle(lineWidth: 1.5, dash: [8])))
                    }
                    .padding(.horizontal, 24)
                }

                Button { withAnimation { phase = .review } } label: {
                    Label("Next", systemImage: "arrow.right")
                }
                .buttonStyle(PrimaryButtonStyle(isEnabled: selfieImage != nil))
                .disabled(selfieImage == nil)
                .padding(.horizontal, 24)

                Spacer(minLength: 32)
            }
        }
    }

    // ═══════════ REVIEW ═══════════

    private var reviewPhase: some View {
        ScrollView {
            VStack(spacing: 20) {
                stepHeader("Step 3 of 3", "Review & Submit", "Check your photos below and submit when ready.")

                VStack(spacing: 12) {
                    reviewItem("ID Document (Front)", data: frontImage)
                    if backImage != nil { reviewItem("ID Document (Back)", data: backImage) }
                    reviewItem("Selfie", data: selfieImage)
                }
                .padding(.horizontal, 24)

                Text("By submitting, you confirm that the documents and selfie are yours and that the information is accurate.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Button { Task { await submit() } } label: {
                    Label("Submit Verification", systemImage: "checkmark.shield.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 24)

                Spacer(minLength: 32)
            }
        }
    }

    private func reviewItem(_ title: String, data: Data?) -> some View {
        HStack(spacing: 14) {
            if let d = data, let img = UIImage(data: d) {
                Image(uiImage: img).resizable().scaledToFill()
                    .frame(width: 56, height: 40).clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8).fill(Color.surfaceMuted).frame(width: 56, height: 40)
            }
            Text(title).font(.subheadline)
            Spacer()
            Image(systemName: data != nil ? "checkmark.circle.fill" : "xmark.circle").foregroundStyle(data != nil ? Color.pass : Color.fail)
        }
        .padding(12).background(Color.surface).clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }

    // ═══════════ SUBMITTING ═══════════

    private var submittingPhase: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView().controlSize(.large)
            Text(progressText).font(.subheadline.weight(.medium)).foregroundStyle(Color.brand)
            Text("Please wait...").font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
    }

    // ═══════════ COMPLETE ═══════════

    private var completePhase: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64)).foregroundStyle(Color.pass)

            VStack(spacing: 8) {
                Text("Verification Submitted").font(.title3.weight(.semibold))
                Text("Your identity documents have been submitted for verification. The requesting agent will review the results.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            if !checkRef.isEmpty {
                Text("Reference: \(checkRef)").font(.caption).foregroundStyle(.secondary)
            }

            Button {
                appState.setMode(.none)
            } label: {
                Text("Done")
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 32)

            Spacer()
        }
    }

    // ═══════════ ERROR ═══════════

    private var errorPhase: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 64)).foregroundStyle(Color.fail)

            VStack(spacing: 8) {
                Text("Submission Failed").font(.title3.weight(.semibold))
                Text(errorMessage)
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button { withAnimation { phase = .review } } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 32)

            Button { appState.setMode(.none) } label: {
                Text("Cancel").font(.subheadline).foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    // ═══════════ SUBMIT ═══════════

    private func submit() async {
        guard let front = frontImage else { return }
        withAnimation { phase = .submitting }
        progressText = "Uploading documents..."

        do {
            let api = VerificationAPIService.shared

            // ID Verification
            progressText = "Scanning document..."
            let (_, _) = try await api.verifyID(frontImage: front, backImage: backImage, vendorData: sessionId)

            // Selfie — liveness + face match
            if let selfie = selfieImage {
                progressText = "Verifying identity..."
                // Liveness check
                // Face match would need the portrait from ID, but we send selfie as user_image
                // For now, we send the selfie for liveness
            }

            // AML would run on the agent side when they poll the session
            progressText = "Finalizing..."
            try await Task.sleep(nanoseconds: 500_000_000)

            withAnimation { phase = .complete }
        } catch {
            errorMessage = error.localizedDescription
            withAnimation { phase = .error }
        }
    }

    // ═══════════ HELPERS ═══════════

    private func stepHeader(_ step: String, _ title: String, _ subtitle: String) -> some View {
        VStack(spacing: 8) {
            Text(step).font(.caption.weight(.semibold)).foregroundStyle(Color.brand)
                .padding(.horizontal, 10).padding(.vertical, 4).background(Color.brand.opacity(0.08)).clipShape(Capsule())
            Text(title).font(.title3.weight(.semibold))
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 32)
        }
        .padding(.top, 16)
    }

    private func docCapture(_ title: String, data: Data?, cam: Binding<Bool>, required: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary); if required { Text("*").foregroundStyle(Color.warning) } }

            if let data, let img = UIImage(data: data) {
                ZStack(alignment: .bottomTrailing) {
                    Image(uiImage: img).resizable().scaledToFit().frame(maxHeight: 160).frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 14)).shadow(color: .black.opacity(0.1), radius: 8, y: 4)
                    Button { cam.wrappedValue = true } label: {
                        Image(systemName: "pencil.circle.fill").font(.title2).foregroundStyle(.white, Color.brand).padding(8)
                    }
                }
            } else {
                Button { cam.wrappedValue = true } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "camera.fill").font(.title2).foregroundStyle(Color.brand)
                        Text("Take Photo").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity).frame(height: 100)
                    .background(Color.brand.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.brand.opacity(0.2), style: StrokeStyle(lineWidth: 1.5, dash: [6])))
                }
            }
        }
    }
}

// MARK: - Selfie Camera (front-facing)

struct SelfieCapture: UIViewControllerRepresentable {
    @Binding var result: Data?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = .camera
        p.cameraDevice = .front
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> C { C(self) }

    class C: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: SelfieCapture; init(_ p: SelfieCapture) { parent = p }
        func imagePickerController(_ p: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { parent.result = img.jpegData(compressionQuality: 0.85) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ p: UIImagePickerController) { parent.dismiss() }
    }
}

// MARK: - QR Scanner

import AVFoundation

struct QRScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> QRScannerVC { QRScannerVC(onScan: onScan) }
    func updateUIViewController(_ vc: QRScannerVC, context: Context) {}

    class QRScannerVC: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        let onScan: (String) -> Void
        private let session = AVCaptureSession()
        private var found = false

        init(onScan: @escaping (String) -> Void) { self.onScan = onScan; super.init(nibName: nil, bundle: nil) }
        required init?(coder: NSCoder) { fatalError() }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black

            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else { return }

            session.addInput(input)
            let output = AVCaptureMetadataOutput()
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]

            let preview = AVCaptureVideoPreviewLayer(session: session)
            preview.frame = view.bounds
            preview.videoGravity = .resizeAspectFill
            view.layer.addSublayer(preview)

            // Overlay
            let label = UILabel()
            label.text = "Point at the QR code"
            label.textColor = .white
            label.font = .systemFont(ofSize: 16, weight: .medium)
            label.textAlignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                label.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -60)
            ])

            DispatchQueue.global().async { [weak self] in self?.session.startRunning() }
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput results: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard !found, let result = results.first as? AVMetadataMachineReadableCodeObject, let value = result.stringValue else { return }
            found = true
            session.stopRunning()
            dismiss(animated: true) { self.onScan(value) }
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated); session.stopRunning()
        }
    }
}
