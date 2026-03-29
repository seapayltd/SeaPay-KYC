//
//  MacSupport.swift
//  OceanCheck
//
//  Mac Catalyst adaptations: keyboard shortcuts, menu commands,
//  platform checks, and window management.
//

import SwiftUI

// MARK: - Platform Detection

enum Platform {
    static var isMac: Bool {
        #if targetEnvironment(macCatalyst)
        return true
        #else
        return false
        #endif
    }

    static var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    static var hasCamera: Bool {
        #if targetEnvironment(macCatalyst)
        return false // Mac Catalyst doesn't support AVCaptureDevice well
        #else
        return UIImagePickerController.isSourceTypeAvailable(.camera)
        #endif
    }

    /// Preferred image source — camera on iPhone, file picker on Mac/iPad
    static var preferredImageSource: UIImagePickerController.SourceType {
        hasCamera ? .camera : .photoLibrary
    }
}

// MARK: - Keyboard Shortcut Modifiers

struct KeyboardShortcutModifier: ViewModifier {
    let key: KeyEquivalent
    let modifiers: EventModifiers
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .keyboardShortcut(key, modifiers: modifiers)
    }
}

// MARK: - Common Keyboard Shortcuts

extension View {
    /// Add vessel (Cmd+N)
    func onAddVessel(_ action: @escaping () -> Void) -> some View {
        background(
            Button("") { action() }
                .keyboardShortcut("n", modifiers: .command)
                .opacity(0).allowsHitTesting(false)
        )
    }

    /// Search (Cmd+F) — already handled by .searchable
    /// Export (Cmd+E)
    func onExport(_ action: @escaping () -> Void) -> some View {
        background(
            Button("") { action() }
                .keyboardShortcut("e", modifiers: .command)
                .opacity(0).allowsHitTesting(false)
        )
    }

    /// Settings (Cmd+,)
    func onOpenSettings(_ action: @escaping () -> Void) -> some View {
        background(
            Button("") { action() }
                .keyboardShortcut(",", modifiers: .command)
                .opacity(0).allowsHitTesting(false)
        )
    }

    /// Refresh (Cmd+R)
    func onRefresh(_ action: @escaping () -> Void) -> some View {
        background(
            Button("") { action() }
                .keyboardShortcut("r", modifiers: .command)
                .opacity(0).allowsHitTesting(false)
        )
    }
}

// MARK: - Mac Window Configuration

#if targetEnvironment(macCatalyst)
enum MacWindowHelper {
    static func configureWindow() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }

        // Set minimum and preferred window size
        let minSize = CGSize(width: 900, height: 600)
        let preferredSize = CGSize(width: 1200, height: 800)

        windowScene.sizeRestrictions?.minimumSize = minSize
        windowScene.sizeRestrictions?.maximumSize = CGSize(width: 2000, height: 1400)

        if let window = windowScene.windows.first {
            window.frame.size = preferredSize
        }

        // Set window title
        windowScene.title = "OceanCheck"
    }
}
#endif

// MARK: - Adaptive Document Picker

/// A document image source that works on both iOS (camera + file) and Mac (file only).
struct AdaptiveImagePicker: ViewModifier {
    @Binding var isPresented: Bool
    let onImageSelected: (Data) -> Void

    func body(content: Content) -> some View {
        content
            .fileImporter(isPresented: $isPresented, allowedContentTypes: [.image, .pdf]) { result in
                if case .success(let url) = result {
                    guard url.startAccessingSecurityScopedResource() else { return }
                    defer { url.stopAccessingSecurityScopedResource() }
                    if let data = try? Data(contentsOf: url) {
                        onImageSelected(data)
                    }
                }
            }
    }
}

extension View {
    func adaptiveImagePicker(isPresented: Binding<Bool>, onImageSelected: @escaping (Data) -> Void) -> some View {
        modifier(AdaptiveImagePicker(isPresented: isPresented, onImageSelected: onImageSelected))
    }
}
