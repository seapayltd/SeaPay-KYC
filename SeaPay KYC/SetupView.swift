//
//  SetupView.swift
//  SeaPay KYC
//

import SwiftUI

struct SetupView: View {
    @ObservedObject var vm: KYCViewModel
    var isSheet = false
    var onComplete: (() -> Void)?
    var onReset: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    @State private var apiKey = ""
    @State private var agentName = ""
    @State private var workflowID = ""
    @State private var testing = false
    @State private var testResult: String?
    @State private var testOK = false
    @State private var showReset = false
    @State private var saved = false

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient.hero.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        if !isSheet {
                            // ── Brand mark ──
                            VStack(spacing: 20) {
                                ZStack {
                                    Circle()
                                        .fill(LinearGradient.brand)
                                        .frame(width: 96, height: 96)
                                        .shadow(color: Color.brand.opacity(0.35), radius: 20, y: 8)

                                    Image(systemName: "key.fill")
                                        .font(.system(size: 40, weight: .medium))
                                        .foregroundStyle(.white)
                                        .symbolRenderingMode(.hierarchical)
                                }

                                VStack(spacing: 6) {
                                    Text("OceanCheck")
                                        .font(BrandFont.brand(28))
                                    Text("Maritime Identity Verification")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.top, 56).padding(.bottom, 36)
                        }

                        // ── Form card ──
                        VStack(spacing: 20) {
                            if !isSheet {
                                Text("Connect your account")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            // API Key
                            VStack(alignment: .leading, spacing: 8) {
                                Label("API Key", systemImage: "key.fill")
                                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                SecureField("Paste your secret key", text: $apiKey)
                                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                                    .padding(14)
                                    .background(Color.surfaceMuted)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }

                            // Agent name
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Your Name", systemImage: "person.fill")
                                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                TextField("Displayed on reports", text: $agentName)
                                    .textContentType(.name)
                                    .padding(14)
                                    .background(Color.surfaceMuted)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }

                            // Workflow ID (for invite flow)
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Workflow ID", systemImage: "arrow.triangle.branch")
                                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                TextField("For remote invitations (optional)", text: $workflowID)
                                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                                    .padding(14)
                                    .background(Color.surfaceMuted)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                Text("Required to invite others to self-verify. Get it from your admin console.")
                                    .font(.system(size: 9)).foregroundStyle(.tertiary)
                            }

                            // Actions
                            Button { save() } label: {
                                HStack(spacing: 8) {
                                    if saved {
                                        Image(systemName: "checkmark").font(.subheadline.bold())
                                            .transition(.scale.combined(with: .opacity))
                                    }
                                    Text(saved ? "Saved" : "Save & Continue")
                                }
                            }
                            .buttonStyle(PrimaryButtonStyle(isEnabled: canSave && !saved))
                            .disabled(!canSave || saved)
                            .accessibilityLabel("Save settings")

                            Button { Task { await test() } } label: {
                                if testing {
                                    HStack(spacing: 8) { ProgressView(); Text("Testing...") }
                                } else {
                                    Label("Test Connection", systemImage: "antenna.radiowaves.left.and.right")
                                }
                            }
                            .buttonStyle(SecondaryButtonStyle())
                            .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty || testing)

                            // Test result
                            if let r = testResult {
                                HStack(spacing: 8) {
                                    Image(systemName: testOK ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                        .font(.body)
                                    Text(r).font(.caption)
                                }
                                .foregroundStyle(testOK ? Color.pass : Color.fail)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background((testOK ? Color.pass : Color.fail).opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        .padding(24)
                        .background(Color.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .shadow(color: .black.opacity(0.08), radius: 20, y: 8)
                        .padding(.horizontal, 20)

                        // ── Reset ──
                        if isSheet {
                            Button(role: .destructive) { showReset = true } label: {
                                Label("Reset All Data", systemImage: "trash")
                                    .font(.caption).foregroundStyle(Color.fail.opacity(0.6))
                            }
                            .padding(.top, 24)
                        }

                        Spacer(minLength: 50)
                    }
                }
            }
            .navigationTitle(isSheet ? "Settings" : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { if isSheet { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } } }
            .onAppear { apiKey = KeychainService.get(.diditAPIKey) ?? ""; agentName = UserDefaults.standard.string(forKey: "agentName") ?? ""; workflowID = KeychainService.get(.workflowID) ?? "" }
            .alert("Reset Everything", isPresented: $showReset) {
                Button("Cancel", role: .cancel) {}
                Button("Delete All", role: .destructive) {
                    vm.resetAll()
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onReset?() }
                }
            } message: { Text("Deletes all checks, images, reports, and API key.") }
        }
    }

    private var canSave: Bool {
        !apiKey.trimmingCharacters(in: .whitespaces).isEmpty && !agentName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func save() {
        KeychainService.save(apiKey.trimmingCharacters(in: .whitespaces), for: .diditAPIKey)
        UserDefaults.standard.set(agentName.trimmingCharacters(in: .whitespaces), forKey: "agentName")
        let wf = workflowID.trimmingCharacters(in: .whitespaces)
        if !wf.isEmpty { KeychainService.save(wf, for: .workflowID) }
        withAnimation(.spring(response: 0.3)) { saved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            if isSheet {
                dismiss()
            } else {
                onComplete?()
            }
        }
    }

    private func test() async {
        KeychainService.save(apiKey.trimmingCharacters(in: .whitespaces), for: .diditAPIKey)
        testing = true; withAnimation { testResult = nil }
        do {
            try await VerificationAPIService.shared.validateAPIKey()
            withAnimation { testResult = "Connection successful"; testOK = true }
        } catch {
            withAnimation { testResult = error.localizedDescription; testOK = false }
        }
        testing = false
    }
}
