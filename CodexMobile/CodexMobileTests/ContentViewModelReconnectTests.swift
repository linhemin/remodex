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
}
