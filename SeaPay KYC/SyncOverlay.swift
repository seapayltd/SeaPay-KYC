//
//  SyncOverlay.swift
//  OceanCheck
//
//  A quiet, confident sync indicator inspired by Jony Ive's design philosophy.
//  Appears as a floating pill at the top of the screen during any sync operation.
//  Minimal, non-intrusive, disappears when done.
//

import SwiftUI
import Combine

// MARK: - Global Sync State

@MainActor
class SyncActivityMonitor: ObservableObject {
    static let shared = SyncActivityMonitor()

    @Published var activities: [SyncActivity] = []

    var isActive: Bool { !activities.isEmpty }
    var currentActivity: SyncActivity? { activities.last }

    func begin(_ description: String, type: SyncActivity.ActivityType = .sync) -> String {
        let id = UUID().uuidString
        let activity = SyncActivity(id: id, description: description, type: type, startedAt: Date())
        withAnimation(.easeOut(duration: 0.25)) { activities.append(activity) }
        return id
    }

    func update(_ id: String, description: String) {
        if let i = activities.firstIndex(where: { $0.id == id }) {
            activities[i].description = description
        }
    }

    func complete(_ id: String, success: Bool = true) {
        if let i = activities.firstIndex(where: { $0.id == id }) {
            activities[i].isComplete = true
            activities[i].success = success
        }
        // Remove after brief display
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            withAnimation(.easeIn(duration: 0.2)) {
                self?.activities.removeAll { $0.id == id }
            }
        }
    }
}

struct SyncActivity: Identifiable {
    let id: String
    var description: String
    let type: ActivityType
    let startedAt: Date
    var isComplete = false
    var success = true

    enum ActivityType {
        case sync, upload, download, push
    }

    var icon: String {
        if isComplete { return success ? "checkmark.circle.fill" : "exclamationmark.circle.fill" }
        switch type {
        case .sync: return "arrow.triangle.2.circlepath"
        case .upload: return "arrow.up.circle"
        case .download: return "arrow.down.circle"
        case .push: return "icloud.and.arrow.up"
        }
    }
}

// MARK: - Sync Overlay View (placed once in app root)

struct SyncOverlayView: View {
    @ObservedObject var monitor = SyncActivityMonitor.shared

    var body: some View {
        VStack {
            if let activity = monitor.currentActivity {
                HStack(spacing: 10) {
                    if activity.isComplete {
                        Image(systemName: activity.icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(activity.success ? Color.clear_ : Color.flagged)
                    } else {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(.primary)
                    }

                    Text(activity.description)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)

                    if !activity.isComplete {
                        // Subtle elapsed time
                        TimelineView(.periodic(from: activity.startedAt, by: 1)) { context in
                            let elapsed = Int(context.date.timeIntervalSince(activity.startedAt))
                            if elapsed > 2 {
                                Text("\(elapsed)s")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            Spacer()
        }
        .padding(.top, 8)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: monitor.activities.count)
        .allowsHitTesting(false)
    }
}
