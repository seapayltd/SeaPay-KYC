//
//  WorkspaceView.swift
//  OceanCheck
//
//  Fleet tab — vessel-selective, role-based collaboration with merge review.
//

import SwiftUI

// MARK: - Fleet Tab

struct FleetTabView: View {
    @ObservedObject var vm: KYCViewModel
    @State private var isConnected = false
    @State private var workspaceDetail: WorkspaceDetail?
    @State private var workspaceVessels: [WorkspaceVessel] = []
    @State private var activity: [ActivityEvent] = []
    @State private var auditTrail: [FleetAuditEvent] = []
    @State private var error: String?
    @State private var showCreate = false
    @State private var showJoin = false
    @State private var showAddVessel = false
    @State private var syncingVesselId: String?
    @State private var mergeDiff: MergeDiff?
    @State private var mergeVesselId: String?
    @State private var mergeRemoteVessel: Vessel?
    @State private var mergeRemoteChecks: [KYCCheck]?
    @State private var downloadURL: IdentifiableURL?
    @State private var showActivity = false
    @State private var isSyncingAll = false
    private var isCollaborator: Bool { UserDefaults.standard.bool(forKey: "isCollaborator") }

    var body: some View {
        Group {
            if isConnected { connectedView } else { disconnectedView }
        }
        .task { await checkConnection() }
        .sheet(isPresented: $showCreate) { CreateWorkspaceSheet(vm: vm, onCreated: { await refresh() }) }
        .sheet(isPresented: $showJoin) { JoinWorkspaceSheet(vm: vm, onJoined: { await refresh() }) }
        .sheet(isPresented: $showAddVessel) { AddVesselToWorkspaceSheet(vm: vm, existingVesselIds: Set(workspaceVessels.map(\.vesselId)), onAdded: { await refresh() }) }
        .sheet(item: $downloadURL) { url in ActivityView(items: [url.url]) }
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
                    HStack(spacing: 8) { Image(systemName: "link").font(.system(size: 13)); Text("Join with Code") }.font(Typo.body).foregroundStyle(.secondary)
                }
                Spacer(minLength: 40)
            }
        }.background(Color.surface.ignoresSafeArea())
    }

    // MARK: - Connected

    private var connectedView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Header
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
                            Button { UIPasteboard.general.string = ws.code; Haptics.light() } label: {
                                Image(systemName: "doc.on.doc").font(.system(size: 13)).foregroundStyle(.secondary)
                            }
                        }.padding(.horizontal, 20).padding(.top, 16)

                        // Agent row
                        if let agents = workspaceDetail?.agents.filter(\.active), !agents.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: -8) {
                                    ForEach(agents) { a in
                                        Circle().fill(Color.surfaceMuted).frame(width: 32, height: 32)
                                            .overlay { Text(String(a.agentName.prefix(1)).uppercased()).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary) }
                                            .overlay(Circle().stroke(Color.surface, lineWidth: 2))
                                    }
                                }.padding(.horizontal, 20)
                            }
                        }
                    }.padding(.bottom, 12)
                }

                // Sync All + Add
                HStack(spacing: 12) {
                    SectionHeader("Shared Vessels")
                    Spacer()
                    if isSyncingAll {
                        ProgressView().controlSize(.mini)
                    } else {
                        Button { Task { await syncAllVessels() } } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 12))
                                Text("Sync").font(Typo.meta)
                            }.foregroundStyle(.primary.opacity(0.6))
                        }
                    }
                    if !isCollaborator {
                        Button { showAddVessel = true } label: {
                            Image(systemName: "plus.circle").font(.system(size: 16)).foregroundStyle(.primary)
                        }
                    }
                }.padding(.horizontal, 20).padding(.top, 8)

                if workspaceVessels.isEmpty {
                    VStack(spacing: 12) {
                        Text("No vessels shared yet").font(Typo.body).foregroundStyle(.secondary)
                        Text(isCollaborator ? "Waiting for the agent to share vessels." : "Tap + to add a vessel to this workspace.")
                            .font(Typo.meta).foregroundStyle(.quaternary)
                    }.padding(.vertical, 24)
                } else {
                    ForEach(workspaceVessels) { wv in
                        let localVessel = vm.vessels.first(where: { $0.id == wv.vesselId })
                        if let lv = localVessel {
                            NavigationLink { VesselDetailView(vm: vm, vessel: lv) } label: {
                                vesselCard(wv)
                            }.buttonStyle(.plain)
                        } else {
                            vesselCard(wv)
                        }
                    }
                }

                // Activity
                Button { withAnimation { showActivity.toggle() } } label: {
                    HStack {
                        SectionHeader("Activity")
                        Spacer()
                        Image(systemName: showActivity ? "chevron.up" : "chevron.down").font(.system(size: 11)).foregroundStyle(.secondary)
                    }.padding(.horizontal, 20).padding(.top, 16)
                }.buttonStyle(.plain)

                if showActivity {
                    ForEach(activity.prefix(15)) { event in
                        activityRow(event)
                    }
                }

                // Error
                if let error { Text(error).font(Typo.meta).foregroundStyle(Color.flagged).padding(20) }

                // Leave
                Button(role: .destructive) {
                    Task { try? await CollaborationService.shared.leaveWorkspace(); await checkConnection() }
                } label: {
                    HStack(spacing: 8) { Image(systemName: "rectangle.portrait.and.arrow.right").font(.system(size: 12)); Text("Leave Workspace").font(Typo.meta) }.foregroundStyle(Color.flagged)
                }.padding(.top, 24).padding(.bottom, 40)
            }
        }
        .background(Color.surface.ignoresSafeArea())
        .refreshable { await refresh() }
        .sheet(isPresented: Binding(get: { mergeDiff != nil }, set: { if !$0 { mergeDiff = nil } })) {
            if let diff = mergeDiff, let vid = mergeVesselId {
                let vn = vm.vessels.first(where: { $0.id == vid })?.name ?? "Vessel"
                MergeReviewSheet(diff: diff, vesselName: vn, onAccept: { vChanges, nChecks, updates in
                    MergeEngine.applyMerge(diff: diff, remoteVessel: mergeRemoteVessel, vm: vm, vesselId: vid, acceptVesselChanges: vChanges, acceptNewChecks: nChecks, acceptUpdates: updates)
                    Haptics.success()
                    mergeDiff = nil
                }, onCancel: { mergeDiff = nil })
            }
        }
    }

    // MARK: - Vessel Card

    private func vesselCard(_ wv: WorkspaceVessel) -> some View {
        let localVessel = vm.vessels.first(where: { $0.id == wv.vesselId })
        let crew = localVessel.map { vm.checksForVessel($0.id) } ?? []
        let scenario = wv.fleetScenario
        let isSyncing = syncingVesselId == wv.vesselId

        // Scenario progress
        let requiredDocs = scenario?.requiredVesselDocTypes ?? []
        let existingDocs = (localVessel?.documents ?? []).filter { !$0.isArchived }
        let docsReady = requiredDocs.filter { req in existingDocs.contains(where: { $0.vesselDocType == req }) }.count

        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    Circle().fill(Color.surfaceMuted).frame(width: 44, height: 44)
                        .overlay { Image(systemName: localVessel?.vesselType?.icon ?? "ferry").font(.system(size: 16)).foregroundStyle(.secondary) }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(wv.vesselName).font(Typo.body).fontWeight(.semibold)
                        HStack(spacing: 8) {
                            if let s = scenario {
                                MetadataPill(icon: s.icon, text: s.shortName)
                            }
                            Text("\(crew.count) crew").font(Typo.meta).foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if isSyncing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.quaternary)
                    }
                }

                // Scenario progress
                if !requiredDocs.isEmpty {
                    ProgressBar(value: docsReady, total: requiredDocs.count)
                }

                Text("Added by \(wv.addedByName) \u{2022} \(scenario?.shortName ?? "")").font(.system(size: 10)).foregroundStyle(.quaternary)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)

            Divider().padding(.leading, 78)
        }
        .contextMenu {
            if !isCollaborator {
                Button { Task { await pushVessel(wv) } } label: { Label("Push Changes", systemImage: "arrow.up.circle") }
            }
            Button { Task { await pullWithReview(wv) } } label: { Label("Pull Latest", systemImage: "arrow.down.circle") }
            Button { downloadPackage(wv) } label: { Label("Download Package", systemImage: "square.and.arrow.down") }
            if !isCollaborator {
                Divider()
                Button(role: .destructive) {
                    Task { try? await CollaborationService.shared.removeVesselFromWorkspace(vesselId: wv.vesselId); await refresh() }
                } label: { Label("Remove from Workspace", systemImage: "minus.circle") }
            }
        }
    }

    // MARK: - Activity Row

    private func activityRow(_ event: ActivityEvent) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle().fill(Color.surfaceMuted).frame(width: 28, height: 28)
                .overlay { Text(String(event.agentName.prefix(1)).uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary) }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(event.agentName) \(event.action.replacingOccurrences(of: "_", with: " "))").font(Typo.body).lineLimit(1)
                if !event.entityName.isEmpty { Text(event.entityName).font(Typo.meta).foregroundStyle(.secondary) }
            }
            Spacer()
            Text(event.createdAt.suffix(8).prefix(5)).font(Typo.meta).foregroundStyle(.quaternary)
        }.padding(.horizontal, 20).padding(.vertical, 8)
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
            workspaceVessels = try await CollaborationService.shared.listWorkspaceVessels()
            activity = try await CollaborationService.shared.getActivity()
            error = nil
            // Auto-sync vessel data on refresh
            await syncAllVessels()
        } catch { self.error = error.localizedDescription }
    }

    private func syncAllVessels() async {
        isSyncingAll = true; defer { isSyncingAll = false }
        for wv in workspaceVessels {
            do {
                guard let snapshot = try await CollaborationService.shared.pullVessel(vesselId: wv.vesselId) else { continue }
                // Auto-merge: add new vessels/checks, update existing
                if let vessels = snapshot.vessels {
                    for v in vessels {
                        if let i = vm.vessels.firstIndex(where: { $0.id == v.id }) {
                            vm.vessels[i] = v  // Update existing
                        } else {
                            vm.vessels.append(v)  // Add new
                        }
                    }
                }
                if let checks = snapshot.checks {
                    for check in checks {
                        if let i = vm.checks.firstIndex(where: { $0.id == check.id }) {
                            vm.checks[i] = check  // Replace with remote (includes documents)
                        } else {
                            vm.checks.append(check)  // Add new
                        }
                    }
                }
                // Sync files (download missing images from server)
                await FilesSyncService.shared.downloadMissingFiles(vesselId: wv.vesselId, vm: vm)
            } catch { /* individual vessel sync failure — continue with others */ }
        }
        vm.saveChecks()
        vm.saveVessels()
    }

    private func pushVessel(_ wv: WorkspaceVessel) async {
        guard let vessel = vm.vessels.first(where: { $0.id == wv.vesselId }) else { return }
        syncingVesselId = wv.vesselId; defer { syncingVesselId = nil }
        do {
            _ = try await CollaborationService.shared.pushVessel(vessel: vessel, checks: vm.checksForVessel(vessel.id))
            // Upload any local images to server
            await FilesSyncService.shared.uploadMissingFiles(vesselId: vessel.id, vm: vm)
            Haptics.success(); await refresh()
        } catch { self.error = "Push failed: \(error.localizedDescription)" }
    }

    private func pullWithReview(_ wv: WorkspaceVessel) async {
        guard let localVessel = vm.vessels.first(where: { $0.id == wv.vesselId }) else { return }
        syncingVesselId = wv.vesselId; defer { syncingVesselId = nil }
        do {
            guard let snapshot = try await CollaborationService.shared.pullVessel(vesselId: wv.vesselId) else {
                self.error = "No remote data for this vessel"; return
            }
            let remoteVessel = snapshot.vessels?.first(where: { $0.id == wv.vesselId })
            let localChecks = vm.checksForVessel(wv.vesselId)
            let diff = MergeEngine.computeDiff(localVessel: localVessel, localChecks: localChecks, remoteVessel: remoteVessel, remoteChecks: snapshot.checks)

            if diff.isEmpty {
                Haptics.light(); self.error = nil
                // Show "already up to date" briefly
                return
            }

            mergeRemoteVessel = remoteVessel
            mergeRemoteChecks = snapshot.checks
            mergeVesselId = wv.vesselId
            mergeDiff = diff
        } catch { self.error = "Pull failed: \(error.localizedDescription)" }
    }

    private func downloadPackage(_ wv: WorkspaceVessel) {
        guard let _ = vm.vessels.first(where: { $0.id == wv.vesselId }) else { return }
        if let url = vm.generateTransferPackage(vesselId: wv.vesselId, scenario: .vesselSale) {
            downloadURL = IdentifiableURL(url: url)
            Haptics.success()
        }
    }
}

// MARK: - Add Vessel to Workspace Sheet

struct AddVesselToWorkspaceSheet: View {
    @ObservedObject var vm: KYCViewModel
    var existingVesselIds: Set<String> = []
    var onAdded: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedVessel: Vessel?
    @State private var selectedScenario: FleetScenario = .preSurvey
    @State private var isAdding = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    // Vessel picker
                    Section("Select Vessel") {
                        ForEach(vm.vessels.filter { !existingVesselIds.contains($0.id) }) { vessel in
                            Button {
                                selectedVessel = vessel
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: vessel.vesselType?.icon ?? "ferry").font(.system(size: 14)).foregroundStyle(.secondary).frame(width: 24)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(vessel.name).font(Typo.body).fontWeight(.medium).foregroundStyle(.primary)
                                        if !vessel.imoNumber.isEmpty { Text("IMO \(vessel.imoNumber)").font(Typo.meta).foregroundStyle(.secondary) }
                                    }
                                    Spacer()
                                    if selectedVessel?.id == vessel.id {
                                        Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.primary)
                                    }
                                }
                            }.buttonStyle(.plain)
                        }
                    }

                    // Scenario picker
                    Section("Collaboration Scenario") {
                        ForEach(FleetScenario.allCases) { scenario in
                            Button {
                                selectedScenario = scenario
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: scenario.icon).font(.system(size: 14)).foregroundStyle(.secondary).frame(width: 24)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(scenario.rawValue).font(Typo.body).foregroundStyle(.primary)
                                        Text(scenario.relevantRoles.map(\.shortTitle).joined(separator: ", ")).font(Typo.meta).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if selectedScenario == scenario {
                                        Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.primary)
                                    }
                                }
                            }.buttonStyle(.plain)
                        }
                    }

                    if let error { Section { Text(error).font(Typo.meta).foregroundStyle(Color.flagged) } }
                }

                Button {
                    Task { await add() }
                } label: { Text(isAdding ? "Adding..." : "Add to Workspace") }
                    .buttonStyle(PrimaryButtonStyle(isEnabled: selectedVessel != nil && !isAdding))
                    .disabled(selectedVessel == nil || isAdding)
                    .padding(.horizontal, 32).padding(.bottom, 20)
            }
            .navigationTitle("Add Vessel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func add() async {
        guard let vessel = selectedVessel else { return }
        isAdding = true; error = nil
        do {
            try await CollaborationService.shared.addVesselToWorkspace(vessel: vessel, scenario: selectedScenario)
            // Auto-push the vessel data after adding
            _ = try await CollaborationService.shared.pushVessel(vessel: vessel, checks: vm.checksForVessel(vessel.id))
            await onAdded()
            Haptics.success()
            dismiss()
        } catch { self.error = error.localizedDescription }
        isAdding = false
    }
}

// MARK: - Create/Join Sheets (unchanged)

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
                    Button { UIPasteboard.general.string = result.code; Haptics.light() } label: { Label("Copy Code", systemImage: "doc.on.doc").font(Typo.body) }
                    Spacer()
                    Button { dismiss() } label: { Text("Done") }.buttonStyle(PrimaryButtonStyle()).padding(.horizontal, 48)
                    Spacer().frame(height: 20)
                } else {
                    Spacer()
                    Image(systemName: "person.3").font(.system(size: 44)).foregroundStyle(.quaternary)
                    Text("Create a Workspace").font(Typo.context)
                    Text("Other agents can join using a code.").font(Typo.meta).foregroundStyle(.secondary)
                    TextField("Workspace name (e.g. fleet name)", text: $name).font(Typo.body).textFieldStyle(.roundedBorder).padding(.horizontal, 32)
                    if let error { Text(error).font(Typo.meta).foregroundStyle(Color.flagged) }
                    Spacer()
                    Button { Task { await create() } } label: { Text(isCreating ? "Creating..." : "Create") }
                        .buttonStyle(PrimaryButtonStyle(isEnabled: !name.trimmingCharacters(in: .whitespaces).isEmpty && !isCreating))
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isCreating).padding(.horizontal, 48)
                    Spacer().frame(height: 20)
                }
            }.background(Color.surface.ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .cancellationAction) { if result == nil { Button("Cancel") { dismiss() } } } }
        }
    }
    private func create() async {
        isCreating = true; error = nil
        do { result = try await CollaborationService.shared.createWorkspace(name: name.trimmingCharacters(in: .whitespaces)); await onCreated(); Haptics.success() } catch { self.error = error.localizedDescription }
        isCreating = false
    }
}

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
                TextField("Workspace code", text: $code).font(.system(size: 24, weight: .bold, design: .monospaced))
                    .multilineTextAlignment(.center).textInputAutocapitalization(.characters).autocorrectionDisabled().padding(.horizontal, 48)
                if let error { Text(error).font(Typo.meta).foregroundStyle(Color.flagged) }
                Spacer()
                Button { Task { await join() } } label: { Text(isJoining ? "Joining..." : "Join") }
                    .buttonStyle(PrimaryButtonStyle(isEnabled: code.count >= 6 && !isJoining))
                    .disabled(code.count < 6 || isJoining).padding(.horizontal, 48)
                Spacer().frame(height: 20)
            }.background(Color.surface.ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
    private func join() async {
        isJoining = true; error = nil
        do { _ = try await CollaborationService.shared.joinWorkspace(code: code); await onJoined(); Haptics.success(); dismiss() } catch { self.error = error.localizedDescription }
        isJoining = false
    }
}

