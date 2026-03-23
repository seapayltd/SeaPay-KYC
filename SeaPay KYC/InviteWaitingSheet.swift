//
//  InviteSheet.swift
//  OceanCheck
//
//  Agent invite: create session, show QR, share link. That's all.
//  Polling lives in the ViewModel — it continues after this sheet is dismissed.
//

import SwiftUI
import CoreImage

struct InviteSheet: View {
    @ObservedObject var vm: KYCViewModel
    let check: KYCCheck
    @Environment(\.dismiss) private var dismiss

    @State private var hostedURL = ""
    @State private var error: String?
    @State private var creating = true
    @State private var showShare = false
    @State private var linkCopied = false
    @State private var sent = false

    private var agent: String {
        let full = UserDefaults.standard.string(forKey: "agentName") ?? "Agent"
        let p = full.split(separator: " "); guard let f = p.first else { return full }
        return p.count > 1 ? "\(f) \(p.last!.first!.uppercased())." : String(f)
    }

    private var message: String {
        var msg = "Please verify your identity for maritime compliance.\n\n"
        msg += "Open this link to start:\n\(hostedURL)\n\n"
        msg += "Takes 2 minutes.\n\u{2014} \(agent), SeaPay\u{00AE}"
        return msg
    }

    var body: some View {
        NavigationStack {
            Group {
                if creating { VStack { Spacer(); ProgressView(); Spacer() } }
                else if let error { errorView(error) }
                else if sent { sentView }
                else { mainView }
            }
            .animation(.smooth(duration: 0.3), value: creating)
            .animation(.smooth(duration: 0.3), value: sent)
            .background(Color.surface.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await create() }
        }
    }

    // MARK: - Views

    private var mainView: some View {
        VStack(spacing: 0) {
            Spacer()

            // Name context
            Text("Invite \(check.displayName)").font(Typo.meta).foregroundStyle(.secondary)
                .padding(.bottom, 20)

            // QR
            if let qr = generateQR(hostedURL) {
                Image(uiImage: qr)
                    .interpolation(.none).resizable().scaledToFit()
                    .frame(width: 200, height: 200)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            Spacer().frame(height: 28)

            // Actions
            VStack(spacing: 12) {
                Button { showShare = true } label: { Text("Send Invite") }
                    .buttonStyle(PrimaryButtonStyle()).padding(.horizontal, 48)
                    .sheet(isPresented: $showShare) {
                        ActivityView(items: [message])
                            .onDisappear { withAnimation(.smooth) { sent = true } }
                    }

                Button {
                    UIPasteboard.general.string = hostedURL
                    withAnimation { linkCopied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { withAnimation { linkCopied = false } }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: linkCopied ? "checkmark" : "doc.on.doc").font(Typo.meta)
                        Text(linkCopied ? "Copied" : "Copy Link").font(Typo.meta)
                    }.foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
    }

    private var sentView: some View {
        VStack(spacing: 20) {
            Spacer()
            Circle().fill(Color.clear_.opacity(0.08)).frame(width: 72, height: 72)
                .overlay { Image(systemName: "paperplane").font(.system(size: 24)).foregroundStyle(Color.clear_) }
            Text("Invite Sent").font(Typo.context)
            Text("Status updates automatically on the home screen.").font(Typo.meta).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 32)
            Button("Done") { dismiss() }.buttonStyle(PrimaryButtonStyle()).padding(.horizontal, 48)
            Spacer()
        }
    }

    private func errorView(_ msg: String) -> some View {
        VStack { Spacer(); Text(msg).font(Typo.meta).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(32); Button("Retry") { Task { await create() } }.buttonStyle(PrimaryButtonStyle()).padding(.horizontal, 48); Spacer() }
    }

    // MARK: - Create Session

    private func create() async {
        creating = true; error = nil
        do {
            let r = try await vm.createInviteSession(checkId: check.id)
            hostedURL = r.verifyURL
            creating = false
        } catch { self.error = error.localizedDescription; creating = false }
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
