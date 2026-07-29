// HermesAgentLiveActivity.swift
// Lock-screen + Dynamic Island presentation of a running Hermes agent session.
// Content state comes from AgentActivityAttributes in the shared package; the host
// app drives updates from the harness WebSocket.

import ActivityKit
import HermesShared
import SwiftUI
import WidgetKit

struct HermesAgentLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AgentActivityAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    StatusGlyph(status: context.state.status)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ProgressRing(state: context.state)
                        .frame(width: 40, height: 40)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.title)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(context.state.currentTask ?? context.attributes.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let action = context.state.currentAction, !action.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.right.2")
                                .font(.caption2)
                                .foregroundStyle(accent(context.state.status))
                            Text(action)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .padding(.top, 2)
                    }
                }
            } compactLeading: {
                StatusGlyph(status: context.state.status)
            } compactTrailing: {
                Text("\(context.state.completedCount)/\(context.state.totalCount)")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(accent(context.state.status))
            } minimal: {
                StatusGlyph(status: context.state.status)
            }
            .keylineTint(accent(context.state.status))
        }
    }
}

// MARK: - Lock screen

private struct LockScreenView: View {
    let context: ActivityViewContext<AgentActivityAttributes>

    var body: some View {
        let state = context.state
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                StatusGlyph(status: state.status)
                Text(context.attributes.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(state.status.displayName)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(accent(state.status).opacity(0.22), in: Capsule())
                    .foregroundStyle(accent(state.status))
            }

            Text(state.currentTask ?? context.attributes.title)
                .font(.headline)
                .lineLimit(2)

            if let action = state.currentAction, !action.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right.2")
                        .font(.caption2)
                        .foregroundStyle(accent(state.status))
                    Text(action)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            HStack(spacing: 10) {
                ProgressView(value: state.progress)
                    .progressViewStyle(.linear)
                    .tint(accent(state.status))
                Text("\(state.completedCount)/\(state.totalCount)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .foregroundStyle(.white)
    }
}

// MARK: - Pieces

private struct StatusGlyph: View {
    let status: AgentRunStatus

    var body: some View {
        Image(systemName: status.systemImage)
            .font(.callout.weight(.semibold))
            .foregroundStyle(accent(status))
            .symbolEffect(.pulse, options: .repeating, isActive: status == .working)
    }
}

private struct ProgressRing: View {
    let state: AgentActivityAttributes.ContentState

    var body: some View {
        ZStack {
            Circle()
                .stroke(accent(state.status).opacity(0.25), lineWidth: 4)
            Circle()
                .trim(from: 0, to: max(0.02, state.progress))
                .stroke(accent(state.status), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(state.completedCount)")
                .font(.caption2.monospacedDigit().weight(.bold))
        }
    }
}

private func accent(_ status: AgentRunStatus) -> Color {
    Color(hexString: status.accentHex) ?? .blue
}

private extension Color {
    init?(hexString: String) {
        var hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt64(hex, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
