// FILE: NetworkReachabilityMonitor.swift
// Purpose: Emits a lightweight token whenever iOS regains a usable network path for reconnect work.
// Layer: Service support
// Exports: NetworkReachabilityMonitor
// Depends on: Observation, Network

import Foundation
import Network
import Observation

@MainActor
@Observable
final class NetworkReachabilityMonitor {
    private let monitor: NWPathMonitor
    private let queue: DispatchQueue
    private var lastSatisfiedSignature: String?

    private(set) var satisfiedChangeToken = 0
    private(set) var prefersLocalNetwork = false

    /// Called directly on MainActor when the network path changes, bypassing
    /// SwiftUI's rendering cycle so reconnect can preempt in-flight sync tasks.
    @ObservationIgnored var onSignificantChange: ((_ prefersLocalNetwork: Bool) -> Void)?

    init(
        monitor: NWPathMonitor = NWPathMonitor(),
        queue: DispatchQueue = DispatchQueue(label: "remodex.network-reachability")
    ) {
        self.monitor = monitor
        self.queue = queue
        self.monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.handlePathUpdate(path)
            }
        }
        self.monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}

private extension NetworkReachabilityMonitor {
    func handlePathUpdate(_ path: NWPath) {
        guard path.status == .satisfied else {
            lastSatisfiedSignature = nil
            prefersLocalNetwork = false
            return
        }

        prefersLocalNetwork = path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet)
        let signature = pathSignature(path)
        guard signature != lastSatisfiedSignature else {
            return
        }

        lastSatisfiedSignature = signature
        satisfiedChangeToken += 1
        onSignificantChange?(prefersLocalNetwork)
    }

    func pathSignature(_ path: NWPath) -> String {
        var components: [String] = []
        if path.usesInterfaceType(.wifi) {
            components.append("wifi")
        }
        if path.usesInterfaceType(.wiredEthernet) {
            components.append("ethernet")
        }
        if path.usesInterfaceType(.cellular) {
            components.append("cellular")
        }
        if path.usesInterfaceType(.other) {
            components.append("other")
        }
        components.append(path.isExpensive ? "expensive" : "unmetered")
        components.append(path.isConstrained ? "constrained" : "unconstrained")

        if components.isEmpty {
            components.append("unknown")
        }

        return components.joined(separator: ",")
    }
}
