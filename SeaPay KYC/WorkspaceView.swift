//
//  WorkspaceView.swift
//  OceanCheck
//
//  Multi-agent workspace: create/join, see collaborators, sync data, activity feed.
//

import SwiftUI

struct WorkspaceView: View {
    @ObservedObject var vm: KYCViewModel
    @State private var isConnected = false
    @State private var workspaceDetail: WorkspaceDetail?
    @State private var activity: [ActivityEvent] = []
    @State private var syncStatus: SyncStatus?
    @State private var error: String?
    @State private var isSyncing = false
    @State private var showCreate = false
    @State private var showJoin = false

    var body: some View {
        Group {
            if isConnected {
                connectedView
            } else {
                disconnectedView
            }
        }
        .navigationTitle("Workspace")
        .navigationBarTitleDisplayMode(.inline)
        .task { await checkConnection() }
        .sheet(isPresented: $showCreate) { CreateWorkspaceSheet(vm: vm, onCreated: { await refresh() }) }
        .sheet(isPresented: $showJoin) { JoinWorkspaceSheet(vm: vm, onJoined: { await refresh() }) }
    }

    // MARK: - Disconnected

    private var disconnectedView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "person.3").font(.system(size: 48)).foregroundStyle(.quaternary)
            VStack(spacing: 6) {
                Text("Multi-Agent Workspace").font(Typo.context).fontWeight(.semibold)
                Text("Collaborate with other compliance officers on the same vessels in real time.")
                    .font(Typo.meta).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 40)
            }
            Spacer()
            Button { showCreate = true } label: { Text("Create Workspace") }.buttonStyle(PrimaryButtonStyle()).padding(.horizontal, 48)
            Button { showJoin = true } label: { Text("Join with Code").font(Typo.body).foregroundStyle(.secondary) }
            Spacer().frame(height: 40)
        }
        .background(Color.surface.ignoresSafeArea())
    }

    // MARK: - Connected

    private var connectedView: some View {
        List {
            // Workspace header
            if let ws = workspaceDetail?.workspace {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(ws.name).font(.system(size: 18, weight: .bold))
                        HStack(spacing: 8) {
                            Label(ws.code, systemImage: "number").font(.system(size: 13, design: .monospaced)).foregroundStyle(.secondary)
                            Spacer()
                            if let status = syncStatus {
                                Text("\(status.activeAgents) online").font(Typo.meta).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Sync status
                Section("Sync") {
                    if let status = syncStatus {
                        HStack {
                            Image(systemName: status.hasUpdates ? "arrow.down.circle.fill" : "checkmark.circle.fill")
                                .foregroundStyle(status.hasUpdates ? Color.review : Color.clear_)
                            Text(status.hasUpdates ? "\(status.updatesAvailable) update\(status.updatesAvailable == 1 ? "" : "s") available" : "Up to date")
                                .font(Typo.body)
                            Spacer()
                            Text("v\(status.latestVersion)").font(Typo.meta).foregroundStyle(.quaternary)
                        }
                    }

                    Button {
                        Task { await pushData() }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.up.circle").foregroundStyle(.secondary)
                            Text("Push Changes").font(Typo.body)
                            Spacer()
                            if isSyncing { ProgressView().controlSize(.mini) }
                        }
                    }
                    .disabled(isSyncing)

                    Button {
                        Task { await pullData() }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.down.circle").foregroundStyle(.secondary)
                            Text("Pull Latest").font(Typo.body)
                            Spacer()
                        }
                    }
                    .disabled(isSyncing)
                }
            }

            // Agents
            if let agents = workspaceDetail?.agents {
                Section("Collaborators (\(agents.filter(\.isActive).count))") {
                    ForEach(agents.filter(\.isActive)) { agent in
                        HStack(spacing: 12) {
                            Circle().fill(Color.surfaceMuted).frame(width: 36, height: 36)
                                .overlay {
                                    Text(String(agent.agentName.prefix(1)).uppercased())
                                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(.secondary)
                                }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(agent.agentName).font(Typo.body).fontWeight(.medium)
                                if !agent.agentOrg.isEmpty { Text(agent.agentOrg).font(Typo.meta).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            if let sync = agent.lastSync {
                                Text(sync.prefix(10)).font(Typo.meta).foregroundStyle(.quaternary)
                            }
                        }
                    }
                }
            }

            // Activity
            if !activity.isEmpty {
                Section("Recent Activity") {
                    ForEach(activity.prefix(15)) { event in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: activityIcon(event.action)).font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(event.agentName) \(event.action.replacingOccurrences(of: "_", with: " "))").font(Typo.body).lineLimit(1)
                                if !event.entityName.isEmpty { Text(event.entityName).font(Typo.meta).foregroundStyle(.secondary) }
                                Text(event.createdAt.prefix(16).replacingOccurrences(of: "T", with: " ")).font(.system(size: 10)).foregroundStyle(.quaternary)
                            }
                        }
                    }
                }
            }

            // Error
            if let error {
                Section {
                    Text(error).font(Typo.meta).foregroundStyle(Color.flagged)
                }
            }

            // Leave
            Section {
                Button(role: .destructive) {
                    Task {
                        try? await CollaborationService.shared.leaveWorkspace()
                        await checkConnection()
                    }
                } label: {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right").foregroundStyle(Color.flagged)
                        Text("Leave Workspace").foregroundStyle(Color.flagged)
                    }
                }
            }
        }
        .refreshable { await refresh() }
    }

    // MARK: - Actions

    private func checkConnection() async {
        let collab = CollaborationService.shared
        isConnected = collab.isConnected
        if isConnected { await refresh() }
    }

    private func refresh() async {
        isConnected = CollaborationService.shared.isConnected
        guard isConnected else { return }
        do {
            async let detail = CollaborationService.shared.getWorkspaceInfo()
            async let status = CollaborationService.shared.checkForUpdates()
            async let feed = CollaborationService.shared.getActivity()
            workspaceDetail = try await detail
            syncStatus = try await status
            activity = try await feed
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func pushData() async {
        isSyncing = true
        defer { isSyncing = false }
        do {
            _ = try await CollaborationService.shared.pushData(vessels: vm.vessels, checks: vm.checks)
            Haptics.success()
            await refresh()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func pullData() async {
        isSyncing = true
        defer { isSyncing = false }
        do {
            if let snapshot = try await CollaborationService.shared.pullLatest() {
                // Merge pulled data
                if let vessels = snapshot.vessels {
                    for vessel in vessels {
                        if !vm.vessels.contains(where: { $0.id == vessel.id }) {
                            vm.vessels.append(vessel)
                        }
                    }
                    vm.saveVessels()
                }
                if let checks = snapshot.checks {
                    for check in checks {
                        if !vm.checks.contains(where: { $0.id == check.id }) {
                            vm.checks.append(check)
                        }
                    }
                    vm.saveChecks()
                }
                Haptics.success()
            }
            await refresh()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func activityIcon(_ action: String) -> String {
        switch action {
        case "workspace_created": return "plus.circle"
        case "agent_joined": return "person.badge.plus"
        case "agent_left": return "person.badge.minus"
        case "data_synced": return "arrow.triangle.2.circlepath"
        default: return "circle"
        }
    }
}

// MARK: - Create Workspace Sheet

struct CreateWorkspaceSheet: View {
    @ObservedObject var vm: KYCViewModel
    var onCreated: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var isCreating = false
    @State private var result: WorkspaceInfo?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let result {
                    // Success
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "checkmark.circle").font(.system(size: 48)).foregroundStyle(Color.clear_)
                        Text("Workspace Created").font(Typo.context)
                        VStack(spacing: 8) {
                            Text("Share this code with collaborators:").font(Typo.meta).foregroundStyle(.secondary)
                            Text(result.code).font(.system(size: 32, weight: .bold, design: .monospaced)).kerning(4)
                        }
                        .padding(.top, 8)
                        Button {
                            UIPasteboard.general.string = result.code
                            Haptics.light()
                        } label: {
                            Label("Copy Code", systemImage: "doc.on.doc").font(Typo.body)
                        }
                        Spacer()
                        Button { dismiss() } label: { Text("Done") }.buttonStyle(PrimaryButtonStyle()).padding(.horizontal, 48)
                        Spacer().frame(height: 20)
                    }
                } else {
                    // Form
                    Spacer()
                    Image(systemName: "person.3").font(.system(size: 44)).foregroundStyle(.quaternary)
                    Text("Create a Workspace").font(Typo.context)
                    Text("Other agents can join using a code.").font(Typo.meta).foregroundStyle(.secondary)
                    TextField("Workspace name (e.g. vessel name)", text: $name)
                        .font(Typo.body).textFieldStyle(.roundedBorder).padding(.horizontal, 32)
                    if let error { Text(error).font(Typo.meta).foregroundStyle(Color.flagged) }
                    Spacer()
                    Button {
                        Task { await create() }
                    } label: { Text(isCreating ? "Creating..." : "Create") }
                        .buttonStyle(PrimaryButtonStyle(isEnabled: !name.trimmingCharacters(in: .whitespaces).isEmpty && !isCreating))
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
                        .padding(.horizontal, 48)
                    Spacer().frame(height: 20)
                }
            }
            .background(Color.surface.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if result == nil { Button("Cancel") { dismiss() } }
                }
            }
        }
    }

    private func create() async {
        isCreating = true; error = nil
        do {
            result = try await CollaborationService.shared.createWorkspace(name: name.trimmingCharacters(in: .whitespaces))
            await onCreated()
            Haptics.success()
        } catch {
            self.error = error.localizedDescription
        }
        isCreating = false
    }
}

// MARK: - Join Workspace Sheet

struct JoinWorkspaceSheet: View {
    @ObservedObject var vm: KYCViewModel
    var onJoined: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var isJoining = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "link.badge.plus").font(.system(size: 44)).foregroundStyle(.quaternary)
                Text("Join a Workspace").font(Typo.context)
                Text("Enter the code shared by another agent.").font(Typo.meta).foregroundStyle(.secondary)
                TextField("Workspace code", text: $code)
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 48)
                if let error { Text(error).font(Typo.meta).foregroundStyle(Color.flagged) }
                Spacer()
                Button {
                    Task { await join() }
                } label: { Text(isJoining ? "Joining..." : "Join") }
                    .buttonStyle(PrimaryButtonStyle(isEnabled: code.count >= 6 && !isJoining))
                    .disabled(code.count < 6 || isJoining)
                    .padding(.horizontal, 48)
                Spacer().frame(height: 20)
            }
            .background(Color.surface.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private func join() async {
        isJoining = true; error = nil
        do {
            _ = try await CollaborationService.shared.joinWorkspace(code: code)
            await onJoined()
            Haptics.success()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isJoining = false
    }
}
