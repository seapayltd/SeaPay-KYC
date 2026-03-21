//
//  SubjectFlowView.swift
//  OceanCheck
//
//  Subject enters a code → app looks up the session → opens the hosted
//  verification in an embedded browser. No API key needed.
//

import SwiftUI
import SafariServices
import AVFoundation

struct SubjectFlowView: View {
    var appState: AppState

    @State private var code = ""
    @State private var sessionURL: URL?
    @State private var showVerification = false
    @State private var showQRScanner = false
    @State private var completed = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.surface.ignoresSafeArea()

                if completed {
                    completedView
                } else {
                    codeEntryView
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { Text("OceanCheck").font(BrandFont.brand(17)) }
                ToolbarItem(placement: .cancellationAction) {
                    Button { appState.showSubjectFlow = false } label: {
                        Image(systemName: "xmark").foregroundStyle(.secondary)
                    }
                }
            }
            .sheet(isPresented: $showQRScanner) {
                QRScannerView { value in
                    showQRScanner = false
                    parseQR(value)
                }
            }
            .fullScreenCover(isPresented: $showVerification) {
                if let url = sessionURL {
                    SafariCover(url: url, onDismiss: {
                        showVerification = false
                        withAnimation(.smooth) { completed = true }
                    })
                }
            }
        }
    }

    // ═══════════ CODE ENTRY ═══════════

    private var codeEntryView: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                Text("Enter your code").font(Typo.context)
                Text("Given to you by the verifying agent").font(Typo.meta).foregroundStyle(.secondary)

                TextField("OC-XXXXXX", text: $code)
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .padding(16)
                    .background(Color.surfaceMuted)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, 40)

                if let error {
                    Text(error).font(Typo.meta).foregroundStyle(Color.flagged).padding(.horizontal, 40)
                }

                Button { openVerification() } label: { Text("Continue") }
                    .buttonStyle(PrimaryButtonStyle(isEnabled: code.count >= 4))
                    .disabled(code.count < 4)
                    .padding(.horizontal, 40)

                Button { showQRScanner = true } label: {
                    Text("or scan QR code").font(Typo.meta).foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
    }

    // ═══════════ COMPLETED ═══════════

    private var completedView: some View {
        VStack(spacing: 20) {
            Spacer()

            Circle().fill(Color.clear_.opacity(0.1)).frame(width: 72, height: 72)
                .overlay { Image(systemName: "checkmark").font(.title).foregroundStyle(Color.clear_) }

            Text("Verification Submitted").font(Typo.context)
            Text("The agent will review your results. You can close this app now.")
                .font(Typo.meta).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button { appState.showSubjectFlow = false } label: { Text("Done") }
                .buttonStyle(PrimaryButtonStyle()).padding(.horizontal, 48)

            Spacer()
        }
    }

    // ═══════════ LOGIC ═══════════

    private func openVerification() {
        // The code contains a session reference. The agent's invite includes
        // a hosted verification URL. For now, we construct the hosted URL
        // from the code. In production, this would be looked up.
        //
        // The hosted verification URL format from the API:
        // https://verify.didit.me/session/{session_token}
        //
        // Since the subject doesn't have the full URL, we open a redirect page
        // that the agent's share message would have included.

        error = nil

        let cleaned = code.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "OC-", with: "")
            .replacingOccurrences(of: "oc-", with: "")

        guard !cleaned.isEmpty else { error = "Please enter a valid code"; return }

        // The code maps to a session. The subject would normally receive
        // a link that opens the app. If they only have the code, we show
        // a message to contact the agent for the full link.
        //
        // If we have a deep link URL with session info, open the hosted flow:
        if let url = URL(string: "https://verify.didit.me/session/\(cleaned)") {
            sessionURL = url
            showVerification = true
        } else {
            error = "Invalid code format"
        }
    }

    private func parseQR(_ value: String) {
        // QR can be: deep link (oceancheck://verify?session=...) or hosted URL
        if let url = URL(string: value) {
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let session = components.queryItems?.first(where: { $0.name == "session" })?.value {
                code = session
            } else if value.contains("verify") || value.contains("session") {
                // Direct hosted URL
                sessionURL = url
                showVerification = true
                return
            }
        }
        if !value.isEmpty && code.isEmpty {
            code = value
        }
        if !code.isEmpty {
            openVerification()
        }
    }
}

// MARK: - Safari Cover (embedded browser for hosted verification)

struct SafariCover: UIViewControllerRepresentable {
    let url: URL
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        let vc = SFSafariViewController(url: url, configuration: config)
        vc.delegate = context.coordinator
        // vc.preferredControlTintColor deprecated in iOS 26
        return vc
    }
    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onDismiss: onDismiss) }

    class Coordinator: NSObject, SFSafariViewControllerDelegate {
        let onDismiss: () -> Void
        init(onDismiss: @escaping () -> Void) { self.onDismiss = onDismiss }
        func safariViewControllerDidFinish(_ controller: SFSafariViewController) { onDismiss() }
    }
}

// MARK: - QR Scanner

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
            preview.frame = view.bounds; preview.videoGravity = .resizeAspectFill
            view.layer.addSublayer(preview)

            let label = UILabel()
            label.text = "Point at the QR code"; label.textColor = .white; label.font = .systemFont(ofSize: 16, weight: .medium)
            label.textAlignment = .center; label.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(label)
            NSLayoutConstraint.activate([label.centerXAnchor.constraint(equalTo: view.centerXAnchor), label.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -60)])

            DispatchQueue.global().async { [weak self] in self?.session.startRunning() }
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput results: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard !found, let result = results.first as? AVMetadataMachineReadableCodeObject, let value = result.stringValue else { return }
            found = true; session.stopRunning()
            dismiss(animated: true) { self.onScan(value) }
        }

        override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); session.stopRunning() }
    }
}
