//
//  BiometricService.swift
//  OceanCheck
//
//  Face ID / Touch ID lock for app access.
//  Guards PII data when returning from background.
//

import LocalAuthentication
import Foundation

enum BiometricService {

    enum BiometricType { case faceID, touchID, none }

    static var availableType: BiometricType {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return .none }
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        default: return .none
        }
    }

    static var isAvailable: Bool { availableType != .none }

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "biometricLockEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "biometricLockEnabled") }
    }

    /// Prompt the user for biometric authentication.
    /// Returns true if authenticated, false if failed or cancelled.
    static func authenticate(reason: String = "Unlock OceanCheck to access compliance data") async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Use Passcode"

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return false }

        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }

    static var biometricName: String {
        switch availableType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .none: return "Biometrics"
        }
    }

    static var biometricIcon: String {
        switch availableType {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .none: return "lock"
        }
    }
}
