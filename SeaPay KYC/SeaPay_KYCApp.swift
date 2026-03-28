//
//  SeaPay_KYCApp.swift
//  OceanCheck
//
//  Default to agent. Subject mode entered via "I have a code" on home screen.
//

import SwiftUI

enum AppMode: String { case agent, subject }

@Observable
class AppState {
    var isConfigured: Bool
    var showSubjectFlow = false
    var incomingDeepLink: URL?

    init() { isConfigured = AppConfiguration.isConfigured }

    func didConfigure() { withAnimation(.easeInOut(duration: 0.35)) { isConfigured = true } }
    func didReset() { withAnimation(.easeInOut(duration: 0.35)) { isConfigured = false } }
}

@main
struct SeaPay_KYCApp: App {
    @State private var appState = AppState()
    @State private var vm = KYCViewModel()
    @State private var pendingImportURL: URL?
    @State private var showImportSheet = false
    @State private var showSplash = true
    @State private var showAgentSetup = false
    @State private var showOwnerSetup = false
    @State private var ownerImportSuccess = false
    @AppStorage("colorSchemePreference") private var colorSchemePref = 0
    @State private var ownerAccessCode: String? = UserDefaults.standard.string(forKey: "ownerAccessCode")

    init() {
        // Lightweight only — heavy work deferred to .onAppear
        AgentProfile.migrateIfNeeded()
    }

    private var preferredColorScheme: ColorScheme? {
        switch colorSchemePref {
        case 1: return .light
        case 2: return .dark
        default: return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                Group {
                    if ownerAccessCode != nil {
                        OwnerDashboardView(onSignOut: { ownerAccessCode = nil })
                    } else if appState.isConfigured {
                        HomeView(vm: vm, appState: appState)
                    } else {
                        WelcomeView(
                            onAgent: { showAgentSetup = true },
                            onSubject: { appState.showSubjectFlow = true },
                            onOwner: { showOwnerSetup = true }
                        )
                    }
                }
                .animation(.smooth(duration: 0.35), value: appState.isConfigured)
                .fullScreenCover(isPresented: $showAgentSetup) {
                    SequentialSetupView(vm: vm, appState: appState, ownerAccessCode: $ownerAccessCode, startAtStep: 1)
                }
                .sheet(isPresented: $showOwnerSetup) {
                    OwnerSetupView(ownerAccessCode: $ownerAccessCode)
                }
                .onChange(of: ownerAccessCode) { _, newValue in
                    if newValue != nil { showOwnerSetup = false; showAgentSetup = false }
                }

                // Owner import success toast
                if ownerImportSuccess {
                    VStack {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.clear_)
                            Text("Vessel dashboard updated").font(Typo.body).fontWeight(.medium)
                        }
                        .padding(.horizontal, 20).padding(.vertical, 12)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.1), radius: 10, y: 4)
                        .padding(.top, 60)
                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(2)
                }

                // Branded splash overlay — masks initial render while content preloads
                if showSplash {
                    SplashOverlay()
                        .transition(.opacity.combined(with: .scale(scale: 1.02)))
                        .zIndex(1)
                }
            }
            .onAppear {
                // Register font + load data after first frame (splash already visible)
                BrandFont.registerIfNeeded()
                NotificationService.shared.requestPermission()
                vm.loadIfNeeded()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(.easeOut(duration: 0.4)) { showSplash = false }
                }
            }
            .preferredColorScheme(preferredColorScheme)
            .fullScreenCover(isPresented: $appState.showSubjectFlow) {
                SubjectFlowView(appState: appState)
            }
            .onOpenURL { url in
                // Handle .oceandash owner dashboard files
                if url.pathExtension == "oceandash" {
                    if let snapshot = KYCViewModel.importOwnerDashboard(from: url) {
                        OwnerStorage.save(snapshot)
                        ownerAccessCode = "local"
                        UserDefaults.standard.set("local", forKey: "ownerAccessCode")
                        Haptics.success()
                        ownerImportSuccess = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { ownerImportSuccess = false }
                    }
                    return
                }
                // Handle .oceancheck transfer packages — show import preview
                if url.pathExtension == "oceancheck" {
                    pendingImportURL = url
                    showImportSheet = true
                    return
                }
                if url.scheme == AppConfiguration.urlScheme {
                    appState.incomingDeepLink = url
                    appState.showSubjectFlow = true
                }
            }
            .sheet(isPresented: $showImportSheet) {
                if let url = pendingImportURL {
                    TransferImportSheet(vm: vm, packageURL: url)
                }
            }
        }
    }
}

// MARK: - Welcome View (Three-Mode Role Selector)

struct WelcomeView: View {
    var onAgent: () -> Void
    var onSubject: () -> Void
    var onOwner: () -> Void

    @State private var appear = false

    var body: some View {
        ZStack {
            Color.surface.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Brand
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 48)).foregroundStyle(.primary.opacity(0.1))
                    Text("OceanCheck").font(BrandFont.brand(32))
                    Text("Maritime Compliance").font(Typo.meta).foregroundStyle(.secondary)
                }
                .opacity(appear ? 1 : 0)
                .offset(y: appear ? 0 : 10)

                Spacer().frame(height: 44)

                // Role cards — staggered fade-in
                VStack(spacing: 12) {
                    roleCard(icon: "shield.checkered", title: "Agent",
                             subtitle: "Manage vessels & verify crew", action: onAgent)
                        .opacity(appear ? 1 : 0).offset(y: appear ? 0 : 15)

                    roleCard(icon: "person.badge.shield.checkmark", title: "Crew / Subject",
                             subtitle: "Verify your identity", action: onSubject)
                        .opacity(appear ? 1 : 0).offset(y: appear ? 0 : 20)

                    roleCard(icon: "sailboat", title: "Vessel Owner",
                             subtitle: "View your vessel's compliance", action: onOwner)
                        .opacity(appear ? 1 : 0).offset(y: appear ? 0 : 25)
                }
                .padding(.horizontal, 32)

                Spacer()
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.7)) { appear = true }
        }
    }

    private func roleCard(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.light()
            action()
        } label: {
            HStack(spacing: 16) {
                Circle().fill(Color.surfaceMuted).frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: icon).font(.system(size: 18)).foregroundStyle(.primary)
                    }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary)
                    Text(subtitle).font(Typo.meta).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.quaternary)
            }
            .padding(16)
            .background(Color.surfaceMuted.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.primary.opacity(0.06), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Splash Overlay

struct SplashOverlay: View {
    @State private var appear = false

    var body: some View {
        ZStack {
            Color.surface.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 56)).foregroundStyle(.primary.opacity(0.1))
                Text("OceanCheck").font(BrandFont.brand(36))
                Text("Maritime Identity Verification").font(Typo.meta).foregroundStyle(.secondary)
            }
            .scaleEffect(appear ? 1 : 0.95)
            .opacity(appear ? 1 : 0)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) { appear = true }
        }
    }
}
