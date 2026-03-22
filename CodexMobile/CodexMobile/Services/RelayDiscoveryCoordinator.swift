// FILE: RelayDiscoveryCoordinator.swift
// Purpose: Ranks LAN-first relay candidates before reconnect falls back to saved or remote endpoints.
// Layer: Service
// Exports: RelayDiscoveryCoordinator
// Depends on: Foundation, RelayDiscoveryModels

import Foundation

enum RelayDiscoveryCoordinator {
    nonisolated static func rankCandidates(
        _ candidates: [RelayDiscoveryCandidate],
        preferredMacDeviceId: String? = nil
    ) -> [RelayDiscoveryCandidate] {
        let filtered = candidates
            .compactMap(normalizedCandidate)
            .filter { candidate in
                guard let preferredMacDeviceId else {
                    return true
                }

                guard let macDeviceId = candidate.macDeviceId else {
                    return true
                }

                return macDeviceId == preferredMacDeviceId
            }

        let sorted = filtered.sorted(by: compareCandidates)
        var deduped: [RelayDiscoveryCandidate] = []
        var seenURLStrings: Set<String> = []

        for candidate in sorted {
            let key = candidate.url.absoluteString
            guard seenURLStrings.insert(key).inserted else {
                continue
            }
            deduped.append(candidate)
        }

        return deduped
    }

    nonisolated static func normalizedRelayURL(from rawURL: String) -> URL? {
        guard let url = URL(string: rawURL) else {
            return nil
        }
        return normalizedRelayURL(from: url)
    }

    nonisolated static func normalizedRelayURL(from url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        components.fragment = nil
        components.query = nil

        let normalizedPath = normalizedRelayPath(components.path)
        if normalizedPath == "/" {
            components.path = ""
        } else {
            components.path = normalizedPath
        }

        return components.url
    }

    private nonisolated static func normalizedCandidate(_ candidate: RelayDiscoveryCandidate) -> RelayDiscoveryCandidate? {
        guard let normalizedURL = normalizedRelayURL(from: candidate.url) else {
            return nil
        }

        return RelayDiscoveryCandidate(
            source: candidate.source,
            url: normalizedURL,
            macDeviceId: candidate.macDeviceId,
            discoveredAt: candidate.discoveredAt
        )
    }

    private nonisolated static func compareCandidates(_ lhs: RelayDiscoveryCandidate, _ rhs: RelayDiscoveryCandidate) -> Bool {
        if lhs.source.rawValue != rhs.source.rawValue {
            return lhs.source.rawValue < rhs.source.rawValue
        }

        let lhsDiscoveredAt = lhs.discoveredAt ?? .distantPast
        let rhsDiscoveredAt = rhs.discoveredAt ?? .distantPast
        if lhsDiscoveredAt != rhsDiscoveredAt {
            return lhsDiscoveredAt > rhsDiscoveredAt
        }

        return lhs.url.absoluteString < rhs.url.absoluteString
    }

    private nonisolated static func normalizedRelayPath(_ path: String) -> String {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !parts.isEmpty else {
            return "/"
        }

        if let relayIndex = parts.firstIndex(of: "relay") {
            return "/" + parts[...relayIndex].joined(separator: "/")
        }

        return "/" + parts.joined(separator: "/")
    }
}
