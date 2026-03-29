//
//  Expiry_WidgetLiveActivity.swift
//  Expiry Widget
//
//  Live Activity UI for in-progress verification sessions.
//

import ActivityKit
import WidgetKit
import SwiftUI

// Shared attributes — must match the main app's definition
struct VerificationActivityAttributes: ActivityAttributes {
    let subjectName: String
    let vesselName: String
    let checkId: String

    struct ContentState: Codable, Hashable {
        let status: String
        let elapsedMinutes: Int
        let stage: Int
        let totalStages: Int
    }
}

struct VerificationLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: VerificationActivityAttributes.self) { context in
            // Lock Screen / Banner
            HStack(spacing: 12) {
                // Progress indicator
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 3)
                        .frame(width: 40, height: 40)
                    Circle()
                        .trim(from: 0, to: CGFloat(context.state.stage) / CGFloat(max(context.state.totalStages, 1)))
                        .stroke(stageColor(context.state.stage, context.state.totalStages), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 40, height: 40)
                        .rotationEffect(.degrees(-90))
                    Image(systemName: stageIcon(context.state.stage))
                        .font(.system(size: 14))
                        .foregroundStyle(stageColor(context.state.stage, context.state.totalStages))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(context.attributes.subjectName)
                        .font(.system(size: 14, weight: .semibold))
                    Text(context.state.status)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    if context.state.elapsedMinutes > 0 {
                        Text("\(context.state.elapsedMinutes)m elapsed")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                // Stage dots
                HStack(spacing: 4) {
                    ForEach(0..<context.state.totalStages, id: \.self) { i in
                        Circle()
                            .fill(i < context.state.stage ? stageColor(context.state.stage, context.state.totalStages) : Color.secondary.opacity(0.3))
                            .frame(width: 6, height: 6)
                    }
                }
            }
            .padding(16)
            .activityBackgroundTint(Color(white: 0.1))
            .activitySystemActionForegroundColor(.white)

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.shield")
                            .font(.system(size: 14))
                        Text(context.attributes.subjectName)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.stage)/\(context.state.totalStages)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(stageColor(context.state.stage, context.state.totalStages))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        // Progress bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.15)).frame(height: 4)
                                Capsule().fill(stageColor(context.state.stage, context.state.totalStages))
                                    .frame(width: geo.size.width * CGFloat(context.state.stage) / CGFloat(max(context.state.totalStages, 1)), height: 4)
                            }
                        }
                        .frame(height: 4)

                        HStack {
                            Text(context.state.status)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Spacer()
                            if context.state.elapsedMinutes > 0 {
                                Text("\(context.state.elapsedMinutes)m")
                                    .font(.system(size: 10, design: .rounded))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: stageIcon(context.state.stage))
                    .font(.system(size: 12))
                    .foregroundStyle(stageColor(context.state.stage, context.state.totalStages))
            } compactTrailing: {
                Text("\(context.state.stage)/\(context.state.totalStages)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(stageColor(context.state.stage, context.state.totalStages))
            } minimal: {
                Image(systemName: stageIcon(context.state.stage))
                    .font(.system(size: 12))
                    .foregroundStyle(stageColor(context.state.stage, context.state.totalStages))
            }
            .widgetURL(URL(string: "oceancheck://verify/\(context.attributes.checkId)"))
        }
    }
}

// MARK: - Helpers

private func stageIcon(_ stage: Int) -> String {
    switch stage {
    case 0: return "hourglass"
    case 1: return "person.text.rectangle"
    case 2: return "shield.checkered"
    default: return "checkmark.circle.fill"
    }
}

private func stageColor(_ stage: Int, _ total: Int) -> Color {
    if stage >= total { return .green }
    if stage == 0 { return .orange }
    return .blue
}
