// FILE: ContentViewModel.swift
// Purpose: Owns non-visual orchestration logic for the root screen (connection, relay pairing, sync throttling).
// Layer: ViewModel
// Exports: ContentViewModel
// Depends on: Foundation, Observation, CodexService, SecureStore

import Foundation
import Observation

@MainActor
@Observable
final class ContentViewModel {
    private var hasAttemptedInitialAutoConnect = false
    private var lastSidebarOpenSyncAt: Date = .distantPast
    private let autoReconnectBackoffNanoseconds: [UInt64] = [1_000_000_000, 3_000_000_000]
    private let lanPromotionCooldown: TimeInterval = 15
    private(set) var isRunningAutoReconnect = false
    private(set) var isRunningLANPromotion = false
    private var lastLANPromotionAttemptAt: Date = .distantPast

    @ObservationIgnored var nowProvider: () -> Date = Date.init
    @ObservationIgnored var connectOverride: ((CodexService, String) async throws -> Void)?
    @ObservationIgnored var disconnectOverride: ((CodexService, Bool) async -> Void)?

    var isAttemptingAutoReconnect: Bool {
        isRunningAutoReconnect
    }

    // Throttles sidebar-open sync requests to avoid redundant thread refresh churn.
    func shouldRequestSidebarFreshSync(isConnected: Bool) -> Bool {
        guard isConnected else {
            return false
        }

        let now = Date()
        guard now.timeIntervalSince(lastSidebarOpenSyncAt) >= 0.8 else {
            return false
        }

        lastSidebarOpenSyncAt = now
        return true
    }

    // Connects to the relay WebSocket using a scanned QR code payload.
    func connectToRelay(pairingPayload: CodexPairingQRPayload, codex: CodexService) async {
        await stopAutoReconnectForManualScan(codex: codex)
        let fullURL = "\(pairingPayload.relay)/\(pairingPayload.sessionId)"
        print("[PAIRING] QR scanned — relay=\(pairingPayload.relay) session=\(pairingPayload.sessionId)")
        print("[PAIRING] full URL=\(fullURL)")
        codex.rememberRelayPairing(pairingPayload)

        do {
            print("[PAIRING] starting connectWithAutoRecovery")
            try await connectWithAutoRecovery(
                codex: codex,
                serverURL: fullURL,
                performAutoRetry: true
            )
            print("[PAIRING] connected OK")
        } catch {
            print("[PAIRING] connect failed: \(error)")
            if codex.lastErrorMessage?.isEmpty ?? true {
                codex.lastErrorMessage = codex.userFacingConnectFailureMessage(error)
            }
        }
    }

    // Connects or disconnects the relay.
    func toggleConnection(codex: CodexService) async {
        guard !codex.isConnecting, !isRunningAutoReconnect else {
            return
        }

        if codex.isConnected {
            await codex.disconnect()
            codex.clearSavedRelaySession()
            return
        }

        guard let fullURL = await preferredReconnectURL(codex: codex) else {
            return
        }
        do {
            try await connectWithAutoRecovery(
                codex: codex,
                serverURL: fullURL,
                performAutoRetry: true
            )
        } catch {
            if codex.lastErrorMessage?.isEmpty ?? true {
                codex.lastErrorMessage = codex.userFacingConnectFailureMessage(error)
            }
        }
    }

    // Lets the manual QR flow take over instead of competing with the foreground reconnect loop.
    func stopAutoReconnectForManualScan(codex: CodexService) async {
        codex.shouldAutoReconnectOnForeground = false
        codex.connectionRecoveryState = .idle
        codex.lastErrorMessage = nil

        // Cancel any in-flight reconnect so the scanner can appear immediately instead of waiting
        // for a stalled handshake to time out on its own.
        if codex.isConnecting || codex.isConnected {
            await codex.disconnect()
        }

        while isRunningAutoReconnect || codex.isConnecting {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    // Attempts one automatic connection on app launch using saved relay session.
    func attemptAutoConnectOnLaunchIfNeeded(codex: CodexService) async {
        guard !hasAttemptedInitialAutoConnect else {
            return
        }
        hasAttemptedInitialAutoConnect = true

        guard !codex.isConnected, !codex.isConnecting else {
            return
        }

        guard let fullURL = await preferredReconnectURL(codex: codex) else {
            return
        }

        do {
            try await connectWithAutoRecovery(
                codex: codex,
                serverURL: fullURL,
                performAutoRetry: true
            )
        } catch {
            // Keep the saved pairing so temporary Mac/relay outages can recover on the next retry.
        }
    }

    // Reconnects after benign background disconnects.
    func attemptAutoReconnectOnForegroundIfNeeded(
        codex: CodexService,
        prefersLocalNetwork: Bool = true,
        excludingRelayURLs: Set<String> = []
    ) async {
        if codex.isConnected {
            return
        }

        guard codex.shouldAutoReconnectOnForeground, !isRunningAutoReconnect else {
            return
        }

        isRunningAutoReconnect = true
        defer { isRunningAutoReconnect = false }

        var attempt = 0
        let maxAttempts = 20
        var excludedRelayURLs = excludingRelayURLs

        // Keep trying while the relay pairing is still valid.
        // This lets network changes recover on their own instead of dropping back to a manual reconnect button.
        while codex.shouldAutoReconnectOnForeground, attempt < maxAttempts {
            guard let fullURL = await reconnectURLForCurrentNetwork(
                codex: codex,
                prefersLocalNetwork: prefersLocalNetwork,
                excludingRelayURLs: excludedRelayURLs
            ) else {
                codex.shouldAutoReconnectOnForeground = false
                codex.connectionRecoveryState = .idle
                return
            }

            if codex.isConnected {
                codex.shouldAutoReconnectOnForeground = false
                codex.connectionRecoveryState = .idle
                codex.lastErrorMessage = nil
                return
            }

            if codex.isConnecting {
                try? await Task.sleep(nanoseconds: 300_000_000)
                continue
            }
            do {
                codex.connectionRecoveryState = .retrying(
                    attempt: max(1, attempt + 1),
                    message: "Reconnecting..."
                )
                try await connect(
                    codex: codex,
                    serverURL: fullURL,
                    allowLANPromotion: false
                )
                codex.connectionRecoveryState = .idle
                codex.lastErrorMessage = nil
                codex.shouldAutoReconnectOnForeground = false
                return
            } catch {
                if let failedRelayURL = reconnectRelayURL(from: fullURL),
                   let failedRelay = URL(string: failedRelayURL),
                   codex.relayHostCategory(for: failedRelay) == .local {
                    excludedRelayURLs.insert(failedRelayURL)
                }

                if codex.secureConnectionState == .rePairRequired {
                    codex.connectionRecoveryState = .idle
                    codex.shouldAutoReconnectOnForeground = false
                    if codex.lastErrorMessage?.isEmpty ?? true {
                        codex.lastErrorMessage = codex.userFacingConnectFailureMessage(error)
                    }
                    return
                }

                let isRetryable = codex.isRecoverableTransientConnectionError(error)
                    || codex.isBenignBackgroundDisconnect(error)
                    || codex.isRetryableSavedSessionConnectError(error)

                guard isRetryable else {
                    codex.connectionRecoveryState = .idle
                    codex.shouldAutoReconnectOnForeground = false
                    codex.lastErrorMessage = codex.userFacingConnectFailureMessage(error)
                    return
                }

                codex.lastErrorMessage = nil
                codex.connectionRecoveryState = .retrying(
                    attempt: attempt + 1,
                    message: codex.recoveryStatusMessage(for: error)
                )

                let backoffIndex = min(attempt, autoReconnectBackoffNanoseconds.count - 1)
                let backoff = autoReconnectBackoffNanoseconds[backoffIndex]
                attempt += 1
                try? await Task.sleep(nanoseconds: backoff)
            }
        }

        // Exhausted all attempts — stop retrying but keep the saved pairing for next foreground cycle.
        if attempt >= maxAttempts {
            codex.shouldAutoReconnectOnForeground = false
            codex.connectionRecoveryState = .idle
            codex.lastErrorMessage = "Could not reconnect. Tap Reconnect to try again."
        }
    }
}

extension ContentViewModel {
    private enum ReconnectURLResolution {
        case use(String)
        case fallbackToSaved
        case stop
    }

    func connect(codex: CodexService, serverURL: String) async throws {
        try await connect(
            codex: codex,
            serverURL: serverURL,
            allowLANPromotion: true
        )
    }

    func connectWithAutoRecovery(
        codex: CodexService,
        serverURL: String,
        performAutoRetry: Bool
    ) async throws {
        guard !isRunningAutoReconnect else {
            return
        }

        isRunningAutoReconnect = true
        defer { isRunningAutoReconnect = false }

        let maxAttemptIndex = performAutoRetry ? autoReconnectBackoffNanoseconds.count : 0
        var lastError: Error?

        for attemptIndex in 0...maxAttemptIndex {
            if attemptIndex > 0 {
                codex.connectionRecoveryState = .retrying(
                    attempt: attemptIndex,
                    message: "Connection timed out. Retrying..."
                )
            }

            do {
                try await connect(codex: codex, serverURL: serverURL)
                codex.connectionRecoveryState = .idle
                codex.lastErrorMessage = nil
                codex.shouldAutoReconnectOnForeground = false
                return
            } catch {
                lastError = error
                if codex.secureConnectionState == .rePairRequired {
                    codex.connectionRecoveryState = .idle
                    codex.shouldAutoReconnectOnForeground = false
                    if codex.lastErrorMessage?.isEmpty ?? true {
                        codex.lastErrorMessage = codex.userFacingConnectFailureMessage(error)
                    }
                    throw error
                }

                let isRetryable = codex.isRecoverableTransientConnectionError(error)
                    || codex.isBenignBackgroundDisconnect(error)
                    || codex.isRetryableSavedSessionConnectError(error)

                guard performAutoRetry,
                      isRetryable,
                      attemptIndex < autoReconnectBackoffNanoseconds.count else {
                    codex.connectionRecoveryState = .idle
                    codex.shouldAutoReconnectOnForeground = false
                    codex.lastErrorMessage = codex.userFacingConnectFailureMessage(error)
                    throw error
                }

                codex.lastErrorMessage = nil
                codex.connectionRecoveryState = .retrying(
                    attempt: attemptIndex + 1,
                    message: codex.recoveryStatusMessage(for: error)
                )
                try? await Task.sleep(nanoseconds: autoReconnectBackoffNanoseconds[attemptIndex])
            }
        }

        if let lastError {
            codex.connectionRecoveryState = .idle
            codex.shouldAutoReconnectOnForeground = false
            codex.lastErrorMessage = codex.userFacingConnectFailureMessage(lastError)
            throw lastError
        }
    }

    func attemptLANPromotionIfNeeded(codex: CodexService) async {
        guard shouldAttemptLANPromotion(codex: codex) else {
            return
        }

        guard let currentRelayURL = codex.normalizedRelayURL,
              let currentReconnectURL = codex.buildReconnectURL(baseRelayURL: currentRelayURL),
              let targetMacDeviceID = codex.normalizedRelayMacDeviceId ?? codex.preferredTrustedMacDeviceId else {
            return
        }

        isRunningLANPromotion = true
        lastLANPromotionAttemptAt = nowProvider()
        defer { isRunningLANPromotion = false }

        let bonjourCandidates = RelayDiscoveryCoordinator.rankCandidates(
            await codex.discoverBonjourReconnectCandidates().filter {
                $0.source == .bonjour && $0.macDeviceId == targetMacDeviceID
            },
            preferredMacDeviceId: targetMacDeviceID
        )

        guard let candidate = bonjourCandidates.first(where: { candidate in
            codex.relayHostCategory(for: candidate.url) == .local
                && RelayDiscoveryCoordinator.normalizedRelayURL(from: candidate.url)?.absoluteString != currentRelayURL
        }),
            let promotedReconnectURL = await lanPromotionReconnectURL(
                codex: codex,
                candidateRelayURL: candidate.url.absoluteString
            ) else {
            return
        }

        await disconnect(codex: codex, preserveReconnectIntent: true)

        do {
            try await connect(
                codex: codex,
                serverURL: promotedReconnectURL,
                allowLANPromotion: false
            )
        } catch {
            await recoverFromFailedLANPromotion(
                codex: codex,
                currentReconnectURL: currentReconnectURL,
                failedPromotionRelayURL: candidate.url.absoluteString
            )
        }
    }

    func handleNetworkReachabilityRestored(codex: CodexService) async {
        await handleNetworkReachabilityChange(codex: codex, prefersLocalNetwork: true)
    }

    func handleNetworkReachabilityChange(
        codex: CodexService,
        prefersLocalNetwork: Bool
    ) async {
        // Show switching status immediately so the user sees instant feedback.
        codex.connectionRecoveryState = .retrying(attempt: 0, message: "Switching network...")

        // Network changes are preemptive: tear down any existing connection AND any
        // in-flight reconnect loop so we can restart with the correct network preference.
        if codex.isConnected || codex.isConnecting || isRunningAutoReconnect {
            // Signal the running reconnect loop to exit on its next iteration.
            codex.shouldAutoReconnectOnForeground = false
            await disconnect(codex: codex, preserveReconnectIntent: false)
            // Wait briefly for the reconnect loop to observe the flag and exit.
            var waitCount = 0
            while isRunningAutoReconnect && waitCount < 15 {
                try? await Task.sleep(nanoseconds: 50_000_000)
                waitCount += 1
            }
        }

        guard codex.hasReconnectCandidate else {
            codex.connectionRecoveryState = .idle
            return
        }

        codex.shouldAutoReconnectOnForeground = true

        await attemptAutoReconnectOnForegroundIfNeeded(
            codex: codex,
            prefersLocalNetwork: prefersLocalNetwork
        )
    }

    // Chooses the best reconnect path: resolve the live trusted-Mac session first, then fall back to the saved QR session.
    func preferredReconnectURL(
        codex: CodexService,
        excludingRelayURLs: Set<String> = []
    ) async -> String? {
        let liveBonjourCandidates = await codex.discoverBonjourReconnectCandidates()

        switch await trustedReconnectResolution(
            codex: codex,
            liveBonjourCandidates: liveBonjourCandidates,
            excludingRelayURLs: excludingRelayURLs
        ) {
        case .use(let resolvedURL):
            return resolvedURL
        case .fallbackToSaved:
            return savedReconnectURL(
                codex: codex,
                liveBonjourCandidates: liveBonjourCandidates,
                excludingRelayURLs: excludingRelayURLs
            )
        case .stop:
            return nil
        }
    }

    // Resolves a trusted-Mac session when possible and tells the caller whether to use, fall back, or stop.
    private func trustedReconnectResolution(
        codex: CodexService,
        liveBonjourCandidates: [RelayDiscoveryCandidate],
        excludingRelayURLs: Set<String>
    ) async -> ReconnectURLResolution {
        guard codex.hasTrustedMacReconnectCandidate || !liveBonjourCandidates.isEmpty else {
            return .fallbackToSaved
        }

        var lastTrustedReconnectError: CodexTrustedSessionResolveError?
        var lastUnexpectedError: Error?

        for candidate in reconnectCandidates(
            codex: codex,
            liveBonjourCandidates: liveBonjourCandidates,
            excludingRelayURLs: excludingRelayURLs
        ) {
            do {
                guard let trustedReconnectURL = try await resolvedTrustedReconnectURL(
                    codex: codex,
                    relayURL: candidate.url.absoluteString
                ) else {
                    continue
                }
                return .use(trustedReconnectURL)
            } catch let error as CodexTrustedSessionResolveError {
                if case .rePairRequired = error {
                    return trustedReconnectResolution(for: error, codex: codex)
                }
                lastTrustedReconnectError = error
            } catch {
                lastUnexpectedError = error
            }
        }

        if let lastTrustedReconnectError {
            return trustedReconnectResolution(for: lastTrustedReconnectError, codex: codex)
        }

        if let lastUnexpectedError {
            if !codex.hasSavedRelaySession {
                codex.lastErrorMessage = lastUnexpectedError.localizedDescription
            }
        }

        return .fallbackToSaved
    }

    // Builds the live reconnect URL after the trusted-session lookup succeeds.
    private func resolvedTrustedReconnectURL(codex: CodexService, relayURL: String) async throws -> String? {
        let resolved = try await codex.resolveTrustedMacSession(via: relayURL)
        guard let relayURL = RelayDiscoveryCoordinator.normalizedRelayURL(from: relayURL)?.absoluteString else {
            return nil
        }
        return "\(relayURL)/\(resolved.sessionId)"
    }

    // Applies trusted-resolve error policy without mixing it into the happy path URL assembly.
    private func trustedReconnectResolution(
        for error: CodexTrustedSessionResolveError,
        codex: CodexService
    ) -> ReconnectURLResolution {
        switch error {
        case .unsupportedRelay:
            if !codex.hasSavedRelaySession {
                codex.connectionRecoveryState = .idle
                codex.lastErrorMessage = "This relay needs a fresh QR scan before trusted reconnect is available."
                return .stop
            }
            return .fallbackToSaved
        case .macOffline(let message):
            if codex.hasSavedRelaySession {
                codex.lastErrorMessage = nil
                return .fallbackToSaved
            }
            codex.connectionRecoveryState = .idle
            codex.lastErrorMessage = message
            return .stop
        case .rePairRequired(let message):
            codex.connectionRecoveryState = .idle
            codex.shouldAutoReconnectOnForeground = false
            codex.lastErrorMessage = message
            return .stop
        case .noTrustedMac:
            return .fallbackToSaved
        case .invalidResponse(let message), .network(let message):
            if !codex.hasSavedRelaySession {
                codex.lastErrorMessage = message
            }
            return .fallbackToSaved
        }
    }

    // Reuses the last QR-resolved session when trusted lookup is unavailable or not yet supported end-to-end.
    private func savedReconnectURL(
        codex: CodexService,
        liveBonjourCandidates: [RelayDiscoveryCandidate],
        excludingRelayURLs: Set<String>
    ) -> String? {
        for candidate in reconnectCandidates(
            codex: codex,
            liveBonjourCandidates: liveBonjourCandidates,
            excludingRelayURLs: excludingRelayURLs
        ) {
            if let fullURL = codex.buildReconnectURL(baseRelayURL: candidate.url.absoluteString) {
                return fullURL
            }
        }

        return nil
    }

    private func connect(
        codex: CodexService,
        serverURL: String,
        allowLANPromotion: Bool
    ) async throws {
        if let connectOverride {
            try await connectOverride(codex, serverURL)
        } else {
            try await codex.connect(
                serverURL: serverURL,
                token: "",
                role: "iphone"
            )
        }

        if allowLANPromotion {
            await attemptLANPromotionIfNeeded(codex: codex)
        }
    }

    private func disconnect(codex: CodexService, preserveReconnectIntent: Bool) async {
        if let disconnectOverride {
            await disconnectOverride(codex, preserveReconnectIntent)
            return
        }

        await codex.disconnect(preserveReconnectIntent: preserveReconnectIntent)
    }

    private func shouldAttemptLANPromotion(codex: CodexService) -> Bool {
        guard codex.isConnected,
              codex.currentConnectionPathStatus == .remoteRelay,
              !isRunningLANPromotion else {
            return false
        }

        return nowProvider().timeIntervalSince(lastLANPromotionAttemptAt) >= lanPromotionCooldown
    }

    private func lanPromotionReconnectURL(
        codex: CodexService,
        candidateRelayURL: String
    ) async -> String? {
        if let trustedReconnectURL = try? await resolvedTrustedReconnectURL(
            codex: codex,
            relayURL: candidateRelayURL
        ) {
            return trustedReconnectURL
        }

        return codex.buildReconnectURL(baseRelayURL: candidateRelayURL)
    }

    private func recoverFromFailedLANPromotion(
        codex: CodexService,
        currentReconnectURL: String,
        failedPromotionRelayURL: String
    ) async {
        do {
            try await connect(
                codex: codex,
                serverURL: currentReconnectURL,
                allowLANPromotion: false
            )
            return
        } catch {
            let excludedRelayURLs = Set(
                [failedPromotionRelayURL].compactMap {
                    RelayDiscoveryCoordinator.normalizedRelayURL(from: $0)?.absoluteString
                }
            )

            guard let refreshedReconnectURL = await preferredReconnectURL(
                codex: codex,
                excludingRelayURLs: excludedRelayURLs
            ),
                  refreshedReconnectURL != currentReconnectURL else {
                codex.shouldAutoReconnectOnForeground = true
                codex.connectionRecoveryState = .retrying(attempt: 0, message: "Reconnecting...")
                return
            }

            do {
                try await connect(
                    codex: codex,
                    serverURL: refreshedReconnectURL,
                    allowLANPromotion: false
                )
            } catch {
                codex.shouldAutoReconnectOnForeground = true
                codex.connectionRecoveryState = .retrying(attempt: 0, message: "Reconnecting...")
            }
        }
    }

    private func reconnectCandidates(
        codex: CodexService,
        liveBonjourCandidates: [RelayDiscoveryCandidate],
        excludingRelayURLs: Set<String>
    ) -> [RelayDiscoveryCandidate] {
        let normalizedExcludedRelayURLs = Set(
            excludingRelayURLs.compactMap {
                RelayDiscoveryCoordinator.normalizedRelayURL(from: $0)?.absoluteString
            }
        )

        guard !normalizedExcludedRelayURLs.isEmpty else {
            return codex.rankReconnectCandidates(liveBonjourCandidates: liveBonjourCandidates)
        }

        return codex.rankReconnectCandidates(liveBonjourCandidates: liveBonjourCandidates).filter { candidate in
            guard let candidateRelayURL = RelayDiscoveryCoordinator.normalizedRelayURL(from: candidate.url)?.absoluteString else {
                return true
            }
            return !normalizedExcludedRelayURLs.contains(candidateRelayURL)
        }
    }

    private func reconnectURLForCurrentNetwork(
        codex: CodexService,
        prefersLocalNetwork: Bool,
        excludingRelayURLs: Set<String> = []
    ) async -> String? {
        // Skip Bonjour discovery entirely on cellular — mDNS cannot resolve .local hostnames
        // outside the local network, so the discovery timeout is wasted time.
        let liveBonjourCandidates: [RelayDiscoveryCandidate]
        if prefersLocalNetwork {
            liveBonjourCandidates = await codex.discoverBonjourReconnectCandidates(
                timeoutNanoseconds: 1_000_000_000
            )
        } else {
            liveBonjourCandidates = []
        }

        if prefersLocalNetwork,
           let liveLocalReconnectURL = await liveBonjourReconnectURL(
            codex: codex,
            liveBonjourCandidates: liveBonjourCandidates,
            excludingRelayURLs: excludingRelayURLs
        ) {
            return liveLocalReconnectURL
        }

        if let savedRemoteRelayReconnectURL = savedRemoteRelayReconnectURL(codex: codex) {
            return savedRemoteRelayReconnectURL
        }

        let excludedLocalRelayURLs = localRelayReconnectURLs(codex: codex).union(excludingRelayURLs)

        return await preferredReconnectURL(
            codex: codex,
            excludingRelayURLs: excludedLocalRelayURLs
        )
    }

    private func currentReconnectURL(codex: CodexService) -> String? {
        guard let currentRelayURL = codex.normalizedRelayURL else {
            return nil
        }
        return codex.buildReconnectURL(baseRelayURL: currentRelayURL)
    }

    private func liveBonjourReconnectURL(
        codex: CodexService,
        liveBonjourCandidates: [RelayDiscoveryCandidate],
        excludingRelayURLs: Set<String>
    ) async -> String? {
        guard let targetMacDeviceID = codex.normalizedRelayMacDeviceId ?? codex.preferredTrustedMacDeviceId else {
            return nil
        }

        let bonjourCandidates = RelayDiscoveryCoordinator.rankCandidates(
            liveBonjourCandidates.filter {
                $0.source == .bonjour && $0.macDeviceId == targetMacDeviceID
            },
            preferredMacDeviceId: targetMacDeviceID
        )

        guard let candidate = bonjourCandidates.first(where: { candidate in
            guard codex.relayHostCategory(for: candidate.url) == .local,
                  let normalizedRelayURL = RelayDiscoveryCoordinator.normalizedRelayURL(from: candidate.url)?
                    .absoluteString else {
                return false
            }
            return !excludingRelayURLs.contains(normalizedRelayURL)
        }) else {
            return nil
        }

        return await lanPromotionReconnectURL(
            codex: codex,
            candidateRelayURL: candidate.url.absoluteString
        ) ?? codex.buildReconnectURL(baseRelayURL: candidate.url.absoluteString)
    }

    private func savedRemoteRelayReconnectURL(codex: CodexService) -> String? {
        // Prefer the in-memory session ID (kept fresh by trusted-session resolve across LAN
        // promotions) over the Keychain value which may be stale from the initial QR scan.
        let savedRemoteSessionID = codex.normalizedRelaySessionId ?? codex.normalizedPersistedRelaySessionId
        let remoteRelayCandidates: [String?] = [
            codex.preferredTrustedMacRecord?.relayURL,
            codex.normalizedRelayURL,
        ]

        for relayURL in remoteRelayCandidates {
            guard let relayURL,
                  let normalizedRelayURL = RelayDiscoveryCoordinator.normalizedRelayURL(from: relayURL),
                  codex.relayHostCategory(for: normalizedRelayURL) == .neither,
                  let savedRemoteSessionID,
                  let reconnectURL = codex.buildReconnectURL(
                    baseRelayURL: normalizedRelayURL.absoluteString,
                    sessionId: savedRemoteSessionID
                  ) else {
                continue
            }
            return reconnectURL
        }

        return nil
    }

    private func localRelayReconnectURLs(codex: CodexService) -> Set<String> {
        let relayURLs = codex.rankReconnectCandidates().compactMap { candidate -> String? in
            guard codex.relayHostCategory(for: candidate.url) == .local else {
                return nil
            }
            return RelayDiscoveryCoordinator.normalizedRelayURL(from: candidate.url)?.absoluteString
        }

        return Set<String>(relayURLs)
    }

    private func reconnectRelayURL(from reconnectURL: String) -> String? {
        RelayDiscoveryCoordinator.normalizedRelayURL(from: reconnectURL)?.absoluteString
    }
}
