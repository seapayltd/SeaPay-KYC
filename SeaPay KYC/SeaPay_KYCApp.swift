//
//  SeaPay_KYCApp.swift
//  SeaPay KYC
//

import SwiftUI

@Observable
class AppState {
    var isConfigured: Bool

    init() {
        isConfigured = AppConfiguration.isConfigured
    }

    func didConfigure() {
        withAnimation(.easeInOut(duration: 0.4)) { isConfigured = true }
    }

    func didReset() {
        withAnimation(.easeInOut(duration: 0.4)) { isConfigured = false }
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
                if appState.isConfigured {
                    HomeView(vm: vm, appState: appState)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                } else {
                    SetupView(vm: vm, onComplete: { appState.didConfigure() })
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .animation(.smooth(duration: 0.4), value: appState.isConfigured)
        }
    }
}
