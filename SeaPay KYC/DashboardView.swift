//
//  DashboardView.swift
//  OceanCheck
//
//  Apple Health-inspired single scrolling dashboard.
//  Replaces the 3-tab HomeView.
//

import SwiftUI

struct DashboardView: View {
    @ObservedObject var vm: KYCViewModel
    var appState: AppState
    private var isCollaborator: Bool { UserDefaults.standard.bool(forKey: "isCollaborator") && AppConfiguration.apiKey.isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Space.xl) {
                    // Fleet Status
                    fleetStatusSection

                    // Needs Attention
                    needsAttentionSection

                    // Recent Activity
                    recentActivitySection

                    // Quick Actions
                    quickActionsSection

                    Spacer(minLength: Space.xxl)
                }
                .padding(.top, Space.lg)
            }
            .background(Color.surface.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("OceanCheck").font(BrandFont.brand(20))
                }
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink { SettingsSheet(vm: vm, appState: appState) } label: {
                        Image(systemName: "gearshape").font(.system(size: 14)).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Fleet Status (horizontal vessel cards)

    private var fleetStatusSection: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(isCollaborator ? "Shared Vessels" : "Fleet Status")
                .font(Typo.caption).foregroundStyle(.secondary).tracking(0.3)
                .padding(.horizontal, Space.lg)

            if vm.vessels.isEmpty {
                CardView {
                    VStack(spacing: Space.sm) {
                        Image(systemName: "ferry").font(.system(size: 28)).foregroundStyle(.quaternary)
                        Text("No vessels yet").font(Typo.body).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, Space.xl)
                }
                .padding(.horizontal, Space.lg)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Space.md) {
                        ForEach(Array(vm.vessels.enumerated()), id: \.element.id) { index, vessel in
                            NavigationLink { VesselDetailView(vm: vm, vessel: vessel) } label: {
                                vesselHealthCard(vessel)
                            }
                            .buttonStyle(.plain)
                            .opacity(1)
                            .animation(.easeOut(duration: 0.3).delay(Double(index) * 0.05), value: vm.vessels.count)
                        }
                    }
                    .padding(.horizontal, Space.lg)
                }
            }
        }
    }

    private func vesselHealthCard(_ vessel: Vessel) -> some View {
        let crew = vm.checksForVessel(vessel.id)
        let passed = crew.filter { $0.status == .passed }.count
        let hasFlag = crew.contains { $0.status == .failed }
        let hasWarning = !hasFlag && crew.contains { $0.status == .requiresReview }
        let photoData = vessel.photoFilename.flatMap { vm.loadDocumentImage(filename: $0) }

        return VStack(alignment: .leading, spacing: Space.sm) {
            // Photo or icon
            ZStack {
                if let data = photoData, let img = UIImage(data: data) {
                    Image(uiImage: img).resizable().scaledToFill()
                        .frame(width: 140, height: 80).clipped()
                } else {
                    Color.surfaceMuted
                        .overlay { Image(systemName: vessel.vesselType?.icon ?? "ferry").font(.system(size: 20)).foregroundStyle(.secondary) }
                        .frame(width: 140, height: 80)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Space.xs) {
                    Text(vessel.name).font(Typo.body).fontWeight(.semibold).lineLimit(1)
                    Circle().fill(hasFlag ? Color.flagged : hasWarning ? Color.review : Color.clear_)
                        .frame(width: 6, height: 6)
                }
                Text("\(crew.count) crew \u{2022} \(passed) clear")
                    .font(Typo.micro).foregroundStyle(.secondary)
            }
            .padding(.horizontal, Space.xs)
        }
        .frame(width: 148)
        .padding(.bottom, Space.sm)
        .background(Color.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.separator, lineWidth: 0.5))
    }

    // MARK: - Needs Attention

    private var needsAttentionSection: some View {
        let expiredChecks = vm.expiredChecks
        let expiringChecks = vm.expiringChecks
        let reviewChecks = vm.checks.filter { $0.status == .requiresReview }
        let items: [(icon: String, color: Color, text: String, id: String)] =
            expiredChecks.map { ("circle.fill", .flagged, "\($0.displayName) — ID expired", $0.id) } +
            expiringChecks.map { ("circle.fill", .review, "\($0.displayName) — expiring soon", $0.id) } +
            reviewChecks.map { ("circle.fill", .review, "\($0.displayName) — needs review", $0.id) }

        return Group {
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: Space.sm) {
                    Text("Needs Attention")
                        .font(Typo.caption).foregroundStyle(.secondary).tracking(0.3)
                        .padding(.horizontal, Space.lg)

                    CardView {
                        VStack(spacing: 0) {
                            ForEach(Array(items.prefix(5).enumerated()), id: \.element.id) { index, item in
                                if index > 0 { Divider().padding(.leading, Space.xl) }
                                HStack(spacing: Space.md) {
                                    Circle().fill(item.color).frame(width: 8, height: 8)
                                    Text(item.text).font(Typo.body).lineLimit(1)
                                    Spacer()
                                }
                                .padding(.vertical, Space.md)
                            }
                        }
                    }
                    .padding(.horizontal, Space.lg)
                }
            }
        }
    }

    // MARK: - Recent Activity

    @State private var showActivity = false

    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Button { withAnimation(.smooth(duration: 0.25)) { showActivity.toggle() } } label: {
                HStack {
                    Text("Recent Activity")
                        .font(Typo.caption).foregroundStyle(.secondary).tracking(0.3)
                    Spacer()
                    Image(systemName: showActivity ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(.quaternary)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Space.lg)

            if showActivity {
                CardView {
                    VStack(spacing: Space.sm) {
                        if vm.checks.isEmpty {
                            Text("No activity yet").font(Typo.body).foregroundStyle(.secondary)
                        } else {
                            ForEach(vm.checks.prefix(5)) { check in
                                HStack(spacing: Space.sm) {
                                    Circle().fill(Color.surfaceMuted).frame(width: 24, height: 24)
                                        .overlay { Text(String(check.displayName.prefix(1)).uppercased()).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary) }
                                    Text(check.displayName).font(Typo.body).lineLimit(1)
                                    Spacer()
                                    Text(check.status.rawValue).font(Typo.micro).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, Space.lg)
            }
        }
    }

    // MARK: - Quick Actions

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("Quick Actions")
                .font(Typo.caption).foregroundStyle(.secondary).tracking(0.3)
                .padding(.horizontal, Space.lg)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Space.sm) {
                if isCollaborator {
                    quickAction(icon: "doc.badge.plus", label: "Upload Doc")
                    quickAction(icon: "arrow.triangle.2.circlepath", label: "Sync")
                    quickAction(icon: "square.and.arrow.down", label: "Download")
                } else {
                    NavigationLink { VesselSheet(vm: vm) } label: { quickAction(icon: "ferry", label: "Add Vessel") }
                    quickAction(icon: "person.badge.plus", label: "Add Crew")
                    quickAction(icon: "tablecells", label: "Export")
                    quickAction(icon: "person.2.badge.plus", label: "Batch Invite")
                }
            }
            .padding(.horizontal, Space.lg)
        }
    }

    private func quickAction(icon: String, label: String) -> some View {
        VStack(spacing: Space.sm) {
            Image(systemName: icon).font(.system(size: 18)).foregroundStyle(.secondary)
            Text(label).font(Typo.caption).foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.lg)
        .background(Color.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.separator, lineWidth: 0.5))
    }
}
