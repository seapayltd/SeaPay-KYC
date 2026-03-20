//
//  SetupView.swift
//  OceanCheck
//
//  Sequential setup: one field per screen. Also used as settings sheet.
//

import SwiftUI

// MARK: - Sequential Setup (first run — one field at a time)

struct SequentialSetupView: View {
    @ObservedObject var vm: KYCViewModel
    var appState: AppState

    @State private var step = 0 // 0 = welcome, 1 = access code, 2 = name
    @State private var apiKey = ""
    @State private var agentName = ""
    @State private var testing = false
    @State private var error: String?

    var body: some View {
        ZStack {
            Color.surface.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                Group {
                    switch step {
                    case 0: welcomeStep
                    case 1: codeStep
                    default: nameStep
                    }
                }
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                .id(step)

                Spacer()

                // Subject path — small, discoverable
                Button { appState.showSubjectFlow = true } label: {
                    Text("I have a verification code").font(Typo.meta).foregroundStyle(.secondary)
                }
                .padding(.bottom, 32)
            }
            .animation(.smooth(duration: 0.3), value: step)
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 24) {
            Text("OceanCheck").font(BrandFont.brand(32))
            Text("Maritime Identity Verification").font(Typo.meta).foregroundStyle(.secondary)

            Spacer().frame(height: 24)

            Button { withAnimation { step = 1 } } label: {
                Text("Get Started")
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 48)
        }
    }

    private var codeStep: some View {
        VStack(spacing: 20) {
            Text("Your access code").font(Typo.context)
            Text("Provided by your administrator").font(Typo.meta).foregroundStyle(.secondary)

            SecureField("Paste here", text: $apiKey)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .font(Typo.body).multilineTextAlignment(.center)
                .padding(16)
                .background(Color.surfaceMuted)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 48)

            if let error { Text(error).font(Typo.meta).foregroundStyle(Color.flagged) }

            Button {
                Task { await validateAndContinue() }
            } label: {
                if testing { ProgressView().tint(.surface) } else { Text("Continue") }
            }
            .buttonStyle(PrimaryButtonStyle(isEnabled: !apiKey.trimmingCharacters(in: .whitespaces).isEmpty && !testing))
            .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty || testing)
            .padding(.horizontal, 48)

            Button { withAnimation { step = 0 } } label: {
                Text("Back").font(Typo.meta).foregroundStyle(.secondary)
            }
        }
    }

    private var nameStep: some View {
        VStack(spacing: 20) {
            Text("Your name").font(Typo.context)
            Text("Appears on verification reports").font(Typo.meta).foregroundStyle(.secondary)

            TextField("First and last name", text: $agentName)
                .textContentType(.name).font(Typo.body).multilineTextAlignment(.center)
                .padding(16)
                .background(Color.surfaceMuted)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 48)

            Button {
                UserDefaults.standard.set(agentName.trimmingCharacters(in: .whitespaces), forKey: "agentName")
                appState.didConfigure()
            } label: {
                Text("Start Verifying")
            }
            .buttonStyle(PrimaryButtonStyle(isEnabled: !agentName.trimmingCharacters(in: .whitespaces).isEmpty))
            .disabled(agentName.trimmingCharacters(in: .whitespaces).isEmpty)
            .padding(.horizontal, 48)

            Button { withAnimation { step = 1 } } label: {
                Text("Back").font(Typo.meta).foregroundStyle(.secondary)
            }
        }
    }

    private func validateAndContinue() async {
        let key = apiKey.trimmingCharacters(in: .whitespaces)
        KeychainService.save(key, for: .diditAPIKey)
        testing = true; error = nil
        do {
            try await VerificationAPIService.shared.validateAPIKey()
            withAnimation { step = 2 }
        } catch {
            self.error = "Invalid code. Check with your administrator."
        }
        testing = false
    }
}

// MARK: - Settings Sheet (compact, used from gear icon)

struct SettingsSheet: View {
    @ObservedObject var vm: KYCViewModel
    var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var apiKey = ""
    @State private var agentName = ""
    @State private var workflowID = ""
    @State private var showReset = false

    var body: some View {
        NavigationStack {
            List {
                Section("Access Code") {
                    SecureField("API Key", text: $apiKey)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Section("Agent") {
                    TextField("Your Name", text: $agentName).textContentType(.name)
                }
                Section("Remote Invitations") {
                    TextField("Workflow ID (optional)", text: $workflowID)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("Required to invite others to self-verify.").font(Typo.meta).foregroundStyle(.secondary)
                }
                Section {
                    Button("Save") { save(); dismiss() }
                }
                Section {
                    Button("Reset All Data", role: .destructive) { showReset = true }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { save(); dismiss() } } }
            .onAppear { apiKey = KeychainService.get(.diditAPIKey) ?? ""; agentName = UserDefaults.standard.string(forKey: "agentName") ?? ""; workflowID = KeychainService.get(.workflowID) ?? "" }
            .alert("Reset Everything", isPresented: $showReset) {
                Button("Cancel", role: .cancel) {}
                Button("Delete All", role: .destructive) { vm.resetAll(); dismiss(); appState.didReset() }
            } message: { Text("Deletes all checks, images, reports, and your access code.") }
        }
    }

    private func save() {
        let k = apiKey.trimmingCharacters(in: .whitespaces)
        if !k.isEmpty { KeychainService.save(k, for: .diditAPIKey) }
        let n = agentName.trimmingCharacters(in: .whitespaces)
        if !n.isEmpty { UserDefaults.standard.set(n, forKey: "agentName") }
        let w = workflowID.trimmingCharacters(in: .whitespaces)
        if !w.isEmpty { KeychainService.save(w, for: .workflowID) }
    }
}
