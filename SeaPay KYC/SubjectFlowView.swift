//
//  SubjectFlowView.swift
//  OceanCheck
//
//  Subject self-verification — native consent, then Didit hosted verification.
//  Enter link/scan QR → consent → hosted verification → done.
//

import SwiftUI
import WebKit
import AVFoundation

struct SubjectFlowView: View {
    var appState: AppState

    @State private var phase: Phase = .enterCode
    enum Phase: Equatable { case enterCode, consent, verify, complete, uploadDocs, error }

    // Session
    @State private var code = ""
    @State private var hostedURL = ""
    @State private var agentName = ""
    @State private var showQRScanner = false

    // State
    @State private var error = ""
    @State private var consent = false
    @State private var showDoneButton = false

    // Certificate upload
    @State private var capturedCerts: [(type: MaritimeDocType, data: Data)] = []
    @State private var showCertCamera = false
    @State private var currentCertType: MaritimeDocType?
    @State private var certImage: Data?

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .enterCode: enterCodeView
                case .consent: consentView
                case .verify: verifyWebView
                case .complete: completeView
                case .uploadDocs: uploadDocsView
                case .error: errorView
                }
            }
            .background(Color.surface.ignoresSafeArea())
            .animation(.smooth(duration: 0.3), value: phase)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { Text("OceanCheck").font(BrandFont.brand(17)) }
                ToolbarItem(placement: .cancellationAction) {
                    if phase == .enterCode || phase == .consent {
                        Button { if phase == .enterCode { appState.showSubjectFlow = false } else { withAnimation { phase = .enterCode } } } label: {
                            Image(systemName: phase == .enterCode ? "xmark" : "chevron.left").foregroundStyle(.secondary)
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if phase == .verify && showDoneButton {
                        Button { withAnimation { phase = .complete } } label: {
                            Text("Done").fontWeight(.medium)
                        }
                    }
                }
            }
            .sheet(isPresented: $showQRScanner) { QRScannerView { v in showQRScanner = false; parseInput(v) } }
        }
    }

    // ═══════════ ENTER CODE ═══════════

    private var enterCodeView: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 28) {
                Image(systemName: "checkmark.shield").font(.system(size: 40)).foregroundStyle(.primary.opacity(0.15))
                Text("Verify Your Identity").font(Typo.context)

                // Two peer options
                VStack(spacing: 10) {
                    // Scan QR — primary for in-person
                    Button { showQRScanner = true } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "qrcode.viewfinder").font(.system(size: 20)).frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Scan QR Code").font(Typo.body).fontWeight(.medium)
                                Text("Point camera at the agent's screen").font(Typo.meta).opacity(0.7)
                            }
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Color.primary)
                        .foregroundStyle(Color.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    // Paste link — secondary for remote
                    VStack(spacing: 10) {
                        TextField("Paste invite link here", text: $code)
                            .font(Typo.body)
                            .multilineTextAlignment(.center)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .padding(14).background(Color.surfaceMuted)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .onChange(of: code) { _, newValue in
                                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                if trimmed.contains("://") { parseInput(trimmed) }
                            }

                        if code.count >= 8 {
                            Button { parseInput(code) } label: { Text("Continue") }
                                .buttonStyle(PrimaryButtonStyle())
                                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        }
                    }
                }
                .padding(.horizontal, 32)
            }
            Spacer()
        }
        .onAppear { handleDeepLinkIfNeeded() }
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

                Button { showDoneButton = false; withAnimation { phase = .verify } } label: { Text("Begin") }
                    .buttonStyle(PrimaryButtonStyle(isEnabled: consent)).disabled(!consent).padding(.horizontal, 40)

                Button { appState.showSubjectFlow = false } label: {
                    Text("Decline").font(Typo.meta).foregroundStyle(.secondary)
                }

                Spacer(minLength: 32)
            }
        }
    }

    private func step(_ num: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Text(num).font(Typo.body).foregroundStyle(Color.surface).frame(width: 26, height: 26).background(Color.primary).clipShape(Circle())
            Text(text).font(Typo.body)
        }
    }

    // ═══════════ VERIFY (Hosted WebView) ═══════════

    private var verifyWebView: some View {
        Group {
            if let url = URL(string: hostedURL) {
                VerificationWebView(url: url) {
                    withAnimation { showDoneButton = true }
                }
                .ignoresSafeArea(edges: .bottom)
            } else {
                VStack(spacing: 16) {
                    Text("Invalid verification URL").font(Typo.body).foregroundStyle(.secondary)
                    Button { withAnimation { phase = .enterCode } } label: { Text("Go Back") }
                        .buttonStyle(PrimaryButtonStyle()).padding(.horizontal, 48)
                }
            }
        }
    }

    // ═══════════ COMPLETE ═══════════

    private var completeView: some View {
        VStack(spacing: 24) {
            Spacer()
            Circle().fill(Color.clear_.opacity(0.1)).frame(width: 72, height: 72)
                .overlay { Image(systemName: "checkmark").font(.title).foregroundStyle(Color.clear_) }
            Text("Identity Verified").font(Typo.context)

            VStack(spacing: 12) {
                Text("Speed up your onboarding by uploading your maritime certificates now.").font(Typo.meta).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 32)

                Button { withAnimation { phase = .uploadDocs } } label: { Text("Upload Certificates") }
                    .buttonStyle(PrimaryButtonStyle()).padding(.horizontal, 48)

                Button { appState.showSubjectFlow = false } label: {
                    Text("Skip for now").font(Typo.meta).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    // ═══════════ UPLOAD DOCS ═══════════

    private let commonDocs: [MaritimeDocType] = [
        .seamansBook, .medicalENG1, .stcwBST, .securityAwareness,
        .cocDeck, .cocEngine, .gmdss, .flagEndorsement, .survivalCraft
    ]

    private var uploadDocsView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    Text("Your Certificates").font(Typo.context).padding(.top, 20)
                    Text("Photograph each certificate you have").font(Typo.meta).foregroundStyle(.secondary)

                    VStack(spacing: 6) {
                        ForEach(commonDocs) { docType in
                            let captured = capturedCerts.contains(where: { $0.type == docType })
                            Button {
                                currentCertType = docType
                                showCertCamera = true
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: docType.icon).font(.system(size: 14))
                                        .foregroundStyle(captured ? Color.clear_ : .secondary)
                                        .frame(width: 28)
                                    Text(docType.displayName).font(Typo.body).lineLimit(1)
                                    Spacer()
                                    if captured {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.clear_)
                                    } else {
                                        Image(systemName: "camera").foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 16).padding(.vertical, 13)
                                .background(captured ? Color.clear_.opacity(0.06) : Color.surfaceMuted)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                    .padding(.horizontal, 20)

                    Spacer(minLength: 32)
                }
            }

            // Bottom bar
            VStack(spacing: 8) {
                if !capturedCerts.isEmpty {
                    Text("\(capturedCerts.count) certificate\(capturedCerts.count == 1 ? "" : "s") captured").font(Typo.meta).foregroundStyle(Color.clear_)
                }
                Button { appState.showSubjectFlow = false } label: {
                    Text(capturedCerts.isEmpty ? "Skip" : "Done")
                }
                .buttonStyle(PrimaryButtonStyle()).padding(.horizontal, 32)
            }
            .padding(.vertical, 12).background(.bar)
        }
        .fullScreenCover(isPresented: $showCertCamera) {
            CameraCapture(result: $certImage).ignoresSafeArea()
        }
        .onChange(of: certImage) { _, newValue in
            if let data = newValue, let docType = currentCertType {
                capturedCerts.append((type: docType, data: data))
                certImage = nil
            }
        }
    }

    // ═══════════ ERROR ═══════════

    private var errorView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "xmark.circle").font(.system(size: 48)).foregroundStyle(Color.flagged.opacity(0.5))
            Text(error).font(Typo.meta).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 32)
            Button { withAnimation { phase = .enterCode } } label: { Text("Try Again") }
                .buttonStyle(PrimaryButtonStyle()).padding(.horizontal, 48)
            Button { appState.showSubjectFlow = false } label: { Text("Cancel").font(Typo.meta).foregroundStyle(.secondary) }
            Spacer()
        }
    }

    // ═══════════ PARSE INPUT ═══════════

    private func parseInput(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Deep link: oceancheck://verify?session=X&url=Y&agent=Z
        if let url = URL(string: trimmed), let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           url.scheme == AppConfiguration.urlScheme {
            hostedURL = components.queryItems?.first(where: { $0.name == "url" })?.value?.removingPercentEncoding ?? ""
            agentName = components.queryItems?.first(where: { $0.name == "agent" })?.value?.removingPercentEncoding ?? ""
            if !hostedURL.isEmpty { withAnimation { phase = .consent }; return }
        }

        // Direct hosted URL (https://...)
        if trimmed.hasPrefix("https://"), let url = URL(string: trimmed), url.host != nil {
            hostedURL = trimmed
            withAnimation { phase = .consent }
            return
        }

        error = "Please paste the full link from your agent's message, or scan the QR code."
        withAnimation { phase = .error }
    }

    private func handleDeepLinkIfNeeded() {
        guard let url = appState.incomingDeepLink else { return }
        appState.incomingDeepLink = nil
        parseInput(url.absoluteString)
    }
}

// MARK: - Verification WebView (with JS completion detection)

struct VerificationWebView: UIViewRepresentable {
    let url: URL
    let onComplete: () -> Void

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        // Inject a script that polls the DOM for completion signals every 2s
        let js = WKUserScript(source: Self.detectionScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        config.userContentController.addUserScript(js)
        config.userContentController.add(context.coordinator, name: "completionHandler")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.bounces = false
        webView.load(URLRequest(url: url))
        return webView
     }

    func updateUIView(_ webView: WKWebView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onComplete: onComplete) }

    // JS that watches for Didit's completion state via DOM polling + MutationObserver
    private static let detectionScript = """
    (function() {
        var done = false;
        var signals = ['completed', 'approved', 'verified', 'thank you', 'all done',
                       'verification complete', 'successfully', 'submitted'];

        function check() {
            if (done) return;
            var text = (document.title + ' ' + (document.body ? document.body.innerText : '')).toLowerCase();
            for (var i = 0; i < signals.length; i++) {
                if (text.indexOf(signals[i]) !== -1) {
                    done = true;
                    window.webkit.messageHandlers.completionHandler.postMessage('done');
                    return;
                }
            }
        }

        // Poll every 2 seconds
        setInterval(check, 2000);

        // Also observe DOM mutations for faster detection
        if (typeof MutationObserver !== 'undefined' && document.body) {
            var obs = new MutationObserver(function() { check(); });
            obs.observe(document.body, { childList: true, subtree: true, characterData: true });
        }
    })();
    """

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let onComplete: () -> Void
        private var fired = false
        init(onComplete: @escaping () -> Void) { self.onComplete = onComplete }

        // JS → Swift callback
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard !fired, message.name == "completionHandler" else { return }
            fired = true
            DispatchQueue.main.async { self.onComplete() }
        }

        // Grant camera access
        func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(.grant)
        }

        // Re-inject the detection script after SPA navigations
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript(VerificationWebView.detectionScript, completionHandler: nil)
        }
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
