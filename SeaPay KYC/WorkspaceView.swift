//
//  WorkspaceView.swift
//  OceanCheck
//
//  Fleet tab — vessel-based multi-agent collaboration.
//  Shows shared vessels with per-vessel sync, activity feed, and collaborator list.
//

import SwiftUI

// MARK: - Fleet Tab (Third tab in HomeView)

struct FleetTabView: View {
    @ObservedObject var vm: KYCViewModel
    @State private var isConnected = false
    @State private var workspaceDetail: WorkspaceDetail?
    @State private var activity: [ActivityEvent] = []
    @State private var syncStatus: SyncStatus?
    @State private var error: String?
    @State private var showCreate = false
    @State private var showJoin = false
    @State private var syncingVesselId: String?

    var body: some View {
        Group {
            if isConnected {
                connectedView
            } else {
                disconnectedView
            }
        }
        .task { await checkConnection() }
        .sheet(isPresented: $showCreate) { CreateWorkspaceSheet(vm: vm, onCreated: { await refresh() }) }
        .sheet(isPresented: $showJoin) { JoinWorkspaceSheet(vm: vm, onJoined: { await refresh() }) }
    }

    // MARK: - Disconnected

    private var disconnectedView: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 40)
                Image(systemName: "person.3.sequence").font(.system(size: 52)).foregroundStyle(.primary.opacity(0.08))
                VStack(spacing: 8) {
                    Text("Fleet Collaboration").font(BrandFont.brand(24))
                    Text("Work on vessels together with other compliance officers. Create a workspace or join one with a code.")
                        .font(Typo.meta).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 40)
                }
                Spacer(minLength: 20)
                Button { showCreate = true } label: { Text("Create Workspace") }.buttonStyle(PrimaryButtonStyle()).padding(.horizontal, 48)
                Button { showJoin = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "link").font(.system(size: 13))
                        Text("Join with Code")
                    }.font(Typo.body).foregroundStyle(.secondary)
                }
                Spacer(minLength: 40)
            }
        }
        .background(Color.surface.ignoresSafeArea())
    }

    // MARK: - Connected

    private var connectedView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Workspace header
                if let ws = workspaceDetail?.workspace {
                    VStack(spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(ws.name).font(.system(size: 18, weight: .bold))
                                HStack(spacing: 6) {
                                    Text(ws.code).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                                    if let agents = workspaceDetail?.agents {
                                        Text("\u{2022} \(agents.filter(\.active).count) online").font(Typo.meta).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            Spacer()
                            Button {
                                UIPasteboard.general.string = ws.code
                                Haptics.light()
                            } label: {
                                Image(systemName: "doc.on.doc").font(.system(size: 13)).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 20).padding(.top, 16)

                        // Agent avatars row
                        if let agents = workspaceDetail?.agents.filter(\.active), !agents.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: -8) {
                                    ForEach(agents) { agent in
                                        Circle().fill(Color.surfaceMuted).frame(width: 32, height: 32)
                                            .overlay {
                                                Text(String(agent.agentName.prefix(1)).uppercased()).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                                            }
                                            .overlay(Circle().stroke(Color.surface, lineWidth: 2))
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                        }
                    }
                    .padding(.bottom, 12)
                }

                // Vessels
                SectionHeader("Shared Vessels").padding(.horizontal, 20).padding(.top, 8)

                if vm.vessels.isEmpty {
                    VStack(spacing: 12) {
                        Text("No vessels yet").font(Typo.body).foregroundStyle(.secondary)
                        Text("Add a vessel in the Vessels tab, then sync it here.").font(Typo.meta).foregroundStyle(.quaternary)
                    }
                    .padding(.vertical, 24)
                } else {
                    ForEach(vm.vessels) { vessel in
                        vesselSyncCard(vessel)
                    }
                }

                // Activity
                if !activity.isEmpty {
                    SectionHeader("Recent Activity").padding(.horizontal, 20).padding(.top, 16)
                    ForEach(activity.prefix(10)) { event in
                        activityRow(event)
                    }
                }

                // Error
                if let error {
                    Text(error).font(Typo.meta).foregroundStyle(Color.flagged).padding(20)
                }

                // Leave
                Button(role: .destructive) {
                    Task {
                        try? await CollaborationService.shared.leaveWorkspace()
                        await checkConnection()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "rectangle.portrait.and.arrow.right").font(.system(size: 12))
                        Text("Leave Workspace").font(Typo.meta)
                    }.foregroundStyle(Color.flagged)
                }
                .padding(.top, 24).padding(.bottom, 40)
            }
        }
        .background(Color.surface.ignoresSafeArea())
        .refreshable { await refresh() }
    }

    // MARK: - Vessel Sync Card

    private func vesselSyncCard(_ vessel: Vessel) -> some View {
        let crew = vm.checksForVessel(vessel.id)
        let isSyncing = syncingVesselId == vessel.id

        return VStack(spacing: 0) {
            HStack(spacing: 14) {
                // Vessel icon
                Circle().fill(Color.surfaceMuted).frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: vessel.vesselType?.icon ?? "ferry").font(.system(size: 16)).foregroundStyle(.secondary)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(vessel.name).font(Typo.body).fontWeight(.semibold)
                    HStack(spacing: 8) {
                        Text("\(crew.count) crew").font(Typo.meta).foregroundStyle(.secondary)
                        if !vessel.flagState.isEmpty {
                            Text(vessel.flagState).font(Typo.meta).foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                if isSyncing {
                    ProgressView().controlSize(.small)
                } else {
                    HStack(spacing: 12) {
                        Button {
                            Task { await pushVessel(vessel) }
                        } label: {
                            Image(systemName: "arrow.up.circle").font(.system(size: 20)).foregroundStyle(.primary.opacity(0.6))
                        }
                        .accessibilityLabel("Push \(vessel.name)")

                        Button {
                            Task { await pullVessel(vessel) }
                        } label: {
                            Image(systemName: "arrow.down.circle").font(.system(size: 20)).foregroundStyle(.primary.opacity(0.6))
                        }
                        .accessibilityLabel("Pull \(vessel.name)")
                    }
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 14)

            Divider().padding(.leading, 78)
        }
    }

    // MARK: - Activity Row

    private func activityRow(_ event: ActivityEvent) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle().fill(Color.surfaceMuted).frame(width: 28, height: 28)
                .overlay {
                    Text(String(event.agentName.prefix(1)).uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text("\(event.agentName) \(event.action.replacingOccurrences(of: "_", with: " "))").font(Typo.body).lineLimit(1)
                if !event.entityName.isEmpty { Text(event.entityName).font(Typo.meta).foregroundStyle(.secondary) }
            }

            Spacer()

            Text(event.createdAt.suffix(8).prefix(5)).font(Typo.meta).foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 20).padding(.vertical, 8)
    }

    // MARK: - Actions

    private func checkConnection() async {
        isConnected = CollaborationService.shared.isConnected
        if isConnected { await refresh() }
    }

    private func refresh() async {
        isConnected = CollaborationService.shared.isConnected
        guard isConnected else { return }
        do {
            workspaceDetail = try await CollaborationService.shared.getWorkspaceInfo()
            syncStatus = try await CollaborationService.shared.checkForUpdates()
            activity = try await CollaborationService.shared.getActivity()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func pushVessel(_ vessel: Vessel) async {
        syncingVesselId = vessel.id
        defer { syncingVesselId = nil }
        do {
            let checks = vm.checksForVessel(vessel.id)
            _ = try await CollaborationService.shared.pushVessel(vessel: vessel, checks: checks)
            Haptics.success()
            await refresh()
        } catch {
            self.error = "Push failed: \(error.localizedDescription)"
        }
    }

    private func pullVessel(_ vessel: Vessel) async {
        syncingVesselId = vessel.id
        defer { syncingVesselId = nil }
        do {
            if let snapshot = try await CollaborationService.shared.pullVessel(vesselId: vessel.id) {
                if let vessels = snapshot.vessels {
                    for v in vessels where v.id == vessel.id {
                        vm.updateVessel(v)
                    }
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
            self.error = "Pull failed: \(error.localizedDescription)"
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
                    Spacer()
                    Image(systemName: "checkmark.circle").font(.system(size: 48)).foregroundStyle(Color.clear_)
                    Text("Workspace Created").font(Typo.context)
                    VStack(spacing: 8) {
                        Text("Share this code with collaborators:").font(Typo.meta).foregroundStyle(.secondary)
                        Text(result.code).font(.system(size: 32, weight: .bold, design: .monospaced)).kerning(4)
                    }.padding(.top, 8)
                    Button {
                        UIPasteboard.general.string = result.code
                        Haptics.light()
                    } label: { Label("Copy Code", systemImage: "doc.on.doc").font(Typo.body) }
                    Spacer()
                    Button { dismiss() } label: { Text("Done") }.buttonStyle(PrimaryButtonStyle()).padding(.horizontal, 48)
                    Spacer().frame(height: 20)
                } else {
                    Spacer()
                    Image(systemName: "person.3").font(.system(size: 44)).foregroundStyle(.quaternary)
                    Text("Create a Workspace").font(Typo.context)
                    Text("Other agents can join using a code.").font(Typo.meta).foregroundStyle(.secondary)
                    TextField("Workspace name (e.g. fleet name)", text: $name)
                        .font(Typo.body).textFieldStyle(.roundedBorder).padding(.horizontal, 32)
                    if let error { Text(error).font(Typo.meta).foregroundStyle(Color.flagged) }
                    Spacer()
                    Button { Task { await create() } } label: { Text(isCreating ? "Creating..." : "Create") }
                        .buttonStyle(PrimaryButtonStyle(isEnabled: !name.trimmingCharacters(in: .whitespaces).isEmpty && !isCreating))
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
                        .padding(.horizontal, 48)
                    Spacer().frame(height: 20)
                }
            }
            .background(Color.surface.ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .cancellationAction) { if result == nil { Button("Cancel") { dismiss() } } } }
        }
    }

    private func create() async {
        isCreating = true; error = nil
        do {
            result = try await CollaborationService.shared.createWorkspace(name: name.trimmingCharacters(in: .whitespaces))
            await onCreated()
            Haptics.success()
        } catch { self.error = error.localizedDescription }
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
                    .multilineTextAlignment(.center).textInputAutocapitalization(.characters)
                    .autocorrectionDisabled().padding(.horizontal, 48)
                if let error { Text(error).font(Typo.meta).foregroundStyle(Color.flagged) }
                Spacer()
                Button { Task { await join() } } label: { Text(isJoining ? "Joining..." : "Join") }
                    .buttonStyle(PrimaryButtonStyle(isEnabled: code.count >= 6 && !isJoining))
                    .disabled(code.count < 6 || isJoining).padding(.horizontal, 48)
                Spacer().frame(height: 20)
            }
            .background(Color.surface.ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func join() async {
        isJoining = true; error = nil
        do {
            _ = try await CollaborationService.shared.joinWorkspace(code: code)
            await onJoined()
            Haptics.success()
            dismiss()
        } catch { self.error = error.localizedDescription }
        isJoining = false
    }
}
