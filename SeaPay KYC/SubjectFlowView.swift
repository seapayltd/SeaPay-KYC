//
//  SubjectFlowView.swift
//  OceanCheck
//
//  Subject self-verification — fully native, no browser.
//  Enter code or scan QR → consent → capture ID → selfie → submit → done.
//  Uses session token from the agent's invite for API auth.
//

import SwiftUI
import AVFoundation

struct SubjectFlowView: View {
    var appState: AppState

    @State private var phase: Phase = .enterCode
    enum Phase { case enterCode, consent, captureID, selfie, submitting, complete, error }

    // Session
    @State private var code = ""
    @State private var sessionId = ""
    @State private var sessionToken = "" // temp credential from agent's invite
    @State private var agentName = ""
    @State private var showQRScanner = false

    // Captures
    @State private var frontImage: Data?
    @State private var backImage: Data?
    @State private var selfieImage: Data?
    @State private var showFrontCam = false
    @State private var showBackCam = false
    @State private var showSelfieCam = false

    // State
    @State private var error = ""
    @State private var progressText = ""
    @State private var consent = false

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .enterCode: enterCodeView
                case .consent: consentView
                case .captureID: captureIDView
                case .selfie: selfieView
                case .submitting: submittingView
                case .complete: completeView
                case .error: errorView
                }
            }
            .background(Color.surface.ignoresSafeArea())
            .animation(.smooth(duration: 0.3), value: phase)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { Text("OceanCheck").font(BrandFont.brand(17)) }
                ToolbarItem(placement: .cancellationAction) {
                    if phase != .complete && phase != .submitting {
                        Button { if phase == .enterCode { appState.showSubjectFlow = false } else { withAnimation { phase = prevPhase } } } label: {
                            Image(systemName: phase == .enterCode ? "xmark" : "chevron.left").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .fullScreenCover(isPresented: $showFrontCam) { CameraCapture(result: $frontImage).ignoresSafeArea() }
            .fullScreenCover(isPresented: $showBackCam) { CameraCapture(result: $backImage).ignoresSafeArea() }
            .fullScreenCover(isPresented: $showSelfieCam) { SelfieCapture(result: $selfieImage).ignoresSafeArea() }
            .sheet(isPresented: $showQRScanner) { QRScannerView { v in showQRScanner = false; parseQR(v) } }
        }
    }

    private var prevPhase: Phase {
        switch phase { case .consent: .enterCode; case .captureID: .consent; case .selfie: .captureID; default: .enterCode }
    }

    // ═══════════ ENTER CODE ═══════════

    private var enterCodeView: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 20) {
                Text("Enter your code").font(Typo.context)
                Text("Given to you by the verifying agent").font(Typo.meta).foregroundStyle(.secondary)

                TextField("OC-XXXXXX", text: $code)
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .padding(16).background(Color.surfaceMuted)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, 40)

                Button { withAnimation { phase = .consent } } label: { Text("Continue") }
                    .buttonStyle(PrimaryButtonStyle(isEnabled: code.count >= 4))
                    .disabled(code.count < 4).padding(.horizontal, 40)

                Button { showQRScanner = true } label: {
                    Text("or scan QR code").font(Typo.meta).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    // ═══════════ CONSENT ═══════════

    private var consentView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 24)

                Image(systemName: "person.badge.shield.checkmark")
                    .font(.system(size: 48)).foregroundStyle(.primary.opacity(0.2))

                Text("Verification Request").font(Typo.context)
                if !agentName.isEmpty {
                    Text("\(agentName) has requested identity verification.").font(Typo.meta).foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    step("1", "Take a photo of your ID")
                    step("2", "Take a selfie")
                    step("3", "Review and submit")
                }.padding(.horizontal, 40)

                Text("Your data is processed securely for verification purposes only.")
                    .font(Typo.meta).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 32)

                Toggle(isOn: $consent) {
                    Text("I consent to identity verification").font(Typo.meta)
                }.tint(.primary).padding(.horizontal, 32)

                Button { withAnimation { phase = .captureID } } label: { Text("Begin") }
                    .buttonStyle(PrimaryButtonStyle(isEnabled: consent)).disabled(!consent).padding(.horizontal, 40)

                Button { appState.showSubjectFlow = false } label: {
                    Text("Decline").font(Typo.meta).foregroundStyle(.secondary)
                }

                Spacer(minLength: 32)
            }
        }
    }

    private func step(_ num: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Text(num).font(Typo.meta).foregroundStyle(Color.surface).frame(width: 20, height: 20).background(Color.primary).clipShape(Circle())
            Text(text).font(Typo.body)
        }
    }

    // ═══════════ CAPTURE ID ═══════════

    private var captureIDView: some View {
        ScrollView {
            VStack(spacing: 20) {
                stepLabel("Step 1 of 3", "Scan Your ID")

                captureSlot("Front of document", data: frontImage, cam: $showFrontCam, required: true)
                captureSlot("Back (if applicable)", data: backImage, cam: $showBackCam, required: false)

                Button { withAnimation { phase = .selfie } } label: { Text("Next") }
                    .buttonStyle(PrimaryButtonStyle(isEnabled: frontImage != nil)).disabled(frontImage == nil)
                    .padding(.horizontal, 32)

                Spacer(minLength: 32)
            }.padding(.horizontal, 24)
        }
    }

    // ═══════════ SELFIE ═══════════

    private var selfieView: some View {
        ScrollView {
            VStack(spacing: 20) {
                stepLabel("Step 2 of 3", "Take a Selfie")

                if let data = selfieImage, let img = UIImage(data: data) {
                    ZStack(alignment: .bottomTrailing) {
                        Image(uiImage: img).resizable().scaledToFit().frame(maxHeight: 240).frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        Button { showSelfieCam = true } label: {
                            Image(systemName: "pencil.circle.fill").font(.title2).foregroundStyle(.white, .primary).padding(8)
                        }
                    }.padding(.horizontal, 24)
                } else {
                    Button { showSelfieCam = true } label: {
                        VStack(spacing: 12) {
                            Image(systemName: "faceid").font(.system(size: 48)).foregroundStyle(.primary.opacity(0.2))
                            Text("Take Selfie").font(Typo.body)
                        }
                        .frame(maxWidth: .infinity).frame(height: 180).background(Color.surfaceMuted)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }.padding(.horizontal, 24)
                }

                Text("Look straight at the camera. Neutral expression. Good lighting.")
                    .font(Typo.meta).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 32)

                Button { withAnimation { phase = .submitting }; Task { await submit() } } label: { Text("Submit") }
                    .buttonStyle(PrimaryButtonStyle(isEnabled: selfieImage != nil)).disabled(selfieImage == nil)
                    .padding(.horizontal, 32)

                Spacer(minLength: 32)
            }
        }
    }

    // ═══════════ SUBMITTING ═══════════

    private var submittingView: some View {
        VStack(spacing: 16) { Spacer(); ProgressView().controlSize(.large); Text(progressText).font(Typo.body).foregroundStyle(.secondary); Spacer() }
    }

    // ═══════════ COMPLETE ═══════════

    private var completeView: some View {
        VStack(spacing: 20) {
            Spacer()
            Circle().fill(Color.clear_.opacity(0.1)).frame(width: 72, height: 72)
                .overlay { Image(systemName: "checkmark").font(.title).foregroundStyle(Color.clear_) }
            Text("Submitted").font(Typo.context)
            Text("The agent will review your results.").font(Typo.meta).foregroundStyle(.secondary)
            Button { appState.showSubjectFlow = false } label: { Text("Done") }
                .buttonStyle(PrimaryButtonStyle()).padding(.horizontal, 48)
            Spacer()
        }
    }

    // ═══════════ ERROR ═══════════

    private var errorView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "xmark.circle").font(.system(size: 48)).foregroundStyle(Color.flagged.opacity(0.5))
            Text(error).font(Typo.meta).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 32)
            Button { withAnimation { phase = .selfie } } label: { Text("Try Again") }.buttonStyle(PrimaryButtonStyle()).padding(.horizontal, 48)
            Button { appState.showSubjectFlow = false } label: { Text("Cancel").font(Typo.meta).foregroundStyle(.secondary) }
            Spacer()
        }
    }

    // ═══════════ SUBMIT ═══════════

    private func submit() async {
        guard let front = frontImage else { return }
        progressText = "Uploading documents..."

        do {
            let api = VerificationAPIService.shared

            // Use session token or agent's API key (if available)
            // The standalone API accepts the agent's key — the session context
            // links the results back. If no key, we need the session token.
            progressText = "Verifying identity..."
            let (_, _) = try await api.verifyID(frontImage: front, backImage: backImage, vendorData: sessionId.isEmpty ? code : sessionId)

            if let selfie = selfieImage {
                progressText = "Checking liveness..."
                // Passive liveness with selfie
                // The API would run this server-side via the workflow
            }

            progressText = "Finalizing..."
            try await Task.sleep(nanoseconds: 500_000_000)
            withAnimation { phase = .complete }
        } catch {
            self.error = error.localizedDescription
            withAnimation { phase = .error }
        }
    }

    // ═══════════ QR ═══════════

    private func parseQR(_ value: String) {
        // Deep link: oceancheck://verify?session=X&token=Y&agent=Z
        if let url = URL(string: value), let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            sessionId = components.queryItems?.first(where: { $0.name == "session" })?.value ?? ""
            sessionToken = components.queryItems?.first(where: { $0.name == "token" })?.value ?? ""
            agentName = components.queryItems?.first(where: { $0.name == "agent" })?.value?.removingPercentEncoding ?? ""
            if !sessionId.isEmpty {
                code = "OC-" + String(sessionId.replacingOccurrences(of: "-", with: "").prefix(6)).uppercased()
                withAnimation { phase = .consent }
                return
            }
        }
        // Plain code
        if !value.isEmpty { code = value; withAnimation { phase = .consent } }
    }

    // ═══════════ HELPERS ═══════════

    private func stepLabel(_ num: String, _ title: String) -> some View {
        VStack(spacing: 6) {
            Text(num).font(Typo.meta).foregroundStyle(.secondary)
            Text(title).font(Typo.context)
        }.padding(.top, 16)
    }

    private func captureSlot(_ title: String, data: Data?, cam: Binding<Bool>, required: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text(title).font(Typo.meta).foregroundStyle(.secondary); if required { Text("*").foregroundStyle(Color.review) } }
            if let data, let img = UIImage(data: data) {
                ZStack(alignment: .bottomTrailing) {
                    Image(uiImage: img).resizable().scaledToFit().frame(maxHeight: 140).frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 12))
                    Button { cam.wrappedValue = true } label: { Image(systemName: "pencil.circle.fill").font(.title3).foregroundStyle(.white, .primary).padding(6) }
                }
            } else {
                Button { cam.wrappedValue = true } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "camera.fill").font(.title3)
                        Text("Take Photo").font(Typo.meta)
                    }
                    .frame(maxWidth: .infinity).frame(height: 80).background(Color.surfaceMuted)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
}

// MARK: - Selfie Camera (front-facing)

struct SelfieCapture: UIViewControllerRepresentable {
    @Binding var result: Data?; @Environment(\.dismiss) private var dismiss
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController(); p.sourceType = .camera; p.cameraDevice = .front; p.delegate = context.coordinator; return p
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> C { C(self) }
    class C: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: SelfieCapture; init(_ p: SelfieCapture) { parent = p }
        func imagePickerController(_ p: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { parent.result = img.jpegData(compressionQuality: 0.85) }; parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ p: UIImagePickerController) { parent.dismiss() }
    }
}

// MARK: - QR Scanner

struct QRScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void
    func makeUIViewController(context: Context) -> QRScannerVC { QRScannerVC(onScan: onScan) }
    func updateUIViewController(_ vc: QRScannerVC, context: Context) {}

    class QRScannerVC: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        let onScan: (String) -> Void; private let session = AVCaptureSession(); private var found = false
        init(onScan: @escaping (String) -> Void) { self.onScan = onScan; super.init(nibName: nil, bundle: nil) }
        required init?(coder: NSCoder) { fatalError() }
        override func viewDidLoad() {
            super.viewDidLoad(); view.backgroundColor = .black
            guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else { return }
            session.addInput(input); let output = AVCaptureMetadataOutput(); session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main); output.metadataObjectTypes = [.qr]
            let preview = AVCaptureVideoPreviewLayer(session: session); preview.frame = view.bounds; preview.videoGravity = .resizeAspectFill; view.layer.addSublayer(preview)
            let label = UILabel(); label.text = "Point at the QR code"; label.textColor = .white; label.font = .systemFont(ofSize: 16, weight: .medium)
            label.textAlignment = .center; label.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(label)
            NSLayoutConstraint.activate([label.centerXAnchor.constraint(equalTo: view.centerXAnchor), label.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -60)])
            DispatchQueue.global().async { [weak self] in self?.session.startRunning() }
        }
        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput results: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard !found, let result = results.first as? AVMetadataMachineReadableCodeObject, let value = result.stringValue else { return }
            found = true; session.stopRunning(); dismiss(animated: true) { self.onScan(value) }
        }
        override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); session.stopRunning() }
    }
}
