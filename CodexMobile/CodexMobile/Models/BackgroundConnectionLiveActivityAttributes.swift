// FILE: BackgroundConnectionLiveActivityAttributes.swift
// Purpose: Shared Live Activity attributes and state mapping for background connection status.
// Layer: Model
// Exports: BackgroundConnectionLiveActivityAttributes, BackgroundConnectionLiveActivityState
// Depends on: ActivityKit, Foundation

import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

#if canImport(ActivityKit)
struct BackgroundConnectionLiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var hostName: String
        var connectedAt: Date
        var isConnected: Bool
    }

    var name: String
}
#endif

struct BackgroundConnectionLiveActivityState: Equatable, Sendable {
    let hostName: String
    let connectedAt: Date
    let isConnected: Bool

    static func make(hostName: String, connectedAt: Date) -> BackgroundConnectionLiveActivityState {
        return BackgroundConnectionLiveActivityState(
            hostName: hostName,
            connectedAt: connectedAt,
            isConnected: true
        )
    }
}

#if canImport(ActivityKit)
extension BackgroundConnectionLiveActivityState {
    var contentState: BackgroundConnectionLiveActivityAttributes.ContentState {
        BackgroundConnectionLiveActivityAttributes.ContentState(
            hostName: hostName,
            connectedAt: connectedAt,
            isConnected: isConnected
        )
    }
}
#endif
