//
//  BatchInviteSheet.swift
//  OceanCheck
//
//  Multi-name invite: paste a list, send all at once.
//

import SwiftUI

struct BatchInviteSheet: View {
    @ObservedObject var vm: KYCViewModel
    var vesselId: String?
    @Environment(\.dismiss) private var dismiss

    @State private var input = ""
    @State private var progress: KYCViewModel.BatchProgress?
    @State private var done = false
    @State private var showShare = false

    private var names: [String] {
        input.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private var agent: String {
        let full = UserDefaults.standard.string(forKey: "agentName") ?? "Agent"
        let p = full.split(separator: " "); guard let f = p.first else { return full }
        return p.count > 1 ? "\(f) \(p.last!.first!.uppercased())." : String(f)
    }

    private var shareMessage: String {
        guard let progress else { return "" }
        var msg = "Please verify your identity:\n\n"
        for r in progress.results {
            if let url = r.url { msg += "\(r.name): \(url)\n" }
        }
        msg += "\nTakes 2 minutes each.\n\u{2014} \(agent), SeaPay\u{00AE}"
        return msg
    }

    var body: some View {
        NavigationStack {
            Group {
                if done { doneView }
                else if progress != nil { progressView }
                else { inputView }
            }
            .background(Color.surface.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if progress == nil || done { Button("Close") { dismiss() } }
                }
            }
        }
    }

    // MARK: - Input

    private var inputView: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 16)
            Text("Batch Invite").font(Typo.context)
            Text("One name per line").font(Typo.meta).foregroundStyle(.secondary)

            TextEditor(text: $input)
                .font(Typo.body)
                .frame(minHeight: 200)
                .padding(12)
                .background(Color.surfaceMuted)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 24)

            if !names.isEmpty {
                Text("\(names.count) people").font(Typo.meta).foregroundStyle(.secondary)
            }

            Button {
                Task { await runBatch() }
            } label: { Text("Invite \(names.count) People") }
                .buttonStyle(PrimaryButtonStyle(isEnabled: !names.isEmpty))
                .disabled(names.isEmpty)
                .padding(.horizontal, 32)

            Spacer()
        }
    }

    // MARK: - Progress

    private var progressView: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                Circle().stroke(Color.primary.opacity(0.06), lineWidth: 5)
                Circle().trim(from: 0, to: CGFloat(progress?.completed ?? 0) / CGFloat(max(progress?.total ?? 1, 1)))
                    .stroke(Color.primary, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.4), value: progress?.completed)
                Text("\(progress?.completed ?? 0)/\(progress?.total ?? 0)")
                    .font(Typo.context).monospacedDigit()
            }
            .frame(width: 96, height: 96)
            .transition(.scale.combined(with: .opacity))

            Text("Creating invite sessions...").font(Typo.meta).foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: - Done

    private var doneView: some View {
        VStack(spacing: 20) {
            Spacer()
            Circle().fill(Color.clear_.opacity(0.08)).frame(width: 72, height: 72)
                .overlay { Image(systemName: "paperplane").font(.system(size: 24)).foregroundStyle(Color.clear_) }
                .transition(.scale.combined(with: .opacity))
            Text("Invites Ready").font(Typo.context)

            let succeeded = progress?.results.filter { $0.url != nil }.count ?? 0
            let failed = progress?.results.filter { $0.error != nil }.count ?? 0
            Text("\(succeeded) created\(failed > 0 ? " · \(failed) failed" : "")").font(Typo.meta).foregroundStyle(.secondary)

            Button { showShare = true } label: { Text("Share All Links") }
                .buttonStyle(PrimaryButtonStyle()).padding(.horizontal, 40)
                .sheet(isPresented: $showShare) { ActivityView(items: [shareMessage]) }

            Button("Close") { dismiss() }
                .buttonStyle(SecondaryButtonStyle()).padding(.horizontal, 40)

            Spacer()
        }
    }

    // MARK: - Run

    private func runBatch() async {
        for await p in vm.createBatchInvites(names: names, vesselId: vesselId) {
            progress = p
        }
        withAnimation { done = true }
    }
}
