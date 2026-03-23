//
//  SetupView.swift
//  OceanCheck
//
//  Sequential setup: one field per screen. Also used as settings sheet.
//

import SwiftUI
import UniformTypeIdentifiers

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
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
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
        VStack(spacing: 20) {
            Image(systemName: "checkmark.shield").font(.system(size: 48)).foregroundStyle(.primary.opacity(0.2))
                .padding(.bottom, 8)
            Text("OceanCheck").font(BrandFont.brand(32))
            Text("Maritime Identity & Compliance").font(Typo.meta).foregroundStyle(.secondary)

            Spacer().frame(height: 24)

            // Feature highlights
            VStack(alignment: .leading, spacing: 14) {
                featureRow("ferry", "Vessel Management", "Add vessels, scan Certificates of Registry")
                featureRow("person.text.rectangle", "Crew Verification", "KYC checks, document tracking, AML screening")
                featureRow("person.badge.key", "UBO Compliance", "Beneficial ownership verification")
                featureRow("doc.text", "Reports & Exports", "PDF reports, crew lists, CSV exports")
            }
            .padding(.horizontal, 40)

            Spacer().frame(height: 24)

            Button { withAnimation { step = 1 } } label: {
                Text("Get Started")
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 48)
        }
    }

    private func featureRow(_ icon: String, _ title: String, _ desc: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 20)).foregroundStyle(.primary.opacity(0.4)).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Typo.body).fontWeight(.medium)
                Text(desc).font(Typo.meta).foregroundStyle(.secondary)
            }
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
    @State private var claudeKey = ""
    @State private var agentName = ""
    @State private var workflowID = ""
    @State private var showReset = false
    @State private var showExportBackup = false
    @State private var showImportBackup = false
    @State private var colorSchemePreference = UserDefaults.standard.integer(forKey: "colorSchemePreference")
    @State private var backupURL: URL?
    @State private var backupMessage = ""

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "v\(v) (\(b))"
    }

    private var statsLine: String {
        let c = vm.checks.count
        let v = vm.vessels.count
        return "\(c) check\(c == 1 ? "" : "s"), \(v) vessel\(v == 1 ? "" : "s")"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Profile header
                    VStack(spacing: 8) {
                        Circle().fill(Color.surfaceMuted).frame(width: 64, height: 64)
                            .overlay { Text(String(agentName.prefix(1)).uppercased()).font(.system(size: 24, weight: .semibold)).foregroundStyle(.secondary) }

                        Text(agentName.isEmpty ? "Agent" : agentName).font(Typo.context)
                        Text(statsLine).font(Typo.meta).foregroundStyle(.secondary)
                    }
                    .padding(.top, 24).padding(.bottom, 20)

                    // Account
                    settingsSection("Account") {
                        settingsRow(icon: "person", label: "Your Name") {
                            TextField("Name", text: $agentName)
                                .textContentType(.name)
                                .font(Typo.body).multilineTextAlignment(.trailing)
                        }
                        Divider().padding(.leading, 44)
                        settingsRow(icon: "key", label: "Access Code") {
                            SecureField("Didit API Key", text: $apiKey)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .font(Typo.body).multilineTextAlignment(.trailing)
                        }
                        Divider().padding(.leading, 44)
                        settingsRow(icon: "brain", label: "Claude API Key") {
                            SecureField("For document OCR", text: $claudeKey)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .font(Typo.body).multilineTextAlignment(.trailing)
                        }
                        Divider().padding(.leading, 44)
                        settingsRow(icon: "link", label: "Workflow ID") {
                            TextField("For invitations", text: $workflowID)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .font(Typo.body).multilineTextAlignment(.trailing)
                        }
                    }

                    // Appearance
                    settingsSection("Appearance") {
                        Picker(selection: $colorSchemePreference) {
                            Text("System").tag(0)
                            Text("Light").tag(1)
                            Text("Dark").tag(2)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "circle.lefthalf.filled").font(.system(size: 15)).foregroundStyle(.secondary).frame(width: 24)
                                Text("Theme").font(Typo.body)
                            }
                        }
                        .pickerStyle(.menu)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .onChange(of: colorSchemePreference) { _, val in
                            UserDefaults.standard.set(val, forKey: "colorSchemePreference")
                        }
                    }

                    // Data
                    settingsSection("Data") {
                        Button {
                            if let url = vm.exportBackup() {
                                backupURL = url
                                showExportBackup = true
                            } else {
                                backupMessage = "Backup failed. Please try again."
                            }
                        } label: {
                            settingsActionRow(icon: "square.and.arrow.up", label: "Export Backup", detail: "Save all data as a file")
                        }
                        Divider().padding(.leading, 44)
                        Button { showImportBackup = true } label: {
                            settingsActionRow(icon: "square.and.arrow.down", label: "Import Backup", detail: "Restore from a backup file")
                        }
                    }

                    // Danger zone
                    settingsSection("") {
                        Button { showReset = true } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "trash").font(.system(size: 15)).foregroundStyle(Color.flagged).frame(width: 24)
                                Text("Reset All Data").font(Typo.body).foregroundStyle(Color.flagged)
                                Spacer()
                            }
                            .padding(.horizontal, 16).padding(.vertical, 14)
                        }
                    }

                    // App info
                    VStack(spacing: 4) {
                        Text("OceanCheck").font(BrandFont.brand(14)).foregroundStyle(.quaternary)
                        Text(version).font(Typo.meta).foregroundStyle(.quaternary)
                    }
                    .padding(.top, 24).padding(.bottom, 32)
                }
            }
            .background(Color.surface.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { Text("Settings").font(Typo.body).fontWeight(.semibold) }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { save(); dismiss() } }
            }
            .onAppear {
                apiKey = KeychainService.get(.diditAPIKey) ?? ""
                claudeKey = KeychainService.get(.claudeAPIKey) ?? ""
                agentName = UserDefaults.standard.string(forKey: "agentName") ?? ""
                workflowID = KeychainService.get(.workflowID) ?? ""
            }
            .alert("Reset Everything", isPresented: $showReset) {
                Button("Cancel", role: .cancel) {}
                Button("Delete All", role: .destructive) { vm.resetAll(); dismiss(); appState.didReset() }
            } message: { Text("This permanently deletes all checks, vessels, documents, images, and reports.") }
            .sheet(isPresented: $showExportBackup) { if let url = backupURL { ActivityView(items: [url]) } }
            .sheet(isPresented: $showImportBackup) {
                BackupImportPicker { url in
                    showImportBackup = false
                    guard let url else { return }
                    if vm.importBackup(from: url) {
                        dismiss()
                    } else {
                        backupMessage = "Import failed. The file may be corrupted."
                    }
                }
            }
            .alert("Backup", isPresented: .constant(!backupMessage.isEmpty)) {
                Button("OK") { backupMessage = "" }
            } message: {
                Text(backupMessage)
            }
        }
    }

    // MARK: - Components

    private func settingsSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !title.isEmpty {
                Text(title.uppercased()).font(Typo.meta).foregroundStyle(.secondary).tracking(0.6)
                    .padding(.horizontal, 20).padding(.bottom, 6)
            }
            VStack(spacing: 0) { content() }
                .background(Color.surfaceMuted.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 16)
        }
        .padding(.top, 16)
    }

    private func settingsRow(icon: String, label: String, @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 15)).foregroundStyle(.secondary).frame(width: 24)
            Text(label).font(Typo.body).foregroundStyle(.secondary)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func settingsActionRow(icon: String, label: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 15)).foregroundStyle(.primary).frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(Typo.body).foregroundStyle(.primary)
                Text(detail).font(Typo.meta).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    // MARK: - Save

    private func save() {
        let k = apiKey.trimmingCharacters(in: .whitespaces)
        if !k.isEmpty { KeychainService.save(k, for: .diditAPIKey) }
        let c = claudeKey.trimmingCharacters(in: .whitespaces)
        if !c.isEmpty { KeychainService.save(c, for: .claudeAPIKey) } else { KeychainService.delete(.claudeAPIKey) }
        let n = agentName.trimmingCharacters(in: .whitespaces)
        if !n.isEmpty { UserDefaults.standard.set(n, forKey: "agentName") }
        let w = workflowID.trimmingCharacters(in: .whitespaces)
        if !w.isEmpty { KeychainService.save(w, for: .workflowID) } else { KeychainService.delete(.workflowID) }
    }
}

// MARK: - Backup Import Picker

struct BackupImportPicker: UIViewControllerRepresentable {
    let onPick: (URL?) -> Void
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.zip, .data, .json])
        picker.delegate = context.coordinator; return picker
    }
    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL?) -> Void
        init(onPick: @escaping (URL?) -> Void) { self.onPick = onPick }
        func documentPicker(_ c: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { onPick(urls.first) }
        func documentPickerWasCancelled(_ c: UIDocumentPickerViewController) { onPick(nil) }
    }
}
