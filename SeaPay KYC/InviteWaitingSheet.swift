//
//  InviteSheet.swift
//  OceanCheck
//
//  Agent creates invite → shows code + share message + QR → polls for completion.
//

import SwiftUI
import CoreImage

struct InviteSheet: View {
    @ObservedObject var vm: KYCViewModel
    let check: KYCCheck
    @Environment(\.dismiss) private var dismiss

    @State private var sessionId = ""
    @State private var inviteCode = ""
    @State private var error: String?
    @State private var creating = true
    @State private var polling = false
    @State private var status = "Waiting"
    @State private var completed = false
    @State private var pollTimer: Timer?
    @State private var showShareSheet = false
    @State private var codeCopied = false

    // App Store URL — replace with real ID after publishing
    private let appStoreURL = "https://apps.apple.com/app/oceancheck/id0000000000"

    private var agentName: String {
        let full = UserDefaults.standard.string(forKey: "agentName") ?? "Agent"
        let parts = full.split(separator: " ")
        guard let first = parts.first else { return full }
        return parts.count > 1 ? "\(first) \(parts.last!.first!.uppercased())." : String(first)
    }

    private var inviteMessage: String {
        """
        Hi \(check.customerName), please complete your identity verification:

        1. Download OceanCheck from the App Store:
        \(appStoreURL)

        2. Open the app → "Verify Myself" → enter code:
        \(inviteCode)

        Takes 2 minutes. Your data is processed securely.

        — \(agentName), SeaPay\u{00AE}
        """
    }

    private var deepLinkURL: String {
        "\(AppConfiguration.urlScheme)://verify?session=\(sessionId)&code=\(inviteCode)&agent=\(agentName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
    }

    var body: some View {
        NavigationStack {
            Group {
                if creating {
                    VStack(spacing: 16) { Spacer(); ProgressView(); Text("Setting up...").font(.subheadline).foregroundStyle(.secondary); Spacer() }
                } else if let error {
                    errorView(error)
                } else if completed {
                    completedView
                } else {
                    inviteView
                }
            }
            .background(Color.surfaceRaised.ignoresSafeArea())
            .navigationTitle("Invite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { stopPolling(); dismiss() } } }
            .task { await createSession() }
            .onDisappear { stopPolling() }
        }
    }

    // ═══════════ MAIN INVITE VIEW ═══════════

    private var inviteView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {

                // Header
                VStack(spacing: 4) {
                    Text("Invite \(check.customerName)").font(.headline)
                    Text("to verify their identity").font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.top, 12)

                // ── CODE ──
                VStack(spacing: 8) {
                    Text("VERIFICATION CODE").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary).tracking(1)

                    Text(inviteCode)
                        .font(.system(size: 36, weight: .bold, design: .monospaced))
                        .tracking(4)
                        .padding(.horizontal, 32).padding(.vertical, 16)
                        .background(Color.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
                        .onTapGesture { copyCode() }

                    if codeCopied {
                        Text("Copied!").font(.caption2.weight(.medium)).foregroundStyle(Color.pass)
                            .transition(.opacity)
                    } else {
                        Text("Tap to copy").font(.caption2).foregroundStyle(.secondary)
                    }
                }

                // ── SHARE ──
                Button { showShareSheet = true } label: {
                    Label("Send Invite", systemImage: "paperplane.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 24)

                // ── INSTRUCTIONS ──
                CardView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("TELL THEM TO:").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary).tracking(0.5)

                        instructionRow("1", "Download OceanCheck from the App Store")
                        instructionRow("2", "Open the app and tap \"Verify Myself\"")
                        instructionRow("3", "Enter code \(inviteCode)")
                    }
                }
                .padding(.horizontal, 24)

                // ── QR (secondary) ──
                VStack(spacing: 8) {
                    Text("Or scan in person").font(.caption).foregroundStyle(.secondary)

                    if let qr = generateQR(deepLinkURL) {
                        Image(uiImage: qr)
                            .interpolation(.none)
                            .resizable().scaledToFit()
                            .frame(width: 120, height: 120)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
                    }
                }

                // ── STATUS ──
                Divider().padding(.horizontal, 24)

                HStack(spacing: 10) {
                    if polling {
                        ProgressView().controlSize(.small)
                    } else {
                        Circle().fill(status == "Waiting" ? Color.warning : Color.pass).frame(width: 8, height: 8)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Status: \(status)").font(.subheadline.weight(.medium))
                        Text("Auto-checking every 5 seconds").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 28)

                Spacer(minLength: 32)
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ActivityView(items: [inviteMessage])
        }
    }

    // ═══════════ COMPLETED ═══════════

    private var completedView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.seal.fill").font(.system(size: 56)).foregroundStyle(Color.pass)
            VStack(spacing: 6) {
                Text("Verification Received").font(.title3.weight(.semibold))
                Text("\(check.customerName) has completed their verification. Review the results in the check details.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 32)
            }
            Button("View Results") { dismiss() }
                .buttonStyle(PrimaryButtonStyle()).padding(.horizontal, 32)
            Spacer()
        }
    }

    // ═══════════ ERROR ═══════════

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "xmark.circle.fill").font(.system(size: 48)).foregroundStyle(Color.fail)
            Text(msg).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 32)
            Button("Retry") { Task { await createSession() } }.buttonStyle(PrimaryButtonStyle()).padding(.horizontal, 32)
            Spacer()
        }
    }

    // ═══════════ HELPERS ═══════════

    private func instructionRow(_ num: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Text(num).font(.caption.bold()).foregroundStyle(.white)
                .frame(width: 20, height: 20).background(Color.brand).clipShape(Circle())
            Text(text).font(.caption)
        }
    }

    private func copyCode() {
        UIPasteboard.general.string = inviteCode
        withAnimation { codeCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { withAnimation { codeCopied = false } }
    }

    // ═══════════ SESSION + POLLING ═══════════

    private func createSession() async {
        creating = true; error = nil
        do {
            let result = try await vm.createInviteSession(checkId: check.id)
            sessionId = result.sessionId
            // Code = first 6 chars of session ID, uppercase
            inviteCode = "OC-" + String(result.sessionId.replacingOccurrences(of: "-", with: "").prefix(6)).uppercased()
            creating = false
            startPolling()
        } catch {
            self.error = error.localizedDescription
            creating = false
        }
    }

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in Task { await pollOnce() } }
    }

    private func stopPolling() { pollTimer?.invalidate(); pollTimer = nil }

    private func pollOnce() async {
        guard !sessionId.isEmpty else { return }
        polling = true
        do {
            let decision = try await vm.pollSessionDecision(checkId: check.id, sessionId: sessionId)
            status = decision.status
            if decision.status == "Approved" || decision.status == "Declined" {
                stopPolling()
                withAnimation { completed = true }
            }
        } catch { /* keep polling */ }
        polling = false
    }

    // ═══════════ QR ═══════════

    private func generateQR(_ string: String) -> UIImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(string.data(using: .utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let ci = filter.outputImage else { return nil }
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(ci, from: ci.extent) else { return nil }
        let s: CGFloat = 512
        UIGraphicsBeginImageContextWithOptions(CGSize(width: s, height: s), true, 1)
        guard let g = UIGraphicsGetCurrentContext() else { return nil }
        g.interpolationQuality = .none; g.scaleBy(x: 1, y: -1); g.translateBy(x: 0, y: -s)
        g.draw(cg, in: CGRect(x: 0, y: 0, width: s, height: s))
        let img = UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext()
        return img
    }
}
