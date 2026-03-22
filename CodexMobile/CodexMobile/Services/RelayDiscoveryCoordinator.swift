// FILE: RelayDiscoveryCoordinator.swift
// Purpose: Ranks LAN-first relay candidates before reconnect falls back to saved or remote endpoints.
// Layer: Service
// Exports: RelayDiscoveryCoordinator
// Depends on: Foundation, RelayDiscoveryModels

import Foundation

struct RelayBonjourResolvedService: Equatable, Sendable {
    let name: String
    let hostName: String
    let port: Int
    let txtRecord: [String: String]
}

enum RelayDiscoveryCoordinator {
    nonisolated static func bonjourCandidate(from service: RelayBonjourResolvedService) -> RelayDiscoveryCandidate? {
        let normalizedHost = normalizedBonjourHost(service.hostName)
        guard !normalizedHost.isEmpty, service.port > 0 else {
            return nil
        }

        let relayPath = service.txtRecord["relayPath"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? service.txtRecord["relayPath"]!
            : "/relay"
        let macDeviceId = service.txtRecord["macDeviceId"]?.trimmingCharacters(in: .whitespacesAndNewlines)

        var components = URLComponents()
        components.scheme = "ws"
        components.host = normalizedHost
        components.port = service.port
        components.path = relayPath

        guard let url = components.url else {
            return nil
        }

        return RelayDiscoveryCandidate(
            source: .bonjour,
            url: url,
            macDeviceId: macDeviceId?.isEmpty == false ? macDeviceId : nil,
            discoveredAt: nil
        )
    }

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

    private nonisolated static func normalizedBonjourHost(_ hostName: String) -> String {
        let trimmed = hostName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }

        if trimmed.hasSuffix(".") {
            return String(trimmed.dropLast())
        }

        return trimmed
    }
}

@MainActor
final class RelayBonjourDiscoveryBrowser: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    private let serviceType = "_remodex._tcp."
    private let serviceDomain = "local."

    private var browser: NetServiceBrowser?
    private var continuation: CheckedContinuation<[RelayDiscoveryCandidate], Never>?
    private var timeoutTask: Task<Void, Never>?
    private var discoveredServices: [String: RelayBonjourResolvedService] = [:]
    private var resolvingServices: [String: NetService] = [:]
    private var isFinished = false

    func discover(timeoutNanoseconds: UInt64 = 1_000_000_000) async -> [RelayDiscoveryCandidate] {
        await withCheckedContinuation { continuation in
            self.continuation = continuation

            let browser = NetServiceBrowser()
            browser.delegate = self
            self.browser = browser
            browser.searchForServices(ofType: serviceType, inDomain: serviceDomain)

            timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                self?.finish()
            }
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        let key = serviceKey(for: service)
        resolvingServices[key] = service
        service.delegate = self
        service.resolve(withTimeout: 1.0)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        let key = serviceKey(for: service)
        resolvingServices.removeValue(forKey: key)?.stop()
        discoveredServices.removeValue(forKey: key)
    }

    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        finish()
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        finish()
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        let key = serviceKey(for: sender)
        resolvingServices[key] = sender

        guard let hostName = sender.hostName, sender.port > 0 else {
            return
        }

        discoveredServices[key] = RelayBonjourResolvedService(
            name: sender.name,
            hostName: hostName,
            port: sender.port,
            txtRecord: decodeTXTRecord(sender.txtRecordData())
        )
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        resolvingServices.removeValue(forKey: serviceKey(for: sender))
    }
}

private extension RelayBonjourDiscoveryBrowser {
    func finish() {
        guard !isFinished else {
            return
        }
        isFinished = true

        timeoutTask?.cancel()
        timeoutTask = nil

        browser?.stop()
        browser = nil

        for service in resolvingServices.values {
            service.stop()
        }
        resolvingServices.removeAll()

        let now = Date()
        let candidates = discoveredServices.values
            .compactMap(RelayDiscoveryCoordinator.bonjourCandidate(from:))
            .map { candidate in
                RelayDiscoveryCandidate(
                    source: candidate.source,
                    url: candidate.url,
                    macDeviceId: candidate.macDeviceId,
                    discoveredAt: now
                )
            }

        discoveredServices.removeAll()
        continuation?.resume(returning: candidates)
        continuation = nil
    }

    func serviceKey(for service: NetService) -> String {
        "\(service.name)|\(service.type)|\(service.domain)"
    }

    func decodeTXTRecord(_ data: Data?) -> [String: String] {
        guard let data else {
            return [:]
        }

        return NetService.dictionary(fromTXTRecord: data).reduce(into: [:]) { partialResult, item in
            guard let value = String(data: item.value, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else {
                return
            }
            partialResult[item.key] = value
        }
    }
}
