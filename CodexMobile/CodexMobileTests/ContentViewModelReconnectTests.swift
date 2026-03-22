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

    func testPreferredReconnectURLResolvesExplicitlySelectedHostBeforeMoreRecentFallback() async {
        let selectedMacDeviceID = "mac-\(UUID().uuidString)"
        let moreRecentMacDeviceID = "mac-\(UUID().uuidString)"
        let selectedRelayURL = "wss://selected.relay/relay"
        let moreRecentRelayURL = "wss://recent.relay/relay"

        let service = makeService()
        let viewModel = ContentViewModel()
        service.selectedHostDeviceId = selectedMacDeviceID
        service.trustedMacRegistry.records[selectedMacDeviceID] = CodexTrustedMacRecord(
            macDeviceId: selectedMacDeviceID,
            macIdentityPublicKey: Data(repeating: 13, count: 32).base64EncodedString(),
            lastPairedAt: Date().addingTimeInterval(-120),
            relayURL: selectedRelayURL,
            lastUsedAt: Date().addingTimeInterval(-120)
        )
        service.trustedMacRegistry.records[moreRecentMacDeviceID] = CodexTrustedMacRecord(
            macDeviceId: moreRecentMacDeviceID,
            macIdentityPublicKey: Data(repeating: 14, count: 32).base64EncodedString(),
            lastPairedAt: Date(),
            relayURL: moreRecentRelayURL,
            lastUsedAt: Date()
        )

        var resolvedDeviceID: String?
        service.trustedSessionResolverOverride = {
            let preferred = service.preferredTrustedMacRecord
            resolvedDeviceID = preferred?.macDeviceId
            service.relayUrl = preferred?.relayURL
            return CodexTrustedSessionResolveResponse(
                ok: true,
                macDeviceId: preferred?.macDeviceId ?? "",
                macIdentityPublicKey: preferred?.macIdentityPublicKey ?? "",
                displayName: preferred?.displayName,
                sessionId: "resolved-session"
            )
        }

        let reconnectURL = await viewModel.preferredReconnectURL(codex: service)

        XCTAssertEqual(resolvedDeviceID, selectedMacDeviceID)
        XCTAssertEqual(reconnectURL, "\(selectedRelayURL)/resolved-session")
    }

    func testPreferredReconnectURLDoesNotFallbackToSavedSessionForDifferentSelectedHost() async {
        let selectedMacDeviceID = "mac-\(UUID().uuidString)"
        let savedSessionMacDeviceID = "mac-\(UUID().uuidString)"
        let selectedRelayURL = "wss://selected.relay/relay"
        let savedRelayURL = "wss://saved.relay/relay"

        let service = makeService()
        let viewModel = ContentViewModel()
        service.selectedHostDeviceId = selectedMacDeviceID
        service.trustedMacRegistry.records[selectedMacDeviceID] = CodexTrustedMacRecord(
            macDeviceId: selectedMacDeviceID,
            macIdentityPublicKey: Data(repeating: 15, count: 32).base64EncodedString(),
            lastPairedAt: Date(),
            relayURL: selectedRelayURL,
            lastUsedAt: Date()
        )
        service.trustedMacRegistry.records[savedSessionMacDeviceID] = CodexTrustedMacRecord(
            macDeviceId: savedSessionMacDeviceID,
            macIdentityPublicKey: Data(repeating: 16, count: 32).base64EncodedString(),
            lastPairedAt: Date().addingTimeInterval(-120),
            relayURL: savedRelayURL,
            lastUsedAt: Date().addingTimeInterval(-120)
        )
        service.relaySessionId = "saved-session"
        service.relayUrl = savedRelayURL
        service.relayMacDeviceId = savedSessionMacDeviceID
        service.trustedSessionResolverOverride = {
            throw CodexTrustedSessionResolveError.macOffline("Your trusted Mac is offline right now.")
        }

        let reconnectURL = await viewModel.preferredReconnectURL(codex: service)

        XCTAssertNil(reconnectURL)
        XCTAssertEqual(service.lastErrorMessage, "Your trusted Mac is offline right now.")
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
        SecureStore.deleteValue(for: CodexSecureKeys.selectedHostDeviceId)
    }
}
