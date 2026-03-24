// FILE: SettingsBackgroundConnectionPresentation.swift
// Purpose: Maps background connection preference plus location permission into concise Settings copy.
// Layer: Model
// Exports: SettingsBackgroundConnectionPresentation
// Depends on: CoreLocation, Foundation

import CoreLocation
import Foundation

struct SettingsBackgroundConnectionPresentation: Equatable, Sendable {
    let title: String
    let detail: String
    let showsOpenSettingsButton: Bool

    static func make(
        isEnabled: Bool,
        authorization: CLAuthorizationStatus,
        isKeepingAlive: Bool
    ) -> SettingsBackgroundConnectionPresentation {
        guard isEnabled else {
            return SettingsBackgroundConnectionPresentation(
                title: "Disabled",
                detail: "Background keepalive is off.",
                showsOpenSettingsButton: false
            )
        }

        switch authorization {
        case .authorizedAlways:
            if isKeepingAlive {
                return SettingsBackgroundConnectionPresentation(
                    title: "Enabled, keeping alive",
                    detail: "Background location is actively keeping your Mac connection alive.",
                    showsOpenSettingsButton: false
                )
            }

            return SettingsBackgroundConnectionPresentation(
                title: "Enabled",
                detail: "Background keepalive is ready for when Remodex moves to background.",
                showsOpenSettingsButton: false
            )

        case .authorizedWhenInUse:
            return SettingsBackgroundConnectionPresentation(
                title: "Enabled, limited",
                detail: "Allow Always Location to keep the connection alive while Remodex is locked or backgrounded.",
                showsOpenSettingsButton: true
            )

        default:
            return SettingsBackgroundConnectionPresentation(
                title: "Permission required",
                detail: "Turn on Always Location in iOS Settings to keep the connection alive in background.",
                showsOpenSettingsButton: true
            )
        }
    }
}
