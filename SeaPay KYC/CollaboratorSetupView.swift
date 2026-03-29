//
//  CollaboratorSetupView.swift
//  OceanCheck
//
//  Lightweight setup for workspace collaborators — no API key needed.
//  Enter workspace code → name → role → join → Fleet tab.
//

import SwiftUI

struct CollaboratorSetupView: View {
    @ObservedObject var vm: KYCViewModel
    var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var step = 0  // 0=code, 1=identity, 2=joining
    @State private var code = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var selectedRole: AppRole?
    @State private var customRoleTitle = ""
    @State private var companyName = ""
    @State private var error: String?
    @State private var isJoining = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Step indicator
                HStack(spacing: 8) {
                    ForEach(0..<2, id: \.self) { i in
                        Capsule().fill(i <= step ? Color.primary : Color.primary.opacity(0.15))
                            .frame(height: 3)
                    }
                }
                .padding(.horizontal, 32).padding(.top, 12)

                ScrollView {
                    VStack(spacing: 24) {
                        Spacer(minLength: 20)

                        if step == 0 {
                            codeStep
                        } else {
                            identityStep
                        }

                        if let error {
                            Text(error).font(Typo.meta).foregroundStyle(Color.flagged)
                                .padding(.horizontal, 32)
                        }

                        Spacer(minLength: 20)
                    }
                }

                // Action button
                VStack(spacing: 12) {
                    if step == 0 {
                        Button { withAnimation { step = 1 } } label: { Text("Next") }
                            .buttonStyle(PrimaryButtonStyle(isEnabled: code.count >= 6))
                            .disabled(code.count < 6)
                    } else {
                        Button { Task { await joinWorkspace() } } label: { Text(isJoining ? "Joining..." : "Join Workspace") }
                            .buttonStyle(PrimaryButtonStyle(isEnabled: !firstName.trimmingCharacters(in: .whitespaces).isEmpty && !lastName.trimmingCharacters(in: .whitespaces).isEmpty && !isJoining))
                            .disabled(firstName.trimmingCharacters(in: .whitespaces).isEmpty || lastName.trimmingCharacters(in: .whitespaces).isEmpty || isJoining)
                    }
                }
                .padding(.horizontal, 32).padding(.bottom, 20)
            }
            .background(Color.surface.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: step == 0 ? "xmark" : "chevron.left").foregroundStyle(.secondary)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Step 0: Workspace Code

    private var codeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.3").font(.system(size: 44)).foregroundStyle(.primary.opacity(0.1))
            Text("Join a Workspace").font(BrandFont.brand(22))
            Text("Enter the code shared by the compliance agent who invited you.")
                .font(Typo.meta).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 20)

            TextField("Workspace code", text: $code)
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .padding(.horizontal, 48).padding(.top, 8)
        }
    }

    // MARK: - Step 1: Identity + Role

    private var identityStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.text.rectangle").font(.system(size: 36)).foregroundStyle(.primary.opacity(0.1))
            Text("Your Identity").font(BrandFont.brand(22))
            Text("This appears in the workspace so other agents can identify you.")
                .font(Typo.meta).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 20)

            // Name fields
            VStack(spacing: 12) {
                TextField("First name", text: $firstName)
                    .font(Typo.body).textContentType(.givenName).textFieldStyle(.roundedBorder)
                TextField("Last name", text: $lastName)
                    .font(Typo.body).textContentType(.familyName).textFieldStyle(.roundedBorder)
                TextField("Organization (optional)", text: $companyName)
                    .font(Typo.body).textContentType(.organizationName).textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal, 32)

            // Role picker
            Text("Your role").font(Typo.meta).foregroundStyle(.secondary).padding(.top, 8)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(AppRole.collaboratorRoles) { role in
                    Button {
                        selectedRole = role
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: role.icon).font(.system(size: 11))
                            Text(role.shortTitle).font(.system(size: 12, weight: selectedRole == role ? .semibold : .regular))
                        }
                        .foregroundStyle(selectedRole == role ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(selectedRole == role ? Color.primary.opacity(0.08) : Color.surfaceMuted.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(selectedRole == role ? Color.primary.opacity(0.3) : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 32)

            if selectedRole == .other {
                TextField("Your role title", text: $customRoleTitle)
                    .font(Typo.body).textFieldStyle(.roundedBorder).padding(.horizontal, 32)
            }
        }
    }

    // MARK: - Join

    private func joinWorkspace() async {
        isJoining = true; error = nil

        // Create profile
        let now = Date()
        let profile = AgentProfile(
            firstName: firstName.trimmingCharacters(in: .whitespaces),
            lastName: lastName.trimmingCharacters(in: .whitespaces),
            agentId: AgentProfile.generateAgentId(firstName: firstName, lastName: lastName, company: companyName.isEmpty ? nil : companyName, createdAt: now),
            companyName: companyName.isEmpty ? nil : companyName,
            role: selectedRole,
            customRoleTitle: selectedRole == .other ? customRoleTitle : nil,
            createdAt: now,
            updatedAt: now
        )
        profile.save()

        // Join workspace + auto-pull data
        do {
            _ = try await CollaborationService.shared.joinWorkspace(code: code)
            UserDefaults.standard.set(true, forKey: "isCollaborator")

            // Pull all workspace vessels into local data
            let wsVessels = try await CollaborationService.shared.listWorkspaceVessels()
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            for wv in wsVessels {
                guard let token = CollaborationService.shared.workspace?.token,
                      let url = URL(string: "https://seapay.me/oceancheck/api/sync.php?action=pull&vessel_id=\(wv.vesselId)") else { continue }
                var req = URLRequest(url: url)
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                req.timeoutInterval = 30
                guard let (data, _) = try? await URLSession.shared.data(for: req),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let snap = json["snapshot"] as? [String: Any] else { continue }

                if let vRaw = snap["vessels"], let vData = try? JSONSerialization.data(withJSONObject: vRaw),
                   let vs = try? decoder.decode([Vessel].self, from: vData) {
                    for v in vs { if !vm.vessels.contains(where: { $0.id == v.id }) { vm.vessels.append(v) } }
                }
                if let cRaw = snap["checks"], let cData = try? JSONSerialization.data(withJSONObject: cRaw),
                   let cs = try? decoder.decode([KYCCheck].self, from: cData) {
                    for c in cs { if !vm.checks.contains(where: { $0.id == c.id }) { vm.checks.append(c) } }
                }
                // Download images
                await FilesSyncService.shared.downloadMissingFiles(vesselId: wv.vesselId, vm: vm)
            }
            vm.saveChecks(); vm.saveVessels()

            appState.didConfigure()
            Haptics.success()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }

        isJoining = false
    }
}
