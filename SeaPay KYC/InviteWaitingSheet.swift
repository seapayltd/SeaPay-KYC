//
//  InviteSheet.swift
//  OceanCheck
//
//  Agent invite: code + QR + share. QR encodes the hosted verification URL.
//

import SwiftUI
import CoreImage

struct InviteSheet: View {
    @ObservedObject var vm: KYCViewModel
    let check: KYCCheck
    @Environment(\.dismiss) private var dismiss

    @State private var sessionId = ""
    @State private var sessionToken = ""
    @State private var code = ""
    @State private var hostedURL = ""
    @State private var error: String?
    @State private var creating = true
    @State private var completed = false
    @State private var status = "Waiting"
    @State private var pollTimer: Timer?
    @State private var showShare = false
    @State private var codeCopied = false
    @State private var sent = false

    private let appStoreURL = "https://apps.apple.com/app/oceancheck/id0000000000"

    private var agent: String {
        let full = UserDefaults.standard.string(forKey: "agentName") ?? "Agent"
        let p = full.split(separator: " "); guard let f = p.first else { return full }
        return p.count > 1 ? "\(f) \(p.last!.first!.uppercased())." : String(f)
    }

    private var message: String {
        var msg = "Hi \(check.customerName), please verify your identity:\n\n"
        if !hostedURL.isEmpty { msg += "Open this link:\n\(hostedURL)\n\n" }
        msg += "Or download OceanCheck and enter code \(code):\n\(appStoreURL)\n\n"
        msg += "Takes 2 minutes.\n— \(agent), SeaPay\u{00AE}"
        return msg
    }

    var body: some View {
        NavigationStack {
            Group {
                if creating { VStack { Spacer(); ProgressView(); Spacer() } }
                else if let error { VStack { Spacer(); Text(error).font(Typo.meta).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(32); Button("Retry") { Task { await create() } }.buttonStyle(PrimaryButtonStyle()).padding(.horizontal, 48); Spacer() } }
                else if completed { doneView }
                else { mainView }
            }
            .background(Color.surface.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { stop(); dismiss() } } }
            .task { await create() }
            .onDisappear { stop() }
        }
    }

    private var mainView: some View {
        VStack(spacing: 0) {
            Spacer()

            if !sent {
                VStack(spacing: 24) {
                    // QR — encodes deep link with session token for native in-app verification
                    let qrData = "\(AppConfiguration.urlScheme)://verify?session=\(sessionId)&token=\(sessionToken)&agent=\(agent.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
                    if let qr = generateQR(qrData) {
                        VStack(spacing: 8) {
                            Image(uiImage: qr)
                                .interpolation(.none)
                                .resizable().scaledToFit()
                                .frame(width: 180, height: 180)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))

                            Text("Show this to \(check.customerName)").font(Typo.meta).foregroundStyle(.secondary)
                        }
                    }

                    // Code
                    VStack(spacing: 6) {
                        Text(code)
                            .font(.system(size: 32, weight: .bold, design: .monospaced))
                            .tracking(4)
                            .onTapGesture { UIPasteboard.general.string = code; withAnimation { codeCopied = true }; DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { withAnimation { codeCopied = false } } }
                        Text(codeCopied ? "Copied" : "Tap to copy code").font(Typo.meta).foregroundStyle(.secondary)
                    }

                    // Send (for remote)
                    Button { showShare = true } label: { Text("Send Invite") }
                        .buttonStyle(PrimaryButtonStyle()).padding(.horizontal, 48)
                        .sheet(isPresented: $showShare) {
                            ActivityView(items: [message])
                                .onDisappear { withAnimation(.smooth) { sent = true } }
                        }
                }
            } else {
                // Waiting state
                VStack(spacing: 16) {
                    Text(code).font(.system(size: 18, weight: .bold, design: .monospaced)).foregroundStyle(.secondary)
                    Circle().fill(Color.primary.opacity(0.06)).frame(width: 64, height: 64).overlay { ProgressView() }
                    Text("Waiting for \(check.customerName)...").font(Typo.body).foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
    }

    private var doneView: some View {
        VStack(spacing: 16) {
            Spacer()
            Circle().fill(Color.clear_.opacity(0.1)).frame(width: 64, height: 64)
                .overlay { Image(systemName: "checkmark").font(.title2).foregroundStyle(Color.clear_) }
            Text("Done").font(Typo.context)
            Text("\(check.customerName) completed verification.").font(Typo.meta).foregroundStyle(.secondary)
            Button("View Results") { dismiss() }.buttonStyle(PrimaryButtonStyle()).padding(.horizontal, 48)
            Spacer()
        }
    }

    // MARK: - Session + Polling

    private func create() async {
        creating = true; error = nil
        do {
            let r = try await vm.createInviteSession(checkId: check.id)
            sessionId = r.sessionId
            sessionToken = r.sessionToken
            hostedURL = r.verifyURL
            code = r.code
            creating = false; startPoll()
        } catch { self.error = error.localizedDescription; creating = false }
    }

    private func startPoll() { pollTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in Task { await poll() } } }
    private func stop() { pollTimer?.invalidate(); pollTimer = nil }

    private func poll() async {
        guard !sessionId.isEmpty else { return }
        do {
            let d = try await vm.pollSessionDecision(checkId: check.id, sessionId: sessionId)
            status = d.status
            if d.status == "Approved" || d.status == "Declined" { stop(); withAnimation { completed = true } }
        } catch {}
    }

    // MARK: - QR

    private func generateQR(_ string: String) -> UIImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(string.data(using: .utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let ci = filter.outputImage else { return nil }
        let ctx = CIContext(); guard let cg = ctx.createCGImage(ci, from: ci.extent) else { return nil }
        let s: CGFloat = 512
        UIGraphicsBeginImageContextWithOptions(CGSize(width: s, height: s), true, 1)
        guard let g = UIGraphicsGetCurrentContext() else { return nil }
        g.interpolationQuality = .none; g.scaleBy(x: 1, y: -1); g.translateBy(x: 0, y: -s)
        g.draw(cg, in: CGRect(x: 0, y: 0, width: s, height: s))
        let img = UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext()
        return img
    }
}
