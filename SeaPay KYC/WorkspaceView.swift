//
//  WorkspaceView.swift
//  OceanCheck
//
//  Fleet tab — vessel-selective, role-based collaboration.
//

import SwiftUI

// MARK: - Fleet Tab

struct FleetTabView: View {
    @ObservedObject var vm: KYCViewModel
    @ObservedObject private var fileSync = FilesSyncService.shared
    @State private var isConnected = false
    @State private var workspaceDetail: WorkspaceDetail?
    @State private var workspaceVessels: [WorkspaceVessel] = []
    @State private var activity: [ActivityEvent] = []
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
    private var isCollaborator: Bool { UserDefaults.standard.bool(forKey: "isCollaborator") && AppConfiguration.apiKey.isEmpty }

    var body: some View {
        Group {
            if isConnected { connectedView } else { disconnectedView }
        }
        .task { await checkConnection() }
        .sheet(isPresented: $showCreate) { CreateWorkspaceSheet(vm: vm, onCreated: { await refresh() }) }
        .sheet(isPresented: $showJoin) { JoinWorkspaceSheet(vm: vm, onJoined: { await refresh() }) }
        .sheet(isPresented: $showAddVessel) { AddVesselToWorkspaceSheet(vm: vm, existingVesselIds: Set(workspaceVessels.map(\.vesselId)), onAdded: { await refresh() }) }
        .sheet(item: $downloadURL) { url in ActivityView(items: [url.url]) }
        .sheet(isPresented: Binding(get: { mergeDiff != nil }, set: { if !$0 { mergeDiff = nil } })) {
            if let diff = mergeDiff, let vid = mergeVesselId {
                MergeReviewSheet(diff: diff, vesselName: vm.vessels.first(where: { $0.id == vid })?.name ?? "Vessel", onAccept: { v, n, u in
                    MergeEngine.applyMerge(diff: diff, remoteVessel: mergeRemoteVessel, vm: vm, vesselId: vid, acceptVesselChanges: v, acceptNewChecks: n, acceptUpdates: u)
                    Haptics.success(); mergeDiff = nil
                }, onCancel: { mergeDiff = nil })
            }
        }
    }

    // MARK: - Disconnected

    private var disconnectedView: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                Image(systemName: "person.3.sequence")
                    .font(.system(size: 52)).foregroundStyle(.primary.opacity(0.08))

                VStack(spacing: 8) {
                    Text("Fleet Collaboration").font(BrandFont.brand(24))
                    Text("Work on vessels together with other agents. Share data, documents, and compliance status in real time.")
                        .font(Typo.meta).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).padding(.horizontal, 36)
                }
            }

            Spacer()

            VStack(spacing: 14) {
                if !isCollaborator {
                    Button { showCreate = true } label: { Text("Create Workspace") }
                        .buttonStyle(PrimaryButtonStyle()).padding(.horizontal, 48)
                }

                if isCollaborator {
                    Button { showJoin = true } label: { Text("Join a Workspace") }
                        .buttonStyle(PrimaryButtonStyle()).padding(.horizontal, 48)
                } else {
                    Button { showJoin = true } label: {
                        Text("Join with Code").font(Typo.body).foregroundStyle(.secondary)
                    }
                }
            }

            Spacer().frame(height: 48)
        }
        .background(Color.surface.ignoresSafeArea())
    }

    // MARK: - Connected

    private var connectedView: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Workspace header card
                    if let ws = workspaceDetail?.workspace {
                        VStack(spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(ws.name).font(.system(size: 20, weight: .bold))
                                    HStack(spacing: 8) {
                                        Text(ws.code)
                                            .font(.system(size: 11, design: .monospaced))
                                            .padding(.horizontal, 8).padding(.vertical, 3)
                                            .background(Color.surfaceMuted)
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                        if let agents = workspaceDetail?.agents {
                                            Text("\(agents.filter(\.active).count) agent\(agents.filter(\.active).count == 1 ? "" : "s")")
                                                .font(Typo.meta).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                Spacer()
                                Button { UIPasteboard.general.string = ws.code; Haptics.light() } label: {
                                    Image(systemName: "doc.on.doc").font(.system(size: 14))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 36, height: 36)
                                        .background(Color.surfaceMuted)
                                        .clipShape(Circle())
                                }
                            }

                            // Agent avatars
                            if let agents = workspaceDetail?.agents.filter(\.active), !agents.isEmpty {
                                HStack(spacing: -6) {
                                    ForEach(agents) { a in
                                        Circle().fill(Color.surfaceMuted).frame(width: 30, height: 30)
                                            .overlay { Text(String(a.agentName.prefix(1)).uppercased()).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary) }
                                            .overlay(Circle().stroke(Color.surface, lineWidth: 2))
                                    }
                                    Spacer()
                                }
                            }
                        }
                        .padding(16)
                        .background(Color.surfaceMuted.opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 16).padding(.top, 8)
                    }

                    // Sync progress
                    if let progress = fileSync.syncProgress {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.mini)
                            Text(progress).font(Typo.meta)
                        }
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(Color.clear_.opacity(0.06))
                        .padding(.top, 8)
                    }

                    // Shared Vessels header
                    HStack {
                        Text("Shared Vessels").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary).tracking(0.3)
                        Spacer()
                        if isSyncingAll {
                            ProgressView().controlSize(.mini)
                        } else {
                            Button { Task { await syncAllVessels() } } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 11))
                                    Text("Sync").font(.system(size: 12, weight: .medium))
                                }.foregroundStyle(.secondary)
                            }
                        }
                        if !isCollaborator {
                            Button { showAddVessel = true } label: {
                                Image(systemName: "plus.circle.fill").font(.system(size: 18)).foregroundStyle(.primary.opacity(0.2))
                            }
                        }
                    }
                    .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 8)

                    // Vessel list
                    if workspaceVessels.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "ferry").font(.system(size: 28)).foregroundStyle(.quaternary)
                            Text(isCollaborator ? "Waiting for shared vessels" : "No vessels shared yet")
                                .font(Typo.body).foregroundStyle(.secondary)
                            if !isCollaborator {
                                Text("Tap + to add a vessel").font(Typo.meta).foregroundStyle(.quaternary)
                            }
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 32)
                    } else {
                        VStack(spacing: 1) {
                            ForEach(workspaceVessels) { wv in
                                let lv = vm.vessels.first(where: { $0.id == wv.vesselId })
                                if let lv {
                                    NavigationLink { VesselDetailView(vm: vm, vessel: lv) } label: {
                                        vesselRow(wv, localVessel: lv)
                                    }.buttonStyle(.plain)
                                } else {
                                    vesselRow(wv, localVessel: nil)
                                }
                            }
                        }
                        .background(Color.surfaceMuted.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 16)
                    }

                    // Activity
                    if !activity.isEmpty {
                        Button { withAnimation(.smooth(duration: 0.2)) { showActivity.toggle() } } label: {
                            HStack {
                                Text("Activity").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary).tracking(0.3)
                                Spacer()
                                Image(systemName: showActivity ? "chevron.up" : "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(.quaternary)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 8)

                        if showActivity {
                            VStack(spacing: 0) {
                                ForEach(activity.prefix(10)) { event in
                                    activityRow(event)
                                }
                            }
                            .background(Color.surfaceMuted.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal, 16)
                        }
                    }

                    // Error
                    if let error {
                        Text(error).font(Typo.meta).foregroundStyle(Color.flagged)
                            .padding(.horizontal, 20).padding(.top, 12)
                    }

                    // Leave workspace
                    Button(role: .destructive) {
                        Task {
                            try? await CollaborationService.shared.leaveWorkspace()
                            if isCollaborator {
                                vm.checks.removeAll(); vm.vessels.removeAll()
                                vm.saveChecks(); vm.saveVessels()
                                let fm = FileManager.default
                                if let files = try? fm.contentsOfDirectory(atPath: vm.imagesDir.path) {
                                    for f in files { try? fm.removeItem(at: vm.imagesDir.appendingPathComponent(f)) }
                                }
                            }
                            await checkConnection()
                        }
                    } label: {
                        VStack(spacing: 3) {
                            Text("Leave Workspace").font(Typo.meta).foregroundStyle(Color.flagged)
                            if isCollaborator {
                                Text("All synced data will be removed").font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.top, 28).padding(.bottom, 40)
                }
            }
            .background(Color.surface.ignoresSafeArea())
            .refreshable { await refresh() }
        }
    }

    // MARK: - Vessel Row

    private func vesselRow(_ wv: WorkspaceVessel, localVessel: Vessel?) -> some View {
        let crew = localVessel.map { vm.checksForVessel($0.id) } ?? []
        let crewPassed = crew.filter { $0.status == .passed }.count
        let compliance = localVessel.map { vm.complianceChecksForVessel($0.id) } ?? []
        let compPassed = compliance.filter { $0.status == .passed }.count
        let hasFlag = crew.contains { $0.status == .failed } || compliance.contains { $0.status == .failed }
        let hasWarning = !hasFlag && (crew.contains { $0.status == .requiresReview } || compliance.contains { $0.status == .requiresReview })

        return WalletVesselCard(
            vesselName: wv.vesselName,
            vesselType: localVessel?.vesselType?.rawValue,
            vesselTypeIcon: localVessel?.vesselType?.icon ?? "ferry",
            flagState: localVessel?.flagState ?? "",
            imoNumber: wv.vesselImo,
            photoData: localVessel?.photoFilename.flatMap { vm.loadDocumentImage(filename: $0) },
            crewCount: crew.count,
            crewPassed: crewPassed,
            complianceCount: compliance.count,
            compliancePassed: compPassed,
            hasFlag: hasFlag,
            hasWarning: hasWarning
        )
        .padding(.horizontal, 16)
        .contextMenu {
            if !isCollaborator {
                Button { Task { await pushVessel(wv) } } label: { Label("Push Changes", systemImage: "arrow.up.circle") }
            }
            Button { Task { await pullWithReview(wv) } } label: { Label("Pull Latest", systemImage: "arrow.down.circle") }
            Divider()
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
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(Color.surfaceMuted).frame(width: 26, height: 26)
                .overlay { Text(String(event.agentName.prefix(1)).uppercased()).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary) }

            VStack(alignment: .leading, spacing: 2) {
                Text("\(event.agentName) \(event.action.replacingOccurrences(of: "_", with: " "))")
                    .font(.system(size: 12)).lineLimit(1)
                if !event.entityName.isEmpty {
                    Text(event.entityName).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(event.createdAt.suffix(8).prefix(5))
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
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
            await syncAllVessels()
        } catch { self.error = error.localizedDescription }
    }

    private func syncAllVessels() async {
        isSyncingAll = true; defer { isSyncingAll = false }
        let total = workspaceVessels.count
        guard total > 0 else { return }
        let activityId = SyncActivityMonitor.shared.begin("Syncing \(total) vessel\(total == 1 ? "" : "s")", type: .sync)
        var synced = 0
        for (idx, wv) in workspaceVessels.enumerated() {
            SyncActivityMonitor.shared.update(activityId, description: "Syncing \(idx + 1)/\(total) — \(wv.vesselName)")
            do {
                // Pull raw JSON and decode vessels/checks separately for better error handling
                guard let token = CollaborationService.shared.workspace?.token else { continue }
                guard let url = URL(string: "https://seapay.me/oceancheck/api/sync.php?action=pull&vessel_id=\(wv.vesselId)") else { continue }
                var req = URLRequest(url: url)
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                req.timeoutInterval = 30

                let (data, _) = try await URLSession.shared.data(for: req)
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                guard let snapshotDict = json["snapshot"] as? [String: Any] else { continue }

                let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601

                // Decode vessels separately (so one failure doesn't kill everything)
                if let vesselsRaw = snapshotDict["vessels"] {
                    let vesselsData = try JSONSerialization.data(withJSONObject: vesselsRaw)
                    do {
                        let vessels = try decoder.decode([Vessel].self, from: vesselsData)
                        for v in vessels {
                            if let i = vm.vessels.firstIndex(where: { $0.id == v.id }) { vm.vessels[i] = v }
                            else { vm.vessels.append(v) }
                        }
                    } catch {
                        self.error = "Vessel decode: \(error.localizedDescription)"
                    }
                }

                // Decode checks separately
                if let checksRaw = snapshotDict["checks"] {
                    let checksData = try JSONSerialization.data(withJSONObject: checksRaw)
                    do {
                        let checks = try decoder.decode([KYCCheck].self, from: checksData)
                        for check in checks {
                            if let i = vm.checks.firstIndex(where: { $0.id == check.id }) { vm.checks[i] = check }
                            else { vm.checks.append(check) }
                        }
                    } catch {
                        self.error = "Check decode: \(error.localizedDescription)"
                    }
                }

                // Download files
                await FilesSyncService.shared.downloadMissingFiles(vesselId: wv.vesselId, vm: vm)
                synced += 1
            } catch {
                self.error = "Sync \(wv.vesselName): \(error.localizedDescription)"
            }
        }
        vm.saveChecks(); vm.saveVessels()
        SyncActivityMonitor.shared.complete(activityId, success: synced > 0)
        if synced > 0 { Haptics.light() }
    }

    private func pushVessel(_ wv: WorkspaceVessel) async {
        guard let vessel = vm.vessels.first(where: { $0.id == wv.vesselId }) else {
            self.error = "Vessel not found locally"; return
        }
        syncingVesselId = wv.vesselId; defer { syncingVesselId = nil }
        let checks = vm.checksForVessel(vessel.id)
        do {
            _ = try await CollaborationService.shared.pushVessel(vessel: vessel, checks: checks)
            // Upload all images for this vessel
            await FilesSyncService.shared.uploadMissingFiles(vesselId: vessel.id, vm: vm)
            self.error = nil
            Haptics.success()
            // Refresh metadata (not full sync — we just pushed)
            workspaceDetail = try? await CollaborationService.shared.getWorkspaceInfo()
            activity = (try? await CollaborationService.shared.getActivity()) ?? []
        } catch {
            self.error = "Push failed: \(error.localizedDescription)"
        }
    }

    private func pullWithReview(_ wv: WorkspaceVessel) async {
        guard let localVessel = vm.vessels.first(where: { $0.id == wv.vesselId }) else { return }
        syncingVesselId = wv.vesselId; defer { syncingVesselId = nil }
        do {
            guard let snapshot = try await CollaborationService.shared.pullVessel(vesselId: wv.vesselId) else {
                self.error = "No remote data"; return
            }
            let remoteVessel = snapshot.vessels?.first(where: { $0.id == wv.vesselId })
            let diff = MergeEngine.computeDiff(localVessel: localVessel, localChecks: vm.checksForVessel(wv.vesselId), remoteVessel: remoteVessel, remoteChecks: snapshot.checks)
            if diff.isEmpty { Haptics.light(); return }
            mergeRemoteVessel = remoteVessel; mergeRemoteChecks = snapshot.checks
            mergeVesselId = wv.vesselId; mergeDiff = diff
        } catch { self.error = "Pull failed: \(error.localizedDescription)" }
    }

    private func downloadPackage(_ wv: WorkspaceVessel) {
        if let url = vm.generateTransferPackage(vesselId: wv.vesselId, scenario: .vesselSale) {
            downloadURL = IdentifiableURL(url: url); Haptics.success()
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

    private var availableVessels: [Vessel] { vm.vessels.filter { !existingVesselIds.contains($0.id) } }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    if availableVessels.isEmpty {
                        Section { Text("All vessels are already in the workspace.").font(Typo.meta).foregroundStyle(.secondary) }
                    } else {
                        Section("Select Vessel") {
                            ForEach(availableVessels) { vessel in
                                Button { selectedVessel = vessel } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: vessel.vesselType?.icon ?? "ferry").font(.system(size: 14)).foregroundStyle(.secondary).frame(width: 24)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(vessel.name).font(Typo.body).fontWeight(.medium).foregroundStyle(.primary)
                                            if !vessel.imoNumber.isEmpty { Text("IMO \(vessel.imoNumber)").font(Typo.meta).foregroundStyle(.secondary) }
                                        }
                                        Spacer()
                                        if selectedVessel?.id == vessel.id { Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)) }
                                    }
                                }.buttonStyle(.plain)
                            }
                        }
                    }

                    Section("Collaboration Purpose") {
                        ForEach(FleetScenario.allCases) { scenario in
                            Button { selectedScenario = scenario } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: scenario.icon).font(.system(size: 14)).foregroundStyle(.secondary).frame(width: 24)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(scenario.rawValue).font(Typo.body).foregroundStyle(.primary)
                                        Text(scenario.relevantRoles.map(\.shortTitle).joined(separator: ", ")).font(Typo.meta).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if selectedScenario == scenario { Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)) }
                                }
                            }.buttonStyle(.plain)
                        }
                    }

                    if let error { Section { Text(error).font(Typo.meta).foregroundStyle(Color.flagged) } }
                }

                Button { Task { await add() } } label: { Text(isAdding ? "Adding..." : "Add to Workspace") }
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
            _ = try await CollaborationService.shared.pushVessel(vessel: vessel, checks: vm.checksForVessel(vessel.id))
            await FilesSyncService.shared.uploadMissingFiles(vesselId: vessel.id, vm: vm)
            await onAdded(); Haptics.success(); dismiss()
        } catch { self.error = error.localizedDescription }
        isAdding = false
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
                        Text("Share this code:").font(Typo.meta).foregroundStyle(.secondary)
                        Text(result.code).font(.system(size: 32, weight: .bold, design: .monospaced)).kerning(4)
                    }
                    Button { UIPasteboard.general.string = result.code; Haptics.light() } label: { Label("Copy", systemImage: "doc.on.doc").font(Typo.body) }
                    Spacer()
                    Button { dismiss() } label: { Text("Done") }.buttonStyle(PrimaryButtonStyle()).padding(.horizontal, 48)
                    Spacer().frame(height: 24)
                } else {
                    Spacer()
                    Image(systemName: "person.3").font(.system(size: 40)).foregroundStyle(.quaternary)
                    Text("Create a Workspace").font(Typo.context)
                    Text("Invite agents by sharing the code.").font(Typo.meta).foregroundStyle(.secondary)
                    TextField("Workspace name", text: $name).font(Typo.body).textFieldStyle(.roundedBorder).padding(.horizontal, 32)
                    if let error { Text(error).font(Typo.meta).foregroundStyle(Color.flagged) }
                    Spacer()
                    Button { Task { await create() } } label: { Text(isCreating ? "Creating..." : "Create") }
                        .buttonStyle(PrimaryButtonStyle(isEnabled: !name.trimmingCharacters(in: .whitespaces).isEmpty && !isCreating))
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isCreating).padding(.horizontal, 48)
                    Spacer().frame(height: 24)
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
                Image(systemName: "link.badge.plus").font(.system(size: 40)).foregroundStyle(.quaternary)
                Text("Join a Workspace").font(Typo.context)
                Text("Enter the code from your agent.").font(Typo.meta).foregroundStyle(.secondary)
                TextField("Code", text: $code)
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .multilineTextAlignment(.center).textInputAutocapitalization(.characters)
                    .autocorrectionDisabled().padding(.horizontal, 48)
                if let error { Text(error).font(Typo.meta).foregroundStyle(Color.flagged) }
                Spacer()
                Button { Task { await join() } } label: { Text(isJoining ? "Joining..." : "Join") }
                    .buttonStyle(PrimaryButtonStyle(isEnabled: code.count >= 6 && !isJoining))
                    .disabled(code.count < 6 || isJoining).padding(.horizontal, 48)
                Spacer().frame(height: 24)
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
