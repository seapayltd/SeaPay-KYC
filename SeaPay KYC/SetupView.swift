//
//  SetupView.swift
//  OceanCheck
//
//  5-step setup: brand → access code → identity → role → confirmation.
//  Settings sheet with Identity / Connections separation.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Sequential Setup (5 steps)

struct SequentialSetupView: View {
    @ObservedObject var vm: KYCViewModel
    var appState: AppState
    @Binding var ownerAccessCode: String?
    var startAtStep: Int = 0
    @Environment(\.dismiss) private var dismiss

    @State private var step: Int = 0
    // Step 1: access code
    @State private var apiKey = ""
    @State private var testing = false
    @State private var error: String?
    // Step 2: identity
    @State private var firstName = ""
    @State private var lastName = ""
    // Step 3: role
    @State private var selectedRole: AgentRole?
    @State private var customRoleTitle = ""
    @State private var companyName = ""
    // Step 4: confirmation
    @State private var showCodeInfo = false

    private let totalSteps = 5

    var body: some View {
        ZStack {
            Color.surface.ignoresSafeArea()

            VStack(spacing: 0) {
                // Step indicator
                StepIndicator(totalSteps: 4, currentStep: max(step - 1, 0))
                    .padding(.top, 16)

                Spacer()

                Group {
                    switch step {
                    case 0, 1: codeStep
                    case 2: identityStep
                    case 3: roleStep
                    default: confirmStep
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
                .id(step)

                Spacer()

                Spacer().frame(height: 32)
            }
            .animation(.smooth(duration: 0.3), value: step)
        }
    }

    // MARK: - Step 1: Access Code

    private var codeStep: some View {
        VStack(spacing: 20) {
            HStack(spacing: 6) {
                Text("Connect to your verification service").font(Typo.context)
                Button { showCodeInfo = true } label: {
                    Image(systemName: "questionmark.circle").font(.system(size: 14)).foregroundStyle(.tertiary)
                }
                .popover(isPresented: $showCodeInfo) {
                    Text("This code links OceanCheck to your organization's Didit verification account. Contact your administrator if you don't have one.")
                        .font(Typo.body).foregroundStyle(.secondary)
                        .padding(16).frame(maxWidth: 280)
                        .presentationCompactAdaptation(.popover)
                }
            }
            Text("Enter the access code from your administrator").font(Typo.meta).foregroundStyle(.secondary)

            SecureField("Access code", text: $apiKey)
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

            Button { dismiss() } label: {
                Text("Back").font(Typo.meta).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Step 2: Identity

    private var identityStep: some View {
        VStack(spacing: 20) {
            Text("Your identity").font(Typo.context)
            Text("This appears on compliance reports and verification records").font(Typo.meta).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 48)

            VStack(spacing: 12) {
                TextField("First name", text: $firstName)
                    .textContentType(.givenName).font(Typo.body).multilineTextAlignment(.center)
                    .padding(16)
                    .background(Color.surfaceMuted)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                TextField("Last name", text: $lastName)
                    .textContentType(.familyName).font(Typo.body).multilineTextAlignment(.center)
                    .padding(16)
                    .background(Color.surfaceMuted)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 48)

            Button { withAnimation { step = 3 } } label: {
                Text("Continue")
            }
            .buttonStyle(PrimaryButtonStyle(isEnabled: nameValid))
            .disabled(!nameValid)
            .padding(.horizontal, 48)

            Button { withAnimation { step = 1 } } label: {
                Text("Back").font(Typo.meta).foregroundStyle(.secondary)
            }
        }
    }

    private var nameValid: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !lastName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Step 3: Role (Optional)

    private var roleStep: some View {
        VStack(spacing: 20) {
            Text("Your role").font(Typo.context)
            Text("Optional — helps identify you in shared reports").font(Typo.meta).foregroundStyle(.secondary)

            ScrollView {
                VStack(spacing: 16) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(AgentRole.allCases) { role in
                            Button {
                                withAnimation(.spring(response: 0.2)) {
                                    selectedRole = selectedRole == role ? nil : role
                                }
                            } label: {
                                RoleChip(title: role == .other ? "Other" : role.shortTitle, isSelected: selectedRole == role)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if selectedRole == .other {
                        TextField("Your role title", text: $customRoleTitle)
                            .font(Typo.body).multilineTextAlignment(.center)
                            .padding(16)
                            .background(Color.surfaceMuted)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .transition(.opacity)
                    }

                    TextField("Organization name", text: $companyName)
                        .textContentType(.organizationName)
                        .font(Typo.body).multilineTextAlignment(.center)
                        .padding(16)
                        .background(Color.surfaceMuted)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .frame(maxHeight: 280)
            .padding(.horizontal, 48)

            Button { withAnimation { step = 4 } } label: {
                Text("Continue")
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 48)

            Button { withAnimation { step = 4 } } label: {
                Text("Skip").font(Typo.meta).foregroundStyle(.secondary)
            }

            Button { withAnimation { step = 2 } } label: {
                Text("Back").font(Typo.meta).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Step 4: Confirmation

    private var confirmStep: some View {
        VStack(spacing: 16) {
            // Initials circle
            let initials = "\(firstName.prefix(1).uppercased())\(lastName.prefix(1).uppercased())"
            Circle().fill(Color.surfaceMuted).frame(width: 72, height: 72)
                .overlay { Text(initials).font(.system(size: 28, weight: .semibold)).foregroundStyle(.secondary) }

            Text("\(firstName.trimmingCharacters(in: .whitespaces)) \(lastName.trimmingCharacters(in: .whitespaces))")
                .font(Typo.context)

            if let roleOrg = previewRoleAndOrg {
                Text(roleOrg).font(Typo.meta).foregroundStyle(.secondary)
            }

            let previewId = AgentProfile.generateAgentId(
                firstName: firstName.trimmingCharacters(in: .whitespaces),
                lastName: lastName.trimmingCharacters(in: .whitespaces),
                company: companyName.isEmpty ? nil : companyName,
                createdAt: Date()
            )
            Text(previewId).font(.system(size: 11, design: .monospaced)).foregroundStyle(.quaternary)

            Spacer().frame(height: 16)

            Button { completeSetup() } label: {
                Text("Start Verifying")
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 48)

            Button { withAnimation { step = 3 } } label: {
                Text("Back").font(Typo.meta).foregroundStyle(.secondary)
            }
        }
    }

    private var previewRoleAndOrg: String? {
        var parts: [String] = []
        if let role = selectedRole {
            if role == .other, !customRoleTitle.isEmpty {
                parts.append(customRoleTitle)
            } else if role != .other {
                parts.append(role.rawValue)
            }
        }
        let co = companyName.trimmingCharacters(in: .whitespaces)
        if !co.isEmpty { parts.append(co) }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " — ")
    }

    // MARK: - Actions

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

    private func completeSetup() {
        let first = firstName.trimmingCharacters(in: .whitespaces)
        let last = lastName.trimmingCharacters(in: .whitespaces)
        let co = companyName.trimmingCharacters(in: .whitespaces)
        let now = Date()

        let profile = AgentProfile(
            firstName: first,
            lastName: last,
            agentId: AgentProfile.generateAgentId(firstName: first, lastName: last, company: co.isEmpty ? nil : co, createdAt: now),
            companyName: co.isEmpty ? nil : co,
            role: selectedRole,
            customRoleTitle: selectedRole == .other ? customRoleTitle.trimmingCharacters(in: .whitespaces) : nil,
            createdAt: now,
            updatedAt: now
        )
        profile.save()
        appState.didConfigure()
    }
}

// MARK: - Settings Sheet (Identity / Connections / Appearance / Data)

struct SettingsSheet: View {
    @ObservedObject var vm: KYCViewModel
    var appState: AppState
    @Environment(\.dismiss) private var dismiss

    // Identity
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var selectedRole: AgentRole?
    @State private var customRoleTitle = ""
    @State private var companyName = ""
    @State private var jurisdiction = ""
    @State private var licenseNumber = ""
    @State private var contactEmail = ""
    @State private var profileImageData: Data?

    // Connections
    @State private var apiKey = ""
    @State private var claudeKey = ""
    @State private var workflowID = ""
    @State private var claudeKeyStatus: ClaudeKeyStatus = .untested
    enum ClaudeKeyStatus { case untested, testing, valid, invalid(String) }

    // UI
    @State private var showReset = false
    @State private var showImportBackup = false
    @State private var shareURL: IdentifiableURL?
    @State private var showRolePicker = false
    @State private var showPhotoPicker = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var colorSchemePreference = UserDefaults.standard.integer(forKey: "colorSchemePreference")
    @State private var backupMessage = ""
    @State private var copiedId = false

    private var profile: AgentProfile? { AgentProfile.current }

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

    private var displayName: String {
        let full = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        return full.isEmpty ? "Agent" : full
    }

    private var initials: String {
        let f = firstName.trimmingCharacters(in: .whitespaces).prefix(1).uppercased()
        let l = lastName.trimmingCharacters(in: .whitespaces).prefix(1).uppercased()
        let result = "\(f)\(l)"
        return result.isEmpty ? "A" : result
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Profile header
                    VStack(spacing: 8) {
                        // Avatar
                        if let data = profileImageData, let uiImage = UIImage(data: data) {
                            Image(uiImage: uiImage)
                                .resizable().scaledToFill()
                                .frame(width: 72, height: 72)
                                .clipShape(Circle())
                        } else {
                            Circle().fill(Color.surfaceMuted).frame(width: 72, height: 72)
                                .overlay { Text(initials).font(.system(size: 28, weight: .semibold)).foregroundStyle(.secondary) }
                        }

                        Text(displayName).font(Typo.context)

                        // Role + Org
                        if let roleOrg = currentRoleAndOrg {
                            Text(roleOrg).font(Typo.meta).foregroundStyle(.secondary)
                        }

                        // Agent ID (tap to copy)
                        if let id = profile?.agentId {
                            Button {
                                UIPasteboard.general.string = id
                                withAnimation { copiedId = true }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    withAnimation { copiedId = false }
                                }
                            } label: {
                                Text(copiedId ? "Copied" : id)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.quaternary)
                            }
                        }

                        Text(statsLine).font(Typo.meta).foregroundStyle(.secondary)
                    }
                    .padding(.top, 24).padding(.bottom, 20)

                    // MARK: Identity
                    settingsSection("Identity") {
                        settingsRow(icon: "person", label: "First Name") {
                            TextField("First name", text: $firstName)
                                .textContentType(.givenName)
                                .font(Typo.body).multilineTextAlignment(.trailing)
                        }
                        Divider().padding(.leading, 44)
                        settingsRow(icon: "person", label: "Last Name") {
                            TextField("Last name", text: $lastName)
                                .textContentType(.familyName)
                                .font(Typo.body).multilineTextAlignment(.trailing)
                        }
                        Divider().padding(.leading, 44)
                        Button { showRolePicker = true } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "briefcase").font(.system(size: 15)).foregroundStyle(.secondary).frame(width: 24)
                                Text("Role").font(Typo.body).foregroundStyle(.secondary)
                                Spacer()
                                Text(currentRoleDisplay).font(Typo.body).foregroundStyle(.primary)
                                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.quaternary)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 12)
                        }
                        Divider().padding(.leading, 44)
                        settingsRow(icon: "building.2", label: "Organization") {
                            TextField("Company name", text: $companyName)
                                .textContentType(.organizationName)
                                .font(Typo.body).multilineTextAlignment(.trailing)
                        }
                        Divider().padding(.leading, 44)
                        settingsRow(icon: "flag", label: "Jurisdiction") {
                            TextField("Country / flag state", text: $jurisdiction)
                                .font(Typo.body).multilineTextAlignment(.trailing)
                        }
                        Divider().padding(.leading, 44)
                        settingsRow(icon: "number", label: "License No.") {
                            TextField("Professional credential", text: $licenseNumber)
                                .font(Typo.body).multilineTextAlignment(.trailing)
                        }
                        Divider().padding(.leading, 44)
                        settingsRow(icon: "envelope", label: "Email") {
                            TextField("Contact email", text: $contactEmail)
                                .textContentType(.emailAddress).keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .font(Typo.body).multilineTextAlignment(.trailing)
                        }
                        Divider().padding(.leading, 44)
                        // Profile photo
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            HStack(spacing: 12) {
                                Image(systemName: "camera").font(.system(size: 15)).foregroundStyle(.secondary).frame(width: 24)
                                Text("Profile Photo").font(Typo.body).foregroundStyle(.secondary)
                                Spacer()
                                if profileImageData != nil {
                                    Text("Set").font(Typo.body).foregroundStyle(.primary)
                                }
                                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.quaternary)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 12)
                        }
                        .onChange(of: selectedPhoto) { _, item in
                            Task { await loadPhoto(item) }
                        }
                    }

                    // MARK: Connections
                    settingsSection("Connections") {
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
                        if !claudeKey.trimmingCharacters(in: .whitespaces).isEmpty {
                            Button {
                                // Save key first, then validate
                                let k = claudeKey.trimmingCharacters(in: .whitespaces)
                                KeychainService.save(k, for: .claudeAPIKey)
                                claudeKeyStatus = .testing
                                Task {
                                    let result = await ClaudeService.shared.validateAPIKey()
                                    await MainActor.run {
                                        claudeKeyStatus = result.valid ? .valid : .invalid(result.error ?? "Unknown error")
                                    }
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    switch claudeKeyStatus {
                                    case .untested:
                                        Image(systemName: "checkmark.circle").font(Typo.meta).foregroundStyle(.secondary)
                                        Text("Test Connection").font(Typo.meta).foregroundStyle(.secondary)
                                    case .testing:
                                        ProgressView().controlSize(.small)
                                        Text("Testing...").font(Typo.meta).foregroundStyle(.secondary)
                                    case .valid:
                                        Image(systemName: "checkmark.circle.fill").font(Typo.meta).foregroundStyle(Color.clear_)
                                        Text("Connected").font(Typo.meta).foregroundStyle(Color.clear_)
                                    case .invalid(let err):
                                        Image(systemName: "xmark.circle.fill").font(Typo.meta).foregroundStyle(Color.flagged)
                                        Text(err).font(Typo.meta).foregroundStyle(Color.flagged)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 16).padding(.vertical, 8)
                            }
                        }
                        Divider().padding(.leading, 44)
                        settingsRow(icon: "link", label: "Workflow ID") {
                            TextField("For invitations", text: $workflowID)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .font(Typo.body).multilineTextAlignment(.trailing)
                        }
                    }

                    // MARK: Appearance
                    settingsSection("Appearance") {
                        HStack(spacing: 12) {
                            Image(systemName: "circle.lefthalf.filled").font(.system(size: 15)).foregroundStyle(.secondary).frame(width: 24)
                            Text("Theme").font(Typo.body).foregroundStyle(.secondary)
                            Spacer()
                            Picker("", selection: $colorSchemePreference) {
                                Text("System").tag(0)
                                Text("Light").tag(1)
                                Text("Dark").tag(2)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 180)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .onChange(of: colorSchemePreference) { _, val in
                            UserDefaults.standard.set(val, forKey: "colorSchemePreference")
                        }

                        if BiometricService.isAvailable {
                            Divider().padding(.leading, 44)
                            HStack(spacing: 12) {
                                Image(systemName: BiometricService.biometricIcon).font(.system(size: 15)).foregroundStyle(.secondary).frame(width: 24)
                                Text(L10n.Biometric.lockWith(BiometricService.biometricName)).font(Typo.body).foregroundStyle(.secondary)
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { BiometricService.isEnabled },
                                    set: { newVal in
                                        BiometricService.isEnabled = newVal
                                        Haptics.light()
                                    }
                                ))
                                .labelsHidden()
                            }
                            .padding(.horizontal, 16).padding(.vertical, 12)
                        }
                    }

                    // MARK: Data
                    settingsSection("Data") {
                        NavigationLink {
                            TransferHistoryView(vm: vm)
                        } label: {
                            settingsActionRow(icon: "arrow.left.arrow.right", label: "Transfer History", detail: "\(vm.transferLog.count) transfer\(vm.transferLog.count == 1 ? "" : "s")")
                        }
                        Divider().padding(.leading, 44)
                        Button {
                            if let url = vm.exportBackup() {
                                shareURL = IdentifiableURL(url: url)
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

                    // MARK: Privacy & Compliance
                    settingsSection("Privacy & Compliance") {
                        NavigationLink {
                            RetentionSettingsView(vm: vm)
                        } label: {
                            settingsActionRow(icon: "clock.badge.checkmark", label: "Data Retention", detail: "\(vm.retentionPolicy.retentionYears) year\(vm.retentionPolicy.retentionYears == 1 ? "" : "s")")
                        }
                        Divider().padding(.leading, 44)
                        NavigationLink {
                            DSARView(vm: vm)
                        } label: {
                            settingsActionRow(icon: "person.text.rectangle", label: "Subject Data Request", detail: "DSAR export")
                        }
                        Divider().padding(.leading, 44)
                        NavigationLink {
                            AuditLogView(vm: vm)
                        } label: {
                            settingsActionRow(icon: "list.clipboard", label: "Audit Log", detail: "\(vm.auditLog.count) event\(vm.auditLog.count == 1 ? "" : "s")")
                        }
                        if !vm.retentionFlaggedChecks.isEmpty {
                            Divider().padding(.leading, 44)
                            HStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle").font(.system(size: 15)).foregroundStyle(Color.review).frame(width: 24)
                                Text("\(vm.retentionFlaggedChecks.count) record\(vm.retentionFlaggedChecks.count == 1 ? "" : "s") past retention period")
                                    .font(Typo.meta).foregroundStyle(Color.review)
                                Spacer()
                            }
                            .padding(.horizontal, 16).padding(.vertical, 10)
                        }
                    }

                    // MARK: API & Demo
                    settingsSection("API Usage") {
                        NavigationLink {
                            APIUsageView()
                        } label: {
                            let usage = APIUsageTracker.totalLast30Days()
                            settingsActionRow(icon: "chart.bar", label: "API Dashboard", detail: "\(usage.calls) calls / $\(String(format: "%.2f", usage.cost))")
                        }
                        Divider().padding(.leading, 44)
                        HStack(spacing: 12) {
                            Image(systemName: "play.rectangle").font(.system(size: 15)).foregroundStyle(.secondary).frame(width: 24)
                            Text("Demo Mode").font(Typo.body).foregroundStyle(.secondary)
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { DemoMode.isEnabled },
                                set: { newVal in
                                    DemoMode.isEnabled = newVal
                                    if newVal { DemoMode.populateDemoData(vm: vm) }
                                    else { DemoMode.clearDemoData(vm: vm) }
                                    Haptics.light()
                                }
                            ))
                            .labelsHidden()
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        if DemoMode.isEnabled {
                            HStack(spacing: 12) {
                                Spacer().frame(width: 24)
                                Text("Using fake data — no API calls made").font(Typo.meta).foregroundStyle(Color.review)
                                Spacer()
                            }
                            .padding(.horizontal, 16).padding(.bottom, 8)
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
            .onAppear { loadProfile() }
            .alert("Reset Everything", isPresented: $showReset) {
                Button("Cancel", role: .cancel) {}
                Button("Delete All", role: .destructive) { vm.resetAll(); AgentProfile.delete(); dismiss(); appState.didReset() }
            } message: { Text("This permanently deletes all checks, vessels, documents, images, and reports.") }
            .sheet(item: $shareURL) { item in
                ActivityView(items: [item.url])
            }
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
            .sheet(isPresented: $showRolePicker) { rolePickerSheet }
            .alert("Backup", isPresented: .constant(!backupMessage.isEmpty)) {
                Button("OK") { backupMessage = "" }
            } message: {
                Text(backupMessage)
            }
        }
    }

    // MARK: - Role Picker Sheet

    private var rolePickerSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(AgentRole.allCases) { role in
                            Button {
                                withAnimation(.spring(response: 0.2)) {
                                    selectedRole = selectedRole == role ? nil : role
                                }
                            } label: {
                                RoleChip(title: role == .other ? "Other" : role.shortTitle, isSelected: selectedRole == role)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if selectedRole == .other {
                        TextField("Your role title", text: $customRoleTitle)
                            .font(Typo.body).multilineTextAlignment(.center)
                            .padding(16)
                            .background(Color.surfaceMuted)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .transition(.opacity)
                    }
                }
                .padding(20)
            }
            .background(Color.surface.ignoresSafeArea())
            .navigationTitle("Your Role")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { showRolePicker = false } }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Helpers

    private var currentRoleDisplay: String {
        guard let role = selectedRole else { return "Not set" }
        if role == .other { return customRoleTitle.isEmpty ? "Other" : customRoleTitle }
        return role.shortTitle
    }

    private var currentRoleAndOrg: String? {
        var parts: [String] = []
        if let role = selectedRole {
            if role == .other, !customRoleTitle.isEmpty {
                parts.append(customRoleTitle)
            } else if role != .other {
                parts.append(role.rawValue)
            }
        }
        let co = companyName.trimmingCharacters(in: .whitespaces)
        if !co.isEmpty { parts.append(co) }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " — ")
    }

    private func loadProfile() {
        apiKey = KeychainService.get(.diditAPIKey) ?? ""
        claudeKey = KeychainService.get(.claudeAPIKey) ?? ""
        workflowID = KeychainService.get(.workflowID) ?? ""

        if let p = AgentProfile.current {
            firstName = p.firstName
            lastName = p.lastName
            selectedRole = p.role
            customRoleTitle = p.customRoleTitle ?? ""
            companyName = p.companyName ?? ""
            jurisdiction = p.jurisdiction ?? ""
            licenseNumber = p.licenseNumber ?? ""
            contactEmail = p.contactEmail ?? ""
            profileImageData = p.profileImageData
        } else {
            // Legacy fallback
            let name = UserDefaults.standard.string(forKey: "agentName") ?? ""
            let parts = name.split(separator: " ", maxSplits: 1)
            firstName = String(parts.first ?? "")
            lastName = parts.count > 1 ? String(parts.last ?? "") : ""
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        guard let image = UIImage(data: data) else { return }
        // Resize to 200x200
        let size = CGSize(width: 200, height: 200)
        let renderer = UIGraphicsImageRenderer(size: size)
        let resized = renderer.jpegData(withCompressionQuality: 0.7) { ctx in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        await MainActor.run { profileImageData = resized }
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
        // Keychain
        let k = apiKey.trimmingCharacters(in: .whitespaces)
        if !k.isEmpty { KeychainService.save(k, for: .diditAPIKey) }
        let c = claudeKey.trimmingCharacters(in: .whitespaces)
        if !c.isEmpty { KeychainService.save(c, for: .claudeAPIKey) } else { KeychainService.delete(.claudeAPIKey) }
        let w = workflowID.trimmingCharacters(in: .whitespaces)
        if !w.isEmpty { KeychainService.save(w, for: .workflowID) } else { KeychainService.delete(.workflowID) }

        // Profile
        let first = firstName.trimmingCharacters(in: .whitespaces)
        let last = lastName.trimmingCharacters(in: .whitespaces)
        let co = companyName.trimmingCharacters(in: .whitespaces)

        if let existing = AgentProfile.current {
            var updated = existing
            updated.firstName = first
            updated.lastName = last
            updated.role = selectedRole
            updated.customRoleTitle = selectedRole == .other ? customRoleTitle.trimmingCharacters(in: .whitespaces) : nil
            updated.companyName = co.isEmpty ? nil : co
            updated.jurisdiction = jurisdiction.trimmingCharacters(in: .whitespaces).isEmpty ? nil : jurisdiction.trimmingCharacters(in: .whitespaces)
            updated.licenseNumber = licenseNumber.trimmingCharacters(in: .whitespaces).isEmpty ? nil : licenseNumber.trimmingCharacters(in: .whitespaces)
            updated.contactEmail = contactEmail.trimmingCharacters(in: .whitespaces).isEmpty ? nil : contactEmail.trimmingCharacters(in: .whitespaces)
            updated.profileImageData = profileImageData
            updated.updatedAt = Date()
            updated.save()
        } else if !first.isEmpty {
            // Create new profile from settings (edge case: legacy user without profile)
            let now = Date()
            let profile = AgentProfile(
                firstName: first,
                lastName: last,
                agentId: AgentProfile.generateAgentId(firstName: first, lastName: last, company: co.isEmpty ? nil : co, createdAt: now),
                companyName: co.isEmpty ? nil : co,
                role: selectedRole,
                customRoleTitle: selectedRole == .other ? customRoleTitle.trimmingCharacters(in: .whitespaces) : nil,
                jurisdiction: jurisdiction.trimmingCharacters(in: .whitespaces).isEmpty ? nil : jurisdiction.trimmingCharacters(in: .whitespaces),
                licenseNumber: licenseNumber.trimmingCharacters(in: .whitespaces).isEmpty ? nil : licenseNumber.trimmingCharacters(in: .whitespaces),
                contactEmail: contactEmail.trimmingCharacters(in: .whitespaces).isEmpty ? nil : contactEmail.trimmingCharacters(in: .whitespaces),
                profileImageData: profileImageData,
                createdAt: now,
                updatedAt: now
            )
            profile.save()
        }
    }
}

// MARK: - Backup Import Picker

// MARK: - Identifiable URL Wrapper

struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - Share File Sheet (robust file sharing)

struct ShareFileSheet: View {
    let url: URL
    var onDismiss: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()

                // File info
                Image(systemName: "doc.zipper").font(.system(size: 48)).foregroundStyle(.quaternary)
                Text(url.lastPathComponent).font(Typo.body).fontWeight(.medium)

                let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
                if size > 0 {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                        .font(Typo.meta).foregroundStyle(.secondary)
                }

                Spacer()

                // Share button triggers native share sheet
                ShareLink(item: url) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share Backup")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 48)

                Button("Done") { onDismiss?(); dismiss() }
                    .font(Typo.meta).foregroundStyle(.secondary)
                    .padding(.bottom, 20)
            }
            .background(Color.surface.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { Text("Export Backup").font(Typo.body).fontWeight(.semibold) }
            }
        }
    }
}

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
