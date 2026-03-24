// FILE: RemodexBackgroundConnectionWidget.swift
// Purpose: Renders the background connection Live Activity and Dynamic Island UI.
// Layer: Extension
// Exports: RemodexBackgroundConnectionWidget
// Depends on: ActivityKit, SwiftUI, WidgetKit

import ActivityKit
import SwiftUI
import WidgetKit

struct RemodexBackgroundConnectionWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BackgroundConnectionLiveActivityAttributes.self) { context in
            HStack(spacing: 10) {
                Image(systemName: "bolt.horizontal.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.hostName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(context.state.connectedAt, style: .timer)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(14)
            .background(Color(.systemBackground))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    HStack(spacing: 8) {
                        Image(systemName: "bolt.horizontal.circle.fill")
                            .foregroundStyle(.green)

                        Text(context.state.hostName)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)

                        Spacer()

                        Text(context.state.connectedAt, style: .timer)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Image(systemName: "bolt.horizontal.circle.fill")
                    .foregroundStyle(.green)
            } compactTrailing: {
                Text(context.state.connectedAt, style: .timer)
                    .font(.caption2.monospacedDigit())
            } minimal: {
                Image(systemName: "bolt.horizontal.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }
}
