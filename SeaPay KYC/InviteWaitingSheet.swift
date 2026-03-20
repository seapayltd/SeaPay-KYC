//
//  InviteWaitingSheet.swift
//  OceanCheck
//
//  Agent-side: shows QR code + polls for subject to complete self-verification.
//

import SwiftUI
import CoreImage

struct InviteWaitingSheet: View {
    @ObservedObject var vm: KYCViewModel
    let check: KYCCheck
    @Environment(\.dismiss) private var dismiss

    @State private var sessionId = ""
    @State private var qrURL = ""
    @State private var verifyURL = ""
    @State private var error: String?
    @State private var creating = true
    @State private var polling = false
    @State private var sessionStatus = "Not Started"
    @State private var completed = false
    @State private var pollTimer: Timer?

    var body: some View {
        NavigationStack {
            Group {
                if creating {
                    VStack(spacing: 16) { Spacer(); ProgressView(); Text("Creating session...").font(.subheadline).foregroundStyle(.secondary); Spacer() }
                } else if let error {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "xmark.circle.fill").font(.system(size: 48)).foregroundStyle(Color.fail)
                        Text(error).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 32)
                        Button("Retry") { Task { await createSession() } }.buttonStyle(PrimaryButtonStyle()).padding(.horizontal, 32)
                        Spacer()
                    }
                } else if completed {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "checkmark.seal.fill").font(.system(size: 48)).foregroundStyle(Color.pass)
                        Text("Verification Received").font(.title3.weight(.semibold))
                        Text("Results are available in the check details.").font(.subheadline).foregroundStyle(.secondary)
                        Button("View Results") { dismiss() }.buttonStyle(PrimaryButtonStyle()).padding(.horizontal, 32)
                        Spacer()
                    }
                } else {
                    waitingView
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

    private var waitingView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text(check.customerName).font(.headline)
                    .padding(.top, 12)

                // QR Code
                if let qrImage = generateQR(qrURL) {
                    VStack(spacing: 6) {
                        Image(uiImage: qrImage)
                            .interpolation(.none)
                            .resizable().scaledToFit()
                            .frame(width: 200, height: 200)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(color: .black.opacity(0.1), radius: 12, y: 4)

                        Text("Show this to \(check.customerName)").font(.caption).foregroundStyle(.secondary)
                    }
                }

                // Share options
                VStack(spacing: 10) {
                    if !verifyURL.isEmpty {
                        ShareLink(item: verifyURL) {
                            Label("Share Verification Link", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }

                    Button {
                        UIPasteboard.general.string = qrURL
                    } label: {
                        Label("Copy QR Link", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                .padding(.horizontal, 24)

                // Status
                VStack(spacing: 8) {
                    Divider()
                    HStack(spacing: 10) {
                        if polling {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "clock").foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Status: \(sessionStatus)").font(.subheadline.weight(.medium))
                            Text("Checking every 5 seconds...").font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                }

                Spacer(minLength: 32)
            }
        }
    }

    // MARK: - Session + Polling

    private func createSession() async {
        creating = true; error = nil
        do {
            let result = try await vm.createInviteSession(checkId: check.id)
            sessionId = result.sessionId
            qrURL = result.qrURL
            verifyURL = result.verifyURL
            creating = false
            startPolling()
        } catch {
            self.error = error.localizedDescription
            creating = false
        }
    }

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            Task { await pollOnce() }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate(); pollTimer = nil
    }

    private func pollOnce() async {
        guard !sessionId.isEmpty else { return }
        polling = true
        do {
            let decision = try await vm.pollSessionDecision(checkId: check.id, sessionId: sessionId)
            sessionStatus = decision.status
            if decision.status == "Approved" || decision.status == "Declined" {
                stopPolling()
                withAnimation { completed = true }
            }
        } catch {
            // Non-fatal — keep polling
        }
        polling = false
    }

    // MARK: - QR Generation

    private func generateQR(_ string: String) -> UIImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(string.data(using: .utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let ciImage = filter.outputImage else { return nil }
        let ctx = CIContext()
        guard let cgImage = ctx.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        let size: CGFloat = 512
        UIGraphicsBeginImageContextWithOptions(CGSize(width: size, height: size), true, 1.0)
        guard let gCtx = UIGraphicsGetCurrentContext() else { return nil }
        gCtx.interpolationQuality = .none
        gCtx.scaleBy(x: 1, y: -1); gCtx.translateBy(x: 0, y: -size)
        gCtx.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image
    }
}
