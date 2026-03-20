//
//  SeaPay_KYCApp.swift
//  OceanCheck
//
//  Dual-mode: Agent (verify others) or Subject (self-verify via invite)
//

import SwiftUI

enum AppMode: String {
    case none       // first launch — choose mode
    case agent      // full agent experience
    case subject    // invited to self-verify
}

@Observable
class AppState {
    var mode: AppMode
    var isConfigured: Bool
    var pendingInviteURL: URL?

    init() {
        if let stored = KeychainService.get(.appMode) {
            mode = AppMode(rawValue: stored) ?? .none
        } else {
            mode = .none
        }
        isConfigured = AppConfiguration.isConfigured
    }

    func setMode(_ m: AppMode) {
        mode = m
        KeychainService.save(m.rawValue, for: .appMode)
    }

    func didConfigure() {
        withAnimation(.easeInOut(duration: 0.4)) { isConfigured = true }
    }

    func didReset() {
        withAnimation(.easeInOut(duration: 0.4)) {
            isConfigured = false
            mode = .none
            KeychainService.delete(.appMode)
        }
    }
}

@main
struct SeaPay_KYCApp: App {
    @State private var appState = AppState()
    @State private var vm = KYCViewModel()

    init() {
        BrandFont.registerIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch appState.mode {
                case .none:
                    ModeSelectionView(appState: appState)
                        .transition(.opacity)

                case .agent:
                    if appState.isConfigured {
                        HomeView(vm: vm, appState: appState)
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                    } else {
                        SetupView(vm: vm, onComplete: { appState.didConfigure() }, onSwitchMode: { appState.setMode(.none) })
                            .transition(.opacity.combined(with: .move(edge: .leading)))
                    }

                case .subject:
                    SubjectFlowView(appState: appState)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .animation(.smooth(duration: 0.4), value: appState.mode)
            .animation(.smooth(duration: 0.4), value: appState.isConfigured)
            .onOpenURL { url in
                handleDeepLink(url)
            }
        }
    }

    private func handleDeepLink(_ url: URL) {
        // oceancheck://verify?session=XXX&agent=Name&ref=OC-XXX
        guard url.scheme == AppConfiguration.urlScheme else { return }
        appState.pendingInviteURL = url
        if appState.mode == .none || appState.mode == .subject {
            appState.setMode(.subject)
        }
    }
}
