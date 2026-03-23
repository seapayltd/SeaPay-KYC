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
    @State private var setupStep = 0 // 0 = api key, 1 = name

    init() {
        BrandFont.registerIfNeeded()
        NotificationService.shared.requestPermission()
    }

    private var preferredColorScheme: ColorScheme? {
        switch UserDefaults.standard.integer(forKey: "colorSchemePreference") {
        case 1: return .light
        case 2: return .dark
        default: return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if appState.isConfigured {
                    HomeView(vm: vm, appState: appState)
                } else {
                    SequentialSetupView(vm: vm, appState: appState)
                }
            }
            .animation(.smooth(duration: 0.35), value: appState.isConfigured)
            .preferredColorScheme(preferredColorScheme)
            .fullScreenCover(isPresented: $appState.showSubjectFlow) {
                SubjectFlowView(appState: appState)
            }
            .onOpenURL { url in
                if url.scheme == AppConfiguration.urlScheme {
                    appState.incomingDeepLink = url
                    appState.showSubjectFlow = true
                }
            }
        }
    }
}
