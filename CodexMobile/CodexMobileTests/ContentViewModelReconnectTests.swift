// FILE: ContentViewModelReconnectTests.swift
// Purpose: Verifies reconnect URL selection across trusted-session lookup failures and saved-session fallback.
// Layer: Unit Test
// Exports: ContentViewModelReconnectTests
// Depends on: XCTest, Foundation, CodexMobile

import Foundation
import XCTest
@testable import CodexMobile

@MainActor
final class ContentViewModelReconnectTests: XCTestCase {
    private static var retainedServices: [CodexService] = []

    override func setUp() {
        super.setUp()
        clearStoredSecureRelayState()
    }

    override func tearDown() {
        clearStoredSecureRelayState()
        super.tearDown()
    }

    func testPreferredReconnectURLFallsBackToSavedSessionWhenTrustedResolveReportsOffline() async {
        let service = makeService()
        let viewModel = ContentViewModel()
        let macDeviceID = "mac-\(UUID().uuidString)"
        let relayURL = "wss://relay.local/relay"

        service.trustedMacRegistry.records[macDeviceID] = CodexTrustedMacRecord(
            macDeviceId: macDeviceID,
            macIdentityPublicKey: Data(repeating: 9, count: 32).base64EncodedString(),
            lastPairedAt: Date(),
            relayURL: relayURL
        )
        service.lastTrustedMacDeviceId = macDeviceID
        service.relaySessionId = "saved-session"
        service.relayUrl = relayURL
        service.relayMacDeviceId = macDeviceID
        service.lastErrorMessage = "stale error"
        service.trustedSessionResolverOverride = {
            throw CodexTrustedSessionResolveError.macOffline("Your trusted Mac is offline right now.")
        }

        let reconnectURL = await viewModel.preferredReconnectURL(codex: service)

        XCTAssertEqual(reconnectURL, "\(relayURL)/saved-session")
        XCTAssertNil(service.lastErrorMessage)
    }

    func testPreferredReconnectURLStopsWhenTrustedResolveReportsOfflineAndNoSavedSessionExists() async {
        let service = makeService()
        let viewModel = ContentViewModel()
        let macDeviceID = "mac-\(UUID().uuidString)"
        let relayURL = "wss://relay.local/relay"

        service.trustedMacRegistry.records[macDeviceID] = CodexTrustedMacRecord(
            macDeviceId: macDeviceID,
            macIdentityPublicKey: Data(repeating: 10, count: 32).base64EncodedString(),
            lastPairedAt: Date(),
            relayURL: relayURL
        )
        service.lastTrustedMacDeviceId = macDeviceID
        service.trustedSessionResolverOverride = {
            throw CodexTrustedSessionResolveError.macOffline("Your trusted Mac is offline right now.")
        }

        let reconnectURL = await viewModel.preferredReconnectURL(codex: service)

        XCTAssertNil(reconnectURL)
        XCTAssertEqual(service.lastErrorMessage, "Your trusted Mac is offline right now.")
    }

    func testPreferredReconnectURLUsesBonjourCandidateBeforeSavedRelay() async {
        let service = makeService()
        let viewModel = ContentViewModel()
        let macDeviceID = "mac-\(UUID().uuidString)"
        let bonjourRelayURL = "ws://macbook-pro.local:9000/relay"
        let savedRelayURL = "wss://relay.example/relay"
        var attemptedRelayURLs: [String] = []

        service.trustedMacRegistry.records[macDeviceID] = CodexTrustedMacRecord(
            macDeviceId: macDeviceID,
            macIdentityPublicKey: Data(repeating: 11, count: 32).base64EncodedString(),
            lastPairedAt: Date(),
            relayURL: savedRelayURL,
            lastLocalRelayURL: bonjourRelayURL
        )
        service.lastTrustedMacDeviceId = macDeviceID
        service.relaySessionId = "saved-session"
        service.relayUrl = savedRelayURL
        service.relayMacDeviceId = macDeviceID
        service.trustedSessionResolverByRelayURLOverride = { relayURL in
            attemptedRelayURLs.append(relayURL)
            return CodexTrustedSessionResolveResponse(
                ok: true,
                macDeviceId: macDeviceID,
                macIdentityPublicKey: Data(repeating: 12, count: 32).base64EncodedString(),
                displayName: "Desk Mac",
                sessionId: "live-session-1"
            )
        }

        let reconnectURL = await viewModel.preferredReconnectURL(codex: service)

        XCTAssertEqual(attemptedRelayURLs, [bonjourRelayURL])
        XCTAssertEqual(reconnectURL, "\(bonjourRelayURL)/live-session-1")
    }

    func testPreferredReconnectURLUsesLiveBonjourDiscoveryBeforeRememberedLocalRelay() async {
        let service = makeService()
        let viewModel = ContentViewModel()
        let macDeviceID = "mac-\(UUID().uuidString)"
        let liveBonjourRelayURL = "ws://desk-mac.local:9000/relay"
        let rememberedLocalRelayURL = "ws://old-desk-mac.local:9000/relay"
        let savedRelayURL = "wss://relay.example/relay"
        var attemptedRelayURLs: [String] = []

        service.trustedMacRegistry.records[macDeviceID] = CodexTrustedMacRecord(
            macDeviceId: macDeviceID,
            macIdentityPublicKey: Data(repeating: 13, count: 32).base64EncodedString(),
            lastPairedAt: Date(),
            relayURL: savedRelayURL,
            lastLocalRelayURL: rememberedLocalRelayURL
        )
        service.lastTrustedMacDeviceId = macDeviceID
        service.relaySessionId = "saved-session"
        service.relayUrl = savedRelayURL
        service.relayMacDeviceId = macDeviceID
        service.bonjourDiscoveryOverride = {
            [.bonjour(liveBonjourRelayURL, macDeviceId: macDeviceID)]
        }
        service.trustedSessionResolverByRelayURLOverride = { relayURL in
            attemptedRelayURLs.append(relayURL)
            return CodexTrustedSessionResolveResponse(
                ok: true,
                macDeviceId: macDeviceID,
                macIdentityPublicKey: Data(repeating: 14, count: 32).base64EncodedString(),
                displayName: "Desk Mac",
                sessionId: "live-session-2"
            )
        }

        let reconnectURL = await viewModel.preferredReconnectURL(codex: service)

        XCTAssertEqual(attemptedRelayURLs, [liveBonjourRelayURL])
        XCTAssertEqual(reconnectURL, "\(liveBonjourRelayURL)/live-session-2")
    }

    func testAttemptLANPromotionMigratesConnectedRemoteRelayToMatchingBonjourCandidate() async {
        let service = makeService()
        let viewModel = ContentViewModel()
        let macDeviceID = "mac-\(UUID().uuidString)"
        let remoteRelayURL = "wss://relay.example/relay"
        let lanRelayURL = "ws://desk-mac.local:9000/relay"
        var disconnectPreserveFlags: [Bool] = []
        var connectURLs: [String] = []

        service.trustedMacRegistry.records[macDeviceID] = CodexTrustedMacRecord(
            macDeviceId: macDeviceID,
            macIdentityPublicKey: Data(repeating: 15, count: 32).base64EncodedString(),
            lastPairedAt: Date(),
            relayURL: remoteRelayURL
        )
        service.lastTrustedMacDeviceId = macDeviceID
        service.relaySessionId = "saved-session"
        service.relayUrl = remoteRelayURL
        service.relayMacDeviceId = macDeviceID
        service.isConnected = true
        service.bonjourDiscoveryOverride = {
            [.bonjour(lanRelayURL, macDeviceId: macDeviceID)]
        }
        service.trustedSessionResolverByRelayURLOverride = { _ in
            CodexTrustedSessionResolveResponse(
                ok: true,
                macDeviceId: macDeviceID,
                macIdentityPublicKey: Data(repeating: 19, count: 32).base64EncodedString(),
                displayName: "Desk Mac",
                sessionId: "live-session-lan"
            )
        }
        viewModel.disconnectOverride = { codex, preserveReconnectIntent in
            disconnectPreserveFlags.append(preserveReconnectIntent)
            codex.isConnected = false
        }
        viewModel.connectOverride = { codex, serverURL in
            connectURLs.append(serverURL)
            codex.relayUrl = lanRelayURL
            codex.isConnected = true
        }

        await viewModel.attemptLANPromotionIfNeeded(codex: service)

        XCTAssertEqual(disconnectPreserveFlags, [true])
        XCTAssertEqual(connectURLs, ["\(lanRelayURL)/live-session-lan"])
        XCTAssertEqual(service.currentConnectionPathStatus, .lanDirect)
    }

    func testAttemptLANPromotionDoesNothingWhenAlreadyUsingLanDirect() async {
        let service = makeService()
        let viewModel = ContentViewModel()
        let macDeviceID = "mac-\(UUID().uuidString)"
        let lanRelayURL = "ws://desk-mac.local:9000/relay"
        var didDisconnect = false
        var didConnect = false

        service.trustedMacRegistry.records[macDeviceID] = CodexTrustedMacRecord(
            macDeviceId: macDeviceID,
            macIdentityPublicKey: Data(repeating: 16, count: 32).base64EncodedString(),
            lastPairedAt: Date(),
            relayURL: "wss://relay.example/relay"
        )
        service.lastTrustedMacDeviceId = macDeviceID
        service.relaySessionId = "saved-session"
        service.relayUrl = lanRelayURL
        service.relayMacDeviceId = macDeviceID
        service.isConnected = true
        service.bonjourDiscoveryOverride = {
            [.bonjour(lanRelayURL, macDeviceId: macDeviceID)]
        }
        viewModel.disconnectOverride = { _, _ in
            didDisconnect = true
        }
        viewModel.connectOverride = { _, _ in
            didConnect = true
        }

        await viewModel.attemptLANPromotionIfNeeded(codex: service)

        XCTAssertFalse(didDisconnect)
        XCTAssertFalse(didConnect)
    }

    func testAttemptLANPromotionIgnoresBonjourCandidateForDifferentMac() async {
        let service = makeService()
        let viewModel = ContentViewModel()
        let macDeviceID = "mac-\(UUID().uuidString)"
        let otherMacDeviceID = "mac-\(UUID().uuidString)"
        let remoteRelayURL = "wss://relay.example/relay"
        var didDisconnect = false
        var didConnect = false

        service.trustedMacRegistry.records[macDeviceID] = CodexTrustedMacRecord(
            macDeviceId: macDeviceID,
            macIdentityPublicKey: Data(repeating: 17, count: 32).base64EncodedString(),
            lastPairedAt: Date(),
            relayURL: remoteRelayURL
        )
        service.lastTrustedMacDeviceId = macDeviceID
        service.relaySessionId = "saved-session"
        service.relayUrl = remoteRelayURL
        service.relayMacDeviceId = macDeviceID
        service.isConnected = true
        service.bonjourDiscoveryOverride = {
            [.bonjour("ws://other-mac.local:9000/relay", macDeviceId: otherMacDeviceID)]
        }
        viewModel.disconnectOverride = { _, _ in
            didDisconnect = true
        }
        viewModel.connectOverride = { _, _ in
            didConnect = true
        }

        await viewModel.attemptLANPromotionIfNeeded(codex: service)

        XCTAssertFalse(didDisconnect)
        XCTAssertFalse(didConnect)
        XCTAssertEqual(service.currentConnectionPathStatus, .remoteRelay)
    }

    func testAttemptLANPromotionFallsBackToRemoteRelayWhenLanReconnectFails() async {
        let service = makeService()
        let viewModel = ContentViewModel()
        let macDeviceID = "mac-\(UUID().uuidString)"
        let remoteRelayURL = "wss://relay.example/relay"
        let lanRelayURL = "ws://desk-mac.local:9000/relay"
        var connectURLs: [String] = []

        service.trustedMacRegistry.records[macDeviceID] = CodexTrustedMacRecord(
            macDeviceId: macDeviceID,
            macIdentityPublicKey: Data(repeating: 18, count: 32).base64EncodedString(),
            lastPairedAt: Date(),
            relayURL: remoteRelayURL
        )
        service.lastTrustedMacDeviceId = macDeviceID
        service.relaySessionId = "saved-session"
        service.relayUrl = remoteRelayURL
        service.relayMacDeviceId = macDeviceID
        service.isConnected = true
        service.bonjourDiscoveryOverride = {
            [.bonjour(lanRelayURL, macDeviceId: macDeviceID)]
        }
        service.trustedSessionResolverByRelayURLOverride = { _ in
            CodexTrustedSessionResolveResponse(
                ok: true,
                macDeviceId: macDeviceID,
                macIdentityPublicKey: Data(repeating: 20, count: 32).base64EncodedString(),
                displayName: "Desk Mac",
                sessionId: "live-session-lan"
            )
        }
        viewModel.disconnectOverride = { codex, _ in
            codex.isConnected = false
        }
        viewModel.connectOverride = { codex, serverURL in
            connectURLs.append(serverURL)
            if serverURL == "\(lanRelayURL)/live-session-lan" {
                throw CodexServiceError.disconnected
            }
            codex.relayUrl = remoteRelayURL
            codex.isConnected = true
        }

        await viewModel.attemptLANPromotionIfNeeded(codex: service)

        XCTAssertEqual(connectURLs, [
            "\(lanRelayURL)/live-session-lan",
            "\(remoteRelayURL)/saved-session",
        ])
        XCTAssertEqual(service.currentConnectionPathStatus, .remoteRelay)
    }

    func testAttemptLANPromotionFallsBackToFreshReconnectCandidateWhenCachedRemoteSessionFails() async {
        let service = makeService()
        let viewModel = ContentViewModel()
        let macDeviceID = "mac-\(UUID().uuidString)"
        let remoteRelayURL = "wss://relay.example/relay"
        let lanRelayURL = "ws://desk-mac.local:9000/relay"
        var connectURLs: [String] = []

        service.trustedMacRegistry.records[macDeviceID] = CodexTrustedMacRecord(
            macDeviceId: macDeviceID,
            macIdentityPublicKey: Data(repeating: 21, count: 32).base64EncodedString(),
            lastPairedAt: Date(),
            relayURL: remoteRelayURL
        )
        service.lastTrustedMacDeviceId = macDeviceID
        service.relaySessionId = "saved-session"
        service.relayUrl = remoteRelayURL
        service.relayMacDeviceId = macDeviceID
        service.isConnected = true
        service.bonjourDiscoveryOverride = {
            [.bonjour(lanRelayURL, macDeviceId: macDeviceID)]
        }
        service.trustedSessionResolverByRelayURLOverride = { relayURL in
            let sessionId = relayURL == lanRelayURL ? "live-session-lan" : "live-session-remote"
            return CodexTrustedSessionResolveResponse(
                ok: true,
                macDeviceId: macDeviceID,
                macIdentityPublicKey: Data(repeating: 22, count: 32).base64EncodedString(),
                displayName: "Desk Mac",
                sessionId: sessionId
            )
        }
        viewModel.disconnectOverride = { codex, _ in
            codex.isConnected = false
        }
        viewModel.connectOverride = { codex, serverURL in
            connectURLs.append(serverURL)
            if serverURL == "\(lanRelayURL)/live-session-lan"
                || serverURL == "\(remoteRelayURL)/saved-session" {
                throw CodexServiceError.disconnected
            }
            codex.relayUrl = remoteRelayURL
            codex.isConnected = true
        }

        await viewModel.attemptLANPromotionIfNeeded(codex: service)

        XCTAssertEqual(connectURLs, [
            "\(lanRelayURL)/live-session-lan",
            "\(remoteRelayURL)/saved-session",
            "\(remoteRelayURL)/live-session-remote",
        ])
        XCTAssertEqual(service.currentConnectionPathStatus, .remoteRelay)
    }

    func testHandleNetworkReachabilityRestoredReconnectsImmediatelyWhenRecoveryIsPending() async {
        let service = makeService()
        let viewModel = ContentViewModel()
        let macDeviceID = "mac-\(UUID().uuidString)"
        let remoteRelayURL = "wss://relay.example/relay"
        var connectURLs: [String] = []

        service.trustedMacRegistry.records[macDeviceID] = CodexTrustedMacRecord(
            macDeviceId: macDeviceID,
            macIdentityPublicKey: Data(repeating: 23, count: 32).base64EncodedString(),
            lastPairedAt: Date(),
            relayURL: remoteRelayURL
        )
        service.lastTrustedMacDeviceId = macDeviceID
        service.relaySessionId = "saved-session"
        service.relayUrl = remoteRelayURL
        service.relayMacDeviceId = macDeviceID
        service.shouldAutoReconnectOnForeground = true
        service.trustedSessionResolverByRelayURLOverride = { _ in
            CodexTrustedSessionResolveResponse(
                ok: true,
                macDeviceId: macDeviceID,
                macIdentityPublicKey: Data(repeating: 24, count: 32).base64EncodedString(),
                displayName: "Desk Mac",
                sessionId: "live-session-remote"
            )
        }
        viewModel.connectOverride = { codex, serverURL in
            connectURLs.append(serverURL)
            codex.relayUrl = remoteRelayURL
            codex.isConnected = true
        }

        await viewModel.handleNetworkReachabilityRestored(codex: service)

        XCTAssertEqual(connectURLs, ["\(remoteRelayURL)/saved-session"])
        XCTAssertFalse(service.shouldAutoReconnectOnForeground)
        XCTAssertEqual(service.currentConnectionPathStatus, .remoteRelay)
    }

    func testHandleNetworkReachabilityChangeReconnectsImmediatelyWhenOfflineWithReconnectCandidateEvenWithoutForegroundFlag() async {
        let service = makeService()
        let viewModel = ContentViewModel()
        let macDeviceID = "mac-\(UUID().uuidString)"
        let remoteRelayURL = "wss://relay.example/relay"
        var connectURLs: [String] = []

        service.trustedMacRegistry.records[macDeviceID] = CodexTrustedMacRecord(
            macDeviceId: macDeviceID,
            macIdentityPublicKey: Data(repeating: 33, count: 32).base64EncodedString(),
            lastPairedAt: Date(),
            relayURL: remoteRelayURL
        )
        service.lastTrustedMacDeviceId = macDeviceID
        service.relaySessionId = "saved-session"
        service.relayUrl = remoteRelayURL
        service.relayMacDeviceId = macDeviceID
        service.shouldAutoReconnectOnForeground = false
        viewModel.connectOverride = { codex, serverURL in
            connectURLs.append(serverURL)
            codex.relayUrl = remoteRelayURL
            codex.isConnected = true
        }

        await viewModel.handleNetworkReachabilityChange(
            codex: service,
            prefersLocalNetwork: false
        )

        XCTAssertEqual(connectURLs, ["\(remoteRelayURL)/saved-session"])
        XCTAssertFalse(service.shouldAutoReconnectOnForeground)
        XCTAssertEqual(service.currentConnectionPathStatus, .remoteRelay)
    }

    func testHandleNetworkReachabilityRestoredPromotesConnectedRemoteRelayImmediately() async {
        let service = makeService()
        let viewModel = ContentViewModel()
        let macDeviceID = "mac-\(UUID().uuidString)"
        let remoteRelayURL = "wss://relay.example/relay"
        let lanRelayURL = "ws://desk-mac.local:9000/relay"
        var connectURLs: [String] = []

        service.trustedMacRegistry.records[macDeviceID] = CodexTrustedMacRecord(
            macDeviceId: macDeviceID,
            macIdentityPublicKey: Data(repeating: 25, count: 32).base64EncodedString(),
            lastPairedAt: Date(),
            relayURL: remoteRelayURL
        )
        service.lastTrustedMacDeviceId = macDeviceID
        service.relaySessionId = "saved-session"
        service.relayUrl = remoteRelayURL
        service.relayMacDeviceId = macDeviceID
        service.isConnected = true
        service.bonjourDiscoveryOverride = {
            [.bonjour(lanRelayURL, macDeviceId: macDeviceID)]
        }
        service.trustedSessionResolverByRelayURLOverride = { _ in
            CodexTrustedSessionResolveResponse(
                ok: true,
                macDeviceId: macDeviceID,
                macIdentityPublicKey: Data(repeating: 26, count: 32).base64EncodedString(),
                displayName: "Desk Mac",
                sessionId: "live-session-lan"
            )
        }
        viewModel.disconnectOverride = { codex, _ in
            codex.isConnected = false
        }
        viewModel.connectOverride = { codex, serverURL in
            connectURLs.append(serverURL)
            codex.relayUrl = lanRelayURL
            codex.isConnected = true
        }

        await viewModel.handleNetworkReachabilityRestored(codex: service)

        XCTAssertEqual(connectURLs, ["\(lanRelayURL)/live-session-lan"])
        XCTAssertEqual(service.currentConnectionPathStatus, .lanDirect)
    }

    func testHandleNetworkReachabilityChangeReconnectsLanDirectSessionThroughRemoteRelayWhenLocalNetworkIsUnavailable() async {
        let service = makeService()
        let viewModel = ContentViewModel()
        let macDeviceID = "mac-\(UUID().uuidString)"
        let remoteRelayURL = "wss://relay.example/relay"
        let lanRelayURL = "ws://desk-mac.local:9000/relay"
        var connectURLs: [String] = []
        var attemptedRelayURLs: [String] = []

        service.trustedMacRegistry.records[macDeviceID] = CodexTrustedMacRecord(
            macDeviceId: macDeviceID,
            macIdentityPublicKey: Data(repeating: 27, count: 32).base64EncodedString(),
            lastPairedAt: Date(),
            relayURL: remoteRelayURL,
            lastLocalRelayURL: lanRelayURL
        )
        service.lastTrustedMacDeviceId = macDeviceID
        service.relaySessionId = "saved-session"
        service.relayUrl = lanRelayURL
        service.relayMacDeviceId = macDeviceID
        service.isConnected = true
        service.trustedSessionResolverByRelayURLOverride = { relayURL in
            attemptedRelayURLs.append(relayURL)
            return CodexTrustedSessionResolveResponse(
                ok: true,
                macDeviceId: macDeviceID,
                macIdentityPublicKey: Data(repeating: 28, count: 32).base64EncodedString(),
                displayName: "Desk Mac",
                sessionId: relayURL == lanRelayURL ? "live-session-lan" : "live-session-remote"
            )
        }
        viewModel.disconnectOverride = { codex, _ in
            codex.isConnected = false
        }
        viewModel.connectOverride = { codex, serverURL in
            connectURLs.append(serverURL)
            codex.relayUrl = remoteRelayURL
            codex.isConnected = true
        }

        await viewModel.handleNetworkReachabilityChange(
            codex: service,
            prefersLocalNetwork: false
        )

        XCTAssertEqual(attemptedRelayURLs, [])
        XCTAssertEqual(connectURLs, ["\(remoteRelayURL)/saved-session"])
        XCTAssertEqual(service.currentConnectionPathStatus, .remoteRelay)
    }

    func testHandleNetworkReachabilityChangeSkipsRememberedLocalRelayWhenReconnectingWithoutLocalNetwork() async {
        let service = makeService()
        let viewModel = ContentViewModel()
        let macDeviceID = "mac-\(UUID().uuidString)"
        let remoteRelayURL = "wss://relay.example/relay"
        let lanRelayURL = "ws://desk-mac.local:9000/relay"
        var connectURLs: [String] = []
        var attemptedRelayURLs: [String] = []

        service.trustedMacRegistry.records[macDeviceID] = CodexTrustedMacRecord(
            macDeviceId: macDeviceID,
            macIdentityPublicKey: Data(repeating: 29, count: 32).base64EncodedString(),
            lastPairedAt: Date(),
            relayURL: remoteRelayURL,
            lastLocalRelayURL: lanRelayURL
        )
        service.lastTrustedMacDeviceId = macDeviceID
        service.relaySessionId = "saved-session"
        service.relayUrl = remoteRelayURL
        service.relayMacDeviceId = macDeviceID
        service.shouldAutoReconnectOnForeground = true
        service.trustedSessionResolverByRelayURLOverride = { relayURL in
            attemptedRelayURLs.append(relayURL)
            return CodexTrustedSessionResolveResponse(
                ok: true,
                macDeviceId: macDeviceID,
                macIdentityPublicKey: Data(repeating: 30, count: 32).base64EncodedString(),
                displayName: "Desk Mac",
                sessionId: relayURL == lanRelayURL ? "live-session-lan" : "live-session-remote"
            )
        }
        viewModel.connectOverride = { codex, serverURL in
            connectURLs.append(serverURL)
            codex.relayUrl = remoteRelayURL
            codex.isConnected = true
        }

        await viewModel.handleNetworkReachabilityChange(
            codex: service,
            prefersLocalNetwork: false
        )

        XCTAssertEqual(attemptedRelayURLs, [])
        XCTAssertEqual(connectURLs, ["\(remoteRelayURL)/saved-session"])
        XCTAssertEqual(service.currentConnectionPathStatus, .remoteRelay)
    }

    func testHandleNetworkReachabilityChangeUsesCurrentSessionWhenReconnectingViaRemoteRelayAfterLanResolve() async {
        let service = makeService()
        let viewModel = ContentViewModel()
        let macDeviceID = "mac-\(UUID().uuidString)"
        let remoteRelayURL = "wss://relay.example/relay"
        let lanRelayURL = "ws://desk-mac.local:9000/relay"
        var connectURLs: [String] = []

        SecureStore.writeString("saved-session", for: CodexSecureKeys.relaySessionId)
        service.trustedMacRegistry.records[macDeviceID] = CodexTrustedMacRecord(
            macDeviceId: macDeviceID,
            macIdentityPublicKey: Data(repeating: 36, count: 32).base64EncodedString(),
            lastPairedAt: Date(),
            relayURL: remoteRelayURL,
            lastLocalRelayURL: lanRelayURL,
            lastResolvedSessionId: "live-session-lan"
        )
        service.lastTrustedMacDeviceId = macDeviceID
        service.relaySessionId = "live-session-lan"
        service.relayUrl = lanRelayURL
        service.relayMacDeviceId = macDeviceID
        service.shouldAutoReconnectOnForeground = true
        viewModel.connectOverride = { codex, serverURL in
            connectURLs.append(serverURL)
            codex.relayUrl = remoteRelayURL
            codex.isConnected = true
        }

        await viewModel.handleNetworkReachabilityChange(
            codex: service,
            prefersLocalNetwork: false
        )

        // The in-memory session ID (from LAN resolve) is universal and fresher than the
        // Keychain value, so the reconnect URL uses it for the remote relay path.
        XCTAssertEqual(connectURLs, ["\(remoteRelayURL)/live-session-lan"])
        XCTAssertEqual(service.currentConnectionPathStatus, .remoteRelay)
    }

    func testHandleNetworkReachabilityChangeFallsBackToRemoteRelayWhenLiveBonjourDirectReconnectFails() async {
        let service = makeService()
        let viewModel = ContentViewModel()
        let macDeviceID = "mac-\(UUID().uuidString)"
        let remoteRelayURL = "wss://relay.example/relay"
        let lanRelayURL = "ws://desk-mac.local:9000/relay"
        var connectURLs: [String] = []

        service.trustedMacRegistry.records[macDeviceID] = CodexTrustedMacRecord(
            macDeviceId: macDeviceID,
            macIdentityPublicKey: Data(repeating: 31, count: 32).base64EncodedString(),
            lastPairedAt: Date(),
            relayURL: remoteRelayURL,
            lastLocalRelayURL: lanRelayURL
        )
        service.lastTrustedMacDeviceId = macDeviceID
        service.relaySessionId = "saved-session"
        service.relayUrl = remoteRelayURL
        service.relayMacDeviceId = macDeviceID
        service.isConnected = true
        service.bonjourDiscoveryOverride = {
            [.bonjour(lanRelayURL, macDeviceId: macDeviceID)]
        }
        service.trustedSessionResolverByRelayURLOverride = { relayURL in
            CodexTrustedSessionResolveResponse(
                ok: true,
                macDeviceId: macDeviceID,
                macIdentityPublicKey: Data(repeating: 32, count: 32).base64EncodedString(),
                displayName: "Desk Mac",
                sessionId: relayURL == lanRelayURL ? "live-session-lan" : "live-session-remote"
            )
        }
        viewModel.disconnectOverride = { codex, _ in
            codex.isConnected = false
        }
        viewModel.connectOverride = { codex, serverURL in
            connectURLs.append(serverURL)
            if serverURL == "\(lanRelayURL)/live-session-lan" {
                throw CodexServiceError.disconnected
            }
            codex.relayUrl = remoteRelayURL
            codex.isConnected = true
        }

        await viewModel.handleNetworkReachabilityChange(
            codex: service,
            prefersLocalNetwork: true
        )

        XCTAssertEqual(connectURLs, [
            "\(lanRelayURL)/live-session-lan",
            "\(remoteRelayURL)/saved-session",
        ])
        XCTAssertEqual(service.currentConnectionPathStatus, .remoteRelay)
    }

    func testHandleNetworkReachabilityChangeReconnectsImmediatelyWhileConnectionSyncIsInFlight() async {
        let service = makeService()
        let viewModel = ContentViewModel()
        let macDeviceID = "mac-\(UUID().uuidString)"
        let remoteRelayURL = "wss://relay.example/relay"
        let lanRelayURL = "ws://desk-mac.local:9000/relay"
        var connectURLs: [String] = []
        var syncRequestContinuation: CheckedContinuation<Void, Never>?
        var hasPausedInitialSyncRequest = false
        let syncStarted = expectation(description: "sync request started")

        service.trustedMacRegistry.records[macDeviceID] = CodexTrustedMacRecord(
            macDeviceId: macDeviceID,
            macIdentityPublicKey: Data(repeating: 34, count: 32).base64EncodedString(),
            lastPairedAt: Date(),
            relayURL: remoteRelayURL,
            lastLocalRelayURL: lanRelayURL
        )
        service.lastTrustedMacDeviceId = macDeviceID
        service.relaySessionId = "saved-session"
        service.relayUrl = lanRelayURL
        service.relayMacDeviceId = macDeviceID
        service.isConnected = true
        service.isInitialized = true
        service.requestTransportOverride = { method, _ in
            if method == "thread/list", !hasPausedInitialSyncRequest {
                hasPausedInitialSyncRequest = true
                syncStarted.fulfill()
                await withCheckedContinuation { continuation in
                    syncRequestContinuation = continuation
                }
                return Self.threadListResponse()
            }
            return Self.emptyRPCResponse()
        }
        viewModel.disconnectOverride = { codex, _ in
            codex.isConnected = false
        }
        viewModel.connectOverride = { codex, serverURL in
            connectURLs.append(serverURL)
            codex.relayUrl = remoteRelayURL
            codex.isConnected = true
        }

        service.requestImmediateSync()
        await fulfillment(of: [syncStarted], timeout: 1.0)

        await viewModel.handleNetworkReachabilityChange(
            codex: service,
            prefersLocalNetwork: false
        )

        syncRequestContinuation?.resume()

        XCTAssertEqual(connectURLs, ["\(remoteRelayURL)/saved-session"])
        XCTAssertEqual(service.currentConnectionPathStatus, .remoteRelay)
    }

    func testHandleNetworkReachabilityChangeReconnectsImmediatelyWhileUsageRefreshIsInFlight() async {
        let service = makeService()
        let viewModel = ContentViewModel()
        let macDeviceID = "mac-\(UUID().uuidString)"
        let remoteRelayURL = "wss://relay.example/relay"
        let lanRelayURL = "ws://desk-mac.local:9000/relay"
        var connectURLs: [String] = []
        var usageRequestContinuation: CheckedContinuation<Void, Never>?
        var hasPausedUsageRefresh = false
        let usageRefreshStarted = expectation(description: "usage refresh started")

        service.trustedMacRegistry.records[macDeviceID] = CodexTrustedMacRecord(
            macDeviceId: macDeviceID,
            macIdentityPublicKey: Data(repeating: 35, count: 32).base64EncodedString(),
            lastPairedAt: Date(),
            relayURL: remoteRelayURL,
            lastLocalRelayURL: lanRelayURL
        )
        service.lastTrustedMacDeviceId = macDeviceID
        service.relaySessionId = "saved-session"
        service.relayUrl = lanRelayURL
        service.relayMacDeviceId = macDeviceID
        service.isConnected = true
        service.isInitialized = true
        service.requestTransportOverride = { method, _ in
            if method == "account/rateLimits/read", !hasPausedUsageRefresh {
                hasPausedUsageRefresh = true
                usageRefreshStarted.fulfill()
                await withCheckedContinuation { continuation in
                    usageRequestContinuation = continuation
                }
                return Self.rateLimitsResponse()
            }
            return Self.emptyRPCResponse()
        }
        viewModel.disconnectOverride = { codex, _ in
            codex.isConnected = false
        }
        viewModel.connectOverride = { codex, serverURL in
            connectURLs.append(serverURL)
            codex.relayUrl = remoteRelayURL
            codex.isConnected = true
        }

        let refreshTask = Task {
            await service.refreshUsageStatus(threadId: nil)
        }
        await fulfillment(of: [usageRefreshStarted], timeout: 1.0)

        await viewModel.handleNetworkReachabilityChange(
            codex: service,
            prefersLocalNetwork: false
        )

        usageRequestContinuation?.resume()
        await refreshTask.value

        XCTAssertEqual(connectURLs, ["\(remoteRelayURL)/saved-session"])
        XCTAssertEqual(service.currentConnectionPathStatus, .remoteRelay)
    }

    private func makeService() -> CodexService {
        let suiteName = "ContentViewModelReconnectTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        let service = CodexService(defaults: defaults)
        Self.retainedServices.append(service)
        return service
    }

    // Clears the persisted relay keys so reconnect tests do not inherit state from other suites.
    private func clearStoredSecureRelayState() {
        SecureStore.deleteValue(for: CodexSecureKeys.relaySessionId)
        SecureStore.deleteValue(for: CodexSecureKeys.relayUrl)
        SecureStore.deleteValue(for: CodexSecureKeys.relayMacDeviceId)
        SecureStore.deleteValue(for: CodexSecureKeys.relayMacIdentityPublicKey)
        SecureStore.deleteValue(for: CodexSecureKeys.relayProtocolVersion)
        SecureStore.deleteValue(for: CodexSecureKeys.relayLastAppliedBridgeOutboundSeq)
        SecureStore.deleteValue(for: CodexSecureKeys.trustedMacRegistry)
        SecureStore.deleteValue(for: CodexSecureKeys.lastTrustedMacDeviceId)
    }

    private static func emptyRPCResponse() -> RPCMessage {
        RPCMessage(id: .string(UUID().uuidString), result: .object([:]), includeJSONRPC: false)
    }

    private static func threadListResponse() -> RPCMessage {
        RPCMessage(
            id: .string(UUID().uuidString),
            result: .object([
                "data": .array([]),
            ]),
            includeJSONRPC: false
        )
    }

    private static func rateLimitsResponse() -> RPCMessage {
        RPCMessage(
            id: .string(UUID().uuidString),
            result: .object([
                "rateLimits": .object([:]),
            ]),
            includeJSONRPC: false
        )
    }
}
