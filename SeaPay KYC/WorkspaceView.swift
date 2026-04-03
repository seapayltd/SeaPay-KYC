//
//  WorkspaceView.swift
//  OceanCheck
//
//  Workspace tab — multi-workspace list + vessel-selective, role-based collaboration.
//

import SwiftUI

// MARK: - Workspace Tab (root — shows list of workspaces)

struct WorkspaceTabView: View {
    @ObservedObject var vm: KYCViewModel
    @ObservedObject private var collab = CollaborationService.shared
    @State private var selectedWorkspace: WorkspaceInfo?
    @State private var showCreate = false
    @State private var showJoin = false
    private var isCollaborator: Bool { UserDefaults.standard.bool(forKey: "isCollaborator") && AppConfiguration.apiKey.isEmpty }

    var body: some View {
        Group {
            if collab.storedWorkspaces.isEmpty {
                emptyState
            } else {
                workspaceList
            }
        }
        .sheet(isPresented: $showCreate) {
            CreateWorkspaceSheet(vm: vm, onCreated: {})
        }
        .sheet(isPresented: $showJoin) {
            JoinWorkspaceSheet(vm: vm, onJoined: {})
        }
        .navigationDestination(item: $selectedWorkspace) { ws in
            WorkspaceDetailView(vm: vm, workspace: ws)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                Image(systemName: "person.3.sequence")
                    .font(.system(size: 52)).foregroundStyle(.primary.opacity(0.08))

                VStack(spacing: 8) {
                    Text("Workspaces").font(BrandFont.brand(24))
                    Text("Collaborate on vessels with other agents. Share data, documents, and compliance status in real time.")
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

    // MARK: - Workspace List

    private var workspaceList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(collab.storedWorkspaces, id: \.workspaceId) { ws in
                    Button {
                        collab.selectWorkspace(ws)
                        selectedWorkspace = ws
                    } label: {
                        workspaceCard(ws)
                    }
                    .buttonStyle(.plain)
                }

                // Actions at the bottom
                VStack(spacing: 10) {
                    if !isCollaborator {
                        Button { showCreate = true } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "plus").font(.system(size: 14, weight: .medium))
                                Text("Create Workspace").font(.system(size: 14, weight: .medium))
                            }
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(Color.surfaceMuted.opacity(0.4))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Button { showJoin = true } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "link.badge.plus").font(.system(size: 14, weight: .medium))
                            Text("Join with Code").font(.system(size: 14, weight: .medium))
                        }
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Color.surfaceMuted.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 80)
        }
        .background(Color.surface.ignoresSafeArea())
    }

    private func workspaceCard(_ ws: WorkspaceInfo) -> some View {
        HStack(spacing: 16) {
            Circle().fill(Color.surfaceMuted).frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: "person.3").font(.system(size: 16)).foregroundStyle(.secondary)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(ws.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary).lineLimit(1)
                Text(ws.code)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.quaternary)
        }
        .padding(16)
        .background(Color.surfaceMuted.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.primary.opacity(0.06), lineWidth: 0.5))
    }
}

// MARK: - Workspace Detail (inside a specific workspace)

struct WorkspaceDetailView: View {
    @ObservedObject var vm: KYCViewModel
    let workspace: WorkspaceInfo
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var collab = CollaborationService.shared
    @ObservedObject private var fileSync = FilesSyncService.shared
    @State private var workspaceDetail: WorkspaceDetail?
    @State private var workspaceVessels: [WorkspaceVessel] = []
    @State private var activity: [ActivityEvent] = []
    @State private var error: String?
    @State private var syncingVesselId: String?
    @State private var mergeDiff: MergeDiff?
    @State private var mergeVesselId: String?
    @State private var mergeRemoteVessel: Vessel?
    @State private var mergeRemoteChecks: [KYCCheck]?
    @State private var showActivity = false
    @State private var isSyncingAll = false
    @State private var hasLoadedOnce = false
    @State private var selectedVesselId: String?
    @State private var codeCopied = false
    private var isCollaborator: Bool { UserDefaults.standard.bool(forKey: "isCollaborator") && AppConfiguration.apiKey.isEmpty }

    private enum SheetType: Identifiable {
        case edit, addVessel, download(URL), merge
        var id: String {
            switch self {
            case .edit: "edit"
            case .addVessel: "addVessel"
            case .download: "download"
            case .merge: "merge"
            }
        }
    }
    @State private var activeSheet: SheetType?

    /// Live name — updates when workspace is edited
    private var workspaceName: String {
        collab.storedWorkspaces.first(where: { $0.workspaceId == workspace.workspaceId })?.name ?? workspace.name
    }

    var body: some View {
        connectedView
            .navigationTitle(workspaceName)
            .navigationBarTitleDisplayMode(.large)
            .task { await loadWorkspace() }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { activeSheet = .edit } label: {
                            Label("Edit Workspace", systemImage: "pencil")
                        }
                        .disabled(isCollaborator)

                        Button {
                            UIPasteboard.general.string = workspace.code
                            Haptics.success()
                            codeCopied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { codeCopied = false }
                        } label: {
                            Label(codeCopied ? "Copied!" : "Copy Code", systemImage: codeCopied ? "checkmark" : "doc.on.doc")
                        }

                        Divider()

                        Button(role: .destructive) {
                            Task {
                                selectedVesselId = nil
                                try? await CollaborationService.shared.leaveWorkspace()
                                if isCollaborator {
                                    vm.checks.removeAll(); vm.vessels.removeAll()
                                    vm.saveChecks(); vm.saveVessels()
                                    let fm = FileManager.default
                                    if let files = try? fm.contentsOfDirectory(atPath: vm.imagesDir.path) {
                                        for f in files { try? fm.removeItem(at: vm.imagesDir.appendingPathComponent(f)) }
                                    }
                                }
                                dismiss()
                            }
                        } label: {
                            Label("Leave Workspace", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 17))
                    }
                }
            }
            .navigationDestination(item: $selectedVesselId) { vesselId in
                if let vessel = vm.vessels.first(where: { $0.id == vesselId }) {
                    VesselDetailView(vm: vm, vessel: vessel)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle").font(.system(size: 36)).foregroundStyle(.quaternary)
                        Text("Vessel not synced yet").font(Typo.context).foregroundStyle(.secondary)
                        Text("Pull to refresh to download this vessel's data.")
                            .font(Typo.meta).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                    }
                    .padding(32)
                    .navigationTitle("Vessel")
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .edit:
                    if let ws = workspaceDetail?.workspace {
                        EditWorkspaceSheet(workspaceName: ws.name, onSave: {
                            await refreshMetadata()  // Refresh header card + activity from backend
                        })
                        .presentationDetents([.medium])
                    }
                case .addVessel:
                    AddVesselToWorkspaceSheet(vm: vm, existingVesselIds: Set(workspaceVessels.map(\.vesselId)), onAdded: { await refreshMetadata() })
                case .download(let url):
                    ActivityView(items: [url])
                case .merge:
                    if let diff = mergeDiff, let vid = mergeVesselId {
                        MergeReviewSheet(diff: diff, vesselName: vm.vessels.first(where: { $0.id == vid })?.name ?? "Vessel", onAccept: { v, n, u in
                            MergeEngine.applyMerge(diff: diff, remoteVessel: mergeRemoteVessel, vm: vm, vesselId: vid, acceptVesselChanges: v, acceptNewChecks: n, acceptUpdates: u)
                            Haptics.success(); mergeDiff = nil
                        }, onCancel: { mergeDiff = nil })
                    }
                }
            }
    }

    // MARK: - Connected

    private var connectedView: some View {
        ScrollView {
                VStack(spacing: 0) {
                    // Workspace header card — info only (actions in toolbar ··· menu)
                    if let ws = workspaceDetail?.workspace {
                        HStack(spacing: 14) {
                            VStack(alignment: .leading, spacing: 6) {
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

                                // Agent avatars
                                if let agents = workspaceDetail?.agents.filter(\.active), !agents.isEmpty {
                                    HStack(spacing: -6) {
                                        ForEach(agents) { a in
                                            Circle().fill(Color.surfaceMuted).frame(width: 28, height: 28)
                                                .overlay { Text(String(a.agentName.prefix(1)).uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary) }
                                                .overlay(Circle().stroke(Color.surface, lineWidth: 2))
                                        }
                                    }
                                }
                            }
                            Spacer()
                        }
                        .padding(14)
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
                        }
                    }
                    .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 8)

                    // Vessel cards — same layout as Vessels tab
                    if workspaceVessels.isEmpty {
                        VStack(spacing: 16) {
                            Spacer(minLength: 60)
                            Image(systemName: "ferry").font(.system(size: 44)).foregroundStyle(.quaternary)
                            Text(isCollaborator ? "Waiting for shared vessels" : "No vessels shared yet")
                                .font(.system(size: 16, weight: .semibold)).foregroundStyle(.secondary)
                            Text(isCollaborator ? "The agent will share vessels with you" : "Add a vessel to start collaborating")
                                .font(Typo.meta).foregroundStyle(.quaternary)
                            if !isCollaborator {
                                Button { activeSheet = .addVessel } label: {
                                    Text("Add Vessel")
                                }
                                .buttonStyle(PrimaryButtonStyle())
                                .padding(.horizontal, 64)
                                .padding(.top, 4)
                            }
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        LazyVStack(spacing: 16) {
                            ForEach(workspaceVessels) { wv in
                                let lv = vm.vessels.first(where: { $0.id == wv.vesselId })
                                Button {
                                    selectedVesselId = wv.vesselId
                                } label: {
                                    vesselCardView(wv, localVessel: lv)
                                }
                                .buttonStyle(.plain)
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
                                            Task { try? await CollaborationService.shared.removeVesselFromWorkspace(vesselId: wv.vesselId); await refreshMetadata() }
                                        } label: { Label("Remove from Workspace", systemImage: "minus.circle") }
                                    }
                                }
                            }

                            // Add vessel button — inline with vessel list
                            if !isCollaborator {
                                Button { activeSheet = .addVessel } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "plus")
                                            .font(.system(size: 14, weight: .medium))
                                        Text("Add Vessel to Workspace")
                                            .font(.system(size: 14, weight: .medium))
                                    }
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 18)
                                    .background(Color.surfaceMuted.opacity(0.4))
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .strokeBorder(Color.primary.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    // Activity — card style matching People tab rows
                    if !activity.isEmpty {
                        HStack {
                            Text("ACTIVITY").font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary).tracking(0.5)
                            Spacer()
                            if activity.count > 3 {
                                Button {
                                    withAnimation(.smooth(duration: 0.25)) { showActivity.toggle() }
                                } label: {
                                    Text(showActivity ? "Show Less" : "Show All (\(activity.count))")
                                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.horizontal, 16).padding(.top, 24).padding(.bottom, 6)

                        LazyVStack(spacing: 4) {
                            ForEach(showActivity ? Array(activity.prefix(20)) : Array(activity.prefix(3))) { event in
                                activityCard(event)
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    // Error
                    if let error {
                        Text(error).font(Typo.meta).foregroundStyle(Color.flagged)
                            .padding(.horizontal, 16).padding(.top, 12)
                    }

                    Spacer().frame(height: 80)
                }
            }
            .background(Color.surface.ignoresSafeArea())
            .refreshable { await fullRefresh() }
    }

    // MARK: - Vessel Card (identical to Vessels tab)

    private func vesselCardView(_ wv: WorkspaceVessel, localVessel: Vessel?) -> some View {
        let seafarers = localVessel.map { vm.checksForVessel($0.id) } ?? []
        let compliance = localVessel.map { vm.complianceChecksForVessel($0.id) } ?? []
        let crewPassed = seafarers.filter { $0.status == .passed }.count
        let compPassed = compliance.filter { $0.status == .passed }.count
        let hasFlag = seafarers.contains { $0.status == .failed } || compliance.contains { $0.status == .failed }
        let hasWarning = !hasFlag && (seafarers.contains { $0.status == .requiresReview } || compliance.contains { $0.status == .requiresReview })

        return WalletVesselCard(
            vesselName: wv.vesselName,
            vesselType: localVessel?.vesselType?.rawValue,
            vesselTypeIcon: localVessel?.vesselType?.icon ?? "ferry",
            flagState: localVessel?.flagState ?? "",
            imoNumber: wv.vesselImo,
            photoData: localVessel?.photoFilename.flatMap { vm.loadDocumentImage(filename: $0) },
            crewCount: seafarers.count,
            crewPassed: crewPassed,
            complianceCount: compliance.count,
            compliancePassed: compPassed,
            hasFlag: hasFlag,
            hasWarning: hasWarning
        )
    }

    // MARK: - Activity Card (matches People tab row style)

    private func activityCard(_ event: ActivityEvent) -> some View {
        HStack(spacing: 14) {
            Circle().fill(Color.surfaceMuted).frame(width: 36, height: 36)
                .overlay { Text(String(event.agentName.prefix(1)).uppercased()).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary) }

            VStack(alignment: .leading, spacing: 3) {
                Text(event.agentName).font(.system(size: 14, weight: .medium)).lineLimit(1)
                HStack(spacing: 6) {
                    Text(event.action.replacingOccurrences(of: "_", with: " "))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    if !event.entityName.isEmpty {
                        Text("·").foregroundStyle(.quaternary)
                        Text(event.entityName).font(.system(size: 11)).foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer()
            Text(event.createdAt.suffix(8).prefix(5))
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(Color.secondary.opacity(0.5))
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Color.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
    }

    // MARK: - Actions

    private func loadWorkspace() async {
        await refreshMetadata()
        if !hasLoadedOnce {
            hasLoadedOnce = true
            await syncAllVessels()
        }
    }

    /// Lightweight — just workspace info, vessel list, activity. No data sync.
    private func refreshMetadata() async {
        do {
            workspaceDetail = try await CollaborationService.shared.getWorkspaceInfo()
            workspaceVessels = try await CollaborationService.shared.listWorkspaceVessels()
            activity = try await CollaborationService.shared.getActivity()
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    /// Full sync — pull-to-refresh triggers this
    private func fullRefresh() async {
        await refreshMetadata()
        await syncAllVessels()
    }

    private func syncAllVessels() async {
        guard vm.isOnline else {
            self.error = "You're offline — pull down to sync when connectivity returns"
            return
        }
        isSyncingAll = true; defer { isSyncingAll = false }
        let total = workspaceVessels.count
        guard total > 0 else { return }
        let activityId = SyncActivityMonitor.shared.begin("Syncing \(total) vessel\(total == 1 ? "" : "s")", type: .sync)
        var synced = 0
        var errors: [String] = []

        for (idx, wv) in workspaceVessels.enumerated() {
            SyncActivityMonitor.shared.update(activityId, description: "Syncing \(idx + 1)/\(total) — \(wv.vesselName)")
            do {
                // Use CollaborationService for proper auth + error handling (token refresh on 401)
                guard let snapshotDict = try await CollaborationService.shared.pullVesselRaw(vesselId: wv.vesselId) else {
                    errors.append("\(wv.vesselName): no data on server")
                    continue
                }

                let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601

                // Decode vessels separately (so one bad field doesn't kill everything)
                if let vesselsRaw = snapshotDict["vessels"] {
                    let vesselsData = try JSONSerialization.data(withJSONObject: vesselsRaw)
                    do {
                        let vessels = try decoder.decode([Vessel].self, from: vesselsData)
                        for v in vessels {
                            if let i = vm.vessels.firstIndex(where: { $0.id == v.id }) { vm.vessels[i] = v }
                            else { vm.vessels.append(v) }
                        }
                    } catch {
                        errors.append("\(wv.vesselName): vessel decode failed")
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
                        errors.append("\(wv.vesselName): check decode failed")
                    }
                }

                // Download files
                await FilesSyncService.shared.downloadMissingFiles(vesselId: wv.vesselId, vm: vm)
                synced += 1
            } catch is CollabError {
                // Auth failure (401) — stop sync
                self.error = "Session expired — rejoin workspace"
                break
            } catch {
                errors.append("\(wv.vesselName): \(error.localizedDescription)")
            }
        }
        vm.saveChecks(); vm.saveVessels()
        SyncActivityMonitor.shared.complete(activityId, success: synced > 0)

        if !errors.isEmpty {
            self.error = "Sync issues: \(errors.joined(separator: "; "))"
        } else {
            self.error = nil
        }
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
            activeSheet = .merge
        } catch { self.error = "Pull failed: \(error.localizedDescription)" }
    }

    private func downloadPackage(_ wv: WorkspaceVessel) {
        if let url = vm.generateTransferPackage(vesselId: wv.vesselId, scenario: .vesselSale) {
            activeSheet = .download(url); Haptics.success()
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

// MARK: - Edit Workspace Sheet

struct EditWorkspaceSheet: View {
    let workspaceName: String
    var onSave: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var scenario: FleetScenario = .preSurvey
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Workspace Name").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    TextField("Name", text: $name)
                        .font(.system(size: 16)).textFieldStyle(.roundedBorder)
                }
                .padding(.horizontal, 20)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Purpose").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(FleetScenario.allCases) { s in
                                Button { scenario = s } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: s.icon).font(.system(size: 11))
                                        Text(s.shortName).font(.system(size: 12, weight: scenario == s ? .semibold : .regular))
                                    }
                                    .foregroundStyle(scenario == s ? .primary : .secondary)
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(scenario == s ? Color.primary.opacity(0.08) : Color.surfaceMuted)
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }

                if let error {
                    Text(error).font(Typo.meta).foregroundStyle(Color.flagged)
                        .padding(.horizontal, 20)
                }

                Spacer()
            }
            .padding(.top, 16)
            .navigationTitle("Edit Workspace")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving..." : "Save") {
                        Task { await save() }
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .onAppear { name = workspaceName }
        }
    }

    private func save() async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isSaving = true; error = nil
        do {
            try await CollaborationService.shared.updateWorkspace(name: trimmed, scenario: scenario.rawValue)
            Haptics.success()
            await onSave()
            dismiss()
        } catch {
            self.error = "Save failed: \(error.localizedDescription)"
        }
        isSaving = false
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
