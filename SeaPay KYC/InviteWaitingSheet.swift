//
//  InviteSheet.swift
//  OceanCheck
//
//  Two states: (1) code + send, (2) waiting. Minimal, calm.
//

import SwiftUI
import CoreImage

struct InviteSheet: View {
    @ObservedObject var vm: KYCViewModel
    let check: KYCCheck
    @Environment(\.dismiss) private var dismiss

    @State private var sessionId = ""
    @State private var code = ""
    @State private var verifyURL = "" // hosted verification URL from API
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
        if !verifyURL.isEmpty {
            msg += "Open this link to start:\n\(verifyURL)\n\n"
        }
        msg += "Or download OceanCheck and enter code \(code):\n\(appStoreURL)\n\n"
        msg += "Takes 2 minutes.\n— \(agent), SeaPay\u{00AE}"
        return msg
    }

    var body: some View {
        NavigationStack {
            Group {
                if creating { VStack { Spacer(); ProgressView(); Spacer() } }
                else if let error { VStack { Spacer(); Text(error).font(Typo.meta).foregroundStyle(.secondary).padding(32); Button("Retry") { Task { await create() } }.buttonStyle(PrimaryButtonStyle()).padding(.horizontal, 48); Spacer() } }
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

    // State 1: code + send
    private var mainView: some View {
        VStack(spacing: 0) {
            Spacer()

            if !sent {
                // Large code
                VStack(spacing: 12) {
                    Text(code)
                        .font(.system(size: 40, weight: .bold, design: .monospaced))
                        .tracking(6)
                        .onTapGesture { UIPasteboard.general.string = code; withAnimation { codeCopied = true }; DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { withAnimation { codeCopied = false } } }

                    Text(codeCopied ? "Copied" : "Tap to copy").font(Typo.meta).foregroundStyle(.secondary)
                }

                Spacer().frame(height: 32)

                Button { showShare = true } label: { Text("Send Invite") }
                    .buttonStyle(PrimaryButtonStyle()).padding(.horizontal, 48)
                    .sheet(isPresented: $showShare) {
                        ActivityView(items: [message])
                            .onDisappear { withAnimation(.smooth) { sent = true } }
                    }
            } else {
                // State 2: waiting — calm
                VStack(spacing: 16) {
                    Text(code).font(.system(size: 20, weight: .bold, design: .monospaced)).foregroundStyle(.secondary)

                    Circle()
                        .fill(Color.primary.opacity(0.06))
                        .frame(width: 64, height: 64)
                        .overlay { ProgressView() }

                    Text("Waiting for \(check.customerName)...")
                        .font(Typo.body).foregroundStyle(.secondary)
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

    private func create() async {
        creating = true; error = nil
        do {
            let r = try await vm.createInviteSession(checkId: check.id)
            sessionId = r.sessionId
            verifyURL = r.verifyURL
            code = "OC-" + String(r.sessionId.replacingOccurrences(of: "-", with: "").prefix(6)).uppercased()
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
}
