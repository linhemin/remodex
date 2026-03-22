// FILE: RelayDiscoveryModels.swift
// Purpose: Shared discovery candidate models for LAN-first relay routing.
// Layer: Service support
// Exports: RelayDiscoverySource, RelayDiscoveryCandidate
// Depends on: Foundation

import Foundation

enum RelayDiscoverySource: Int, Sendable {
    case bonjour = 0
    case overlay = 1
    case savedRelay = 2
    case remoteResolve = 3
}

struct RelayDiscoveryCandidate: Equatable, Sendable {
    let source: RelayDiscoverySource
    let url: URL
    let macDeviceId: String?
    let discoveredAt: Date?
}

extension RelayDiscoveryCandidate {
    static func bonjour(
        _ rawURL: String,
        macDeviceId: String? = nil,
        discoveredAt: Date? = nil
    ) -> RelayDiscoveryCandidate {
        candidate(.bonjour, rawURL: rawURL, macDeviceId: macDeviceId, discoveredAt: discoveredAt)
    }

    static func overlay(
        _ rawURL: String,
        macDeviceId: String? = nil,
        discoveredAt: Date? = nil
    ) -> RelayDiscoveryCandidate {
        candidate(.overlay, rawURL: rawURL, macDeviceId: macDeviceId, discoveredAt: discoveredAt)
    }

    static func savedRelay(
        _ rawURL: String,
        macDeviceId: String? = nil,
        discoveredAt: Date? = nil
    ) -> RelayDiscoveryCandidate {
        candidate(.savedRelay, rawURL: rawURL, macDeviceId: macDeviceId, discoveredAt: discoveredAt)
    }

    static func remoteResolve(
        _ rawURL: String,
        macDeviceId: String? = nil,
        discoveredAt: Date? = nil
    ) -> RelayDiscoveryCandidate {
        candidate(.remoteResolve, rawURL: rawURL, macDeviceId: macDeviceId, discoveredAt: discoveredAt)
    }

    private static func candidate(
        _ source: RelayDiscoverySource,
        rawURL: String,
        macDeviceId: String?,
        discoveredAt: Date?
    ) -> RelayDiscoveryCandidate {
        guard let url = RelayDiscoveryCoordinator.normalizedRelayURL(from: rawURL) else {
            preconditionFailure("Invalid relay discovery URL: \(rawURL)")
        }

        return RelayDiscoveryCandidate(
            source: source,
            url: url,
            macDeviceId: macDeviceId,
            discoveredAt: discoveredAt
        )
    }
}
