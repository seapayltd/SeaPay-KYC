//
//  VerificationActivity.swift
//  OceanCheck
//
//  Live Activity for in-progress verification sessions.
//  Shows on Dynamic Island and Lock Screen while polling.
//

import ActivityKit
import Foundation

struct VerificationActivityAttributes: ActivityAttributes {
    /// Fixed properties set at start
    let subjectName: String
    let vesselName: String
    let checkId: String

    /// Dynamic state updated during polling
    struct ContentState: Codable, Hashable {
        let status: String        // "Waiting", "ID Verified", "AML Screening", "Complete", "Failed"
        let elapsedMinutes: Int
        let stage: Int            // 0=waiting, 1=ID done, 2=AML done, 3=complete
        let totalStages: Int      // typically 3
    }
}

// MARK: - Activity Manager

@MainActor
enum VerificationActivityManager {

    private static var activeActivities: [String: Activity<VerificationActivityAttributes>] = [:]

    static func startActivity(checkId: String, subjectName: String, vesselName: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = VerificationActivityAttributes(
            subjectName: subjectName,
            vesselName: vesselName,
            checkId: checkId
        )
        let initialState = VerificationActivityAttributes.ContentState(
            status: "Waiting for verification",
            elapsedMinutes: 0,
            stage: 0,
            totalStages: 3
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: nil),
                pushType: nil
            )
            activeActivities[checkId] = activity
        } catch {
            // Live Activities not available on this device
        }
    }

    static func updateActivity(checkId: String, status: String, stage: Int, elapsedMinutes: Int) {
        guard let activity = activeActivities[checkId] else { return }
        let state = VerificationActivityAttributes.ContentState(
            status: status,
            elapsedMinutes: elapsedMinutes,
            stage: stage,
            totalStages: 3
        )
        Task {
            await activity.update(.init(state: state, staleDate: nil))
        }
    }

    static func endActivity(checkId: String, finalStatus: String) {
        guard let activity = activeActivities[checkId] else { return }
        let finalState = VerificationActivityAttributes.ContentState(
            status: finalStatus,
            elapsedMinutes: 0,
            stage: 3,
            totalStages: 3
        )
        Task {
            await activity.end(.init(state: finalState, staleDate: nil), dismissalPolicy: .after(.now + 30))
            activeActivities.removeValue(forKey: checkId)
        }
    }

    static func endAllActivities() {
        for (checkId, _) in activeActivities {
            endActivity(checkId: checkId, finalStatus: "Session ended")
        }
    }
}
