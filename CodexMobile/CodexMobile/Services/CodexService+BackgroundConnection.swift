// FILE: CodexService+BackgroundConnection.swift
// Purpose: Shares reconnect URL resolution and background reconnect policy for background connection keepalive.
// Layer: Service extension
// Exports: CodexService background-connection helpers
// Depends on: Foundation

import Foundation

extension CodexService: BackgroundConnectionSnapshotControlling {
    func attemptBackgroundReconnectIfNeeded() async {
        guard !isAppInForeground,
              shouldAutoReconnectOnForeground,
              hasReconnectCandidate,
              !isConnected,
              !isConnecting else {
            return
        }

        guard let fullURL = await preferredReconnectURLForAutoReconnect() else {
            shouldAutoReconnectOnForeground = false
            connectionRecoveryState = .idle
            return
        }

        do {
            connectionRecoveryState = .retrying(attempt: 1, message: "Reconnecting...")
            try await connect(serverURL: fullURL, token: "", role: "iphone")
            connectionRecoveryState = .idle
            lastErrorMessage = nil
            shouldAutoReconnectOnForeground = false
        } catch {
            if secureConnectionState == .rePairRequired {
                connectionRecoveryState = .idle
                shouldAutoReconnectOnForeground = false
                if lastErrorMessage?.isEmpty ?? true {
                    lastErrorMessage = userFacingConnectFailureMessage(error)
                }
                return
            }

            let isRetryable = isRecoverableTransientConnectionError(error)
                || isBenignBackgroundDisconnect(error)
                || isRetryableSavedSessionConnectError(error)

            guard isRetryable else {
                connectionRecoveryState = .idle
                shouldAutoReconnectOnForeground = false
                lastErrorMessage = userFacingConnectFailureMessage(error)
                return
            }

            lastErrorMessage = nil
            connectionRecoveryState = .retrying(
                attempt: 1,
                message: recoveryStatusMessage(for: error)
            )
        }
    }

    func preferredReconnectURLForAutoReconnect() async -> String? {
        switch await trustedReconnectResolutionForAutoReconnect() {
        case .use(let resolvedURL):
            return resolvedURL
        case .fallbackToSaved:
            return savedReconnectURLForAutoReconnect()
        case .stop:
            return nil
        }
    }
}

private extension CodexService {
    enum ReconnectURLResolution {
        case use(String)
        case fallbackToSaved
        case stop
    }

    func trustedReconnectResolutionForAutoReconnect() async -> ReconnectURLResolution {
        guard hasTrustedMacReconnectCandidate else {
            return .fallbackToSaved
        }

        do {
            guard let trustedReconnectURL = try await resolvedTrustedReconnectURLForAutoReconnect() else {
                return .fallbackToSaved
            }
            return .use(trustedReconnectURL)
        } catch let error as CodexTrustedSessionResolveError {
            return trustedReconnectResolutionForAutoReconnect(for: error)
        } catch {
            if !hasSavedRelaySession {
                lastErrorMessage = error.localizedDescription
            }
            return .fallbackToSaved
        }
    }

    func resolvedTrustedReconnectURLForAutoReconnect() async throws -> String? {
        let resolved = try await resolveTrustedMacSession()
        guard let relayURL = normalizedRelayURL else {
            return nil
        }
        return "\(relayURL)/\(resolved.sessionId)"
    }

    func trustedReconnectResolutionForAutoReconnect(
        for error: CodexTrustedSessionResolveError
    ) -> ReconnectURLResolution {
        switch error {
        case .unsupportedRelay:
            if !hasSavedRelaySession {
                connectionRecoveryState = .idle
                lastErrorMessage = "This relay needs a fresh QR scan before trusted reconnect is available."
                return .stop
            }
            return .fallbackToSaved
        case .macOffline(let message):
            if hasSavedRelaySession {
                lastErrorMessage = nil
                return .fallbackToSaved
            }
            connectionRecoveryState = .idle
            lastErrorMessage = message
            return .stop
        case .rePairRequired(let message):
            connectionRecoveryState = .idle
            shouldAutoReconnectOnForeground = false
            lastErrorMessage = message
            return .stop
        case .noTrustedMac:
            return .fallbackToSaved
        case .invalidResponse(let message), .network(let message):
            if !hasSavedRelaySession {
                lastErrorMessage = message
            }
            return .fallbackToSaved
        }
    }

    func savedReconnectURLForAutoReconnect() -> String? {
        guard let sessionId = normalizedRelaySessionId,
              let relayURL = normalizedRelayURL else {
            return nil
        }
        return "\(relayURL)/\(sessionId)"
    }
}
