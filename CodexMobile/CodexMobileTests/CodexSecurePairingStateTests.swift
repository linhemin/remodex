// FILE: CodexSecurePairingStateTests.swift
// Purpose: Verifies fresh QR scans force bootstrap mode and secure pairing failures stay actionable in UI state.
// Layer: Unit Test
// Exports: CodexSecurePairingStateTests
// Depends on: Foundation, XCTest, CodexMobile

import Foundation
import XCTest
import UserNotifications
@testable import CodexMobile

@MainActor
final class CodexSecurePairingStateTests: XCTestCase {
    private static var retainedServices: [CodexService] = []
    private var defaultsSuiteNamesToClear: [String] = []

    override func setUp() {
        super.setUp()
        clearStoredSecureRelayState()
    }

    override func tearDown() {
        clearStoredSecureRelayState()
        for suiteName in defaultsSuiteNamesToClear {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        defaultsSuiteNamesToClear.removeAll()
        super.tearDown()
    }

    func testRememberRelayPairingForcesFreshQRBootstrapEvenForTrustedMac() {
        let service = makeService()
        let macDeviceID = "mac-\(UUID().uuidString)"
        let originalPublicKey = Data(repeating: 1, count: 32).base64EncodedString()
        let freshQRPublicKey = Data(repeating: 2, count: 32).base64EncodedString()

        service.trustedMacRegistry.records[macDeviceID] = CodexTrustedMacRecord(
            macDeviceId: macDeviceID,
            macIdentityPublicKey: originalPublicKey,
            lastPairedAt: Date()
        )

        service.rememberRelayPairing(
            CodexPairingQRPayload(
                v: codexPairingQRVersion,
                relay: "ws://relay.local/relay",
                sessionId: "session-\(UUID().uuidString)",
                macDeviceId: macDeviceID,
                macIdentityPublicKey: freshQRPublicKey,
                expiresAt: Int64(Date().addingTimeInterval(60).timeIntervalSince1970 * 1000)
            )
        )

        XCTAssertTrue(service.shouldForceQRBootstrapOnNextHandshake)
        XCTAssertFalse(service.hasTrustedReconnectContext)
        XCTAssertEqual(service.secureConnectionState, .trustedMac)
        XCTAssertEqual(service.normalizedRelayMacIdentityPublicKey, freshQRPublicKey)
    }

    func testRememberRelayPairingShowsHandshakeStateForBrandNewMac() {
        let service = makeService()
        let freshQRPublicKey = Data(repeating: 4, count: 32).base64EncodedString()

        service.rememberRelayPairing(
            CodexPairingQRPayload(
                v: codexPairingQRVersion,
                relay: "ws://relay.local/relay",
                sessionId: "session-\(UUID().uuidString)",
                macDeviceId: "mac-\(UUID().uuidString)",
                macIdentityPublicKey: freshQRPublicKey,
                expiresAt: Int64(Date().addingTimeInterval(60).timeIntervalSince1970 * 1000)
            )
        )

        XCTAssertTrue(service.shouldForceQRBootstrapOnNextHandshake)
        XCTAssertEqual(service.secureConnectionState, .handshaking)
        XCTAssertEqual(service.secureMacFingerprint, codexSecureFingerprint(for: freshQRPublicKey))
    }

    func testResetSecureTransportStatePreservesRePairRequiredState() {
        let service = makeService()
        service.relaySessionId = "session-\(UUID().uuidString)"
        service.relayUrl = "ws://relay.local/relay"
        service.secureConnectionState = .rePairRequired
        service.secureMacFingerprint = "ABC123"

        service.resetSecureTransportState()

        XCTAssertEqual(service.secureConnectionState, .rePairRequired)
        XCTAssertEqual(service.secureMacFingerprint, "ABC123")
    }

    func testApplyingResolvedTrustedSessionResetsReplayCursorWhenLiveSessionChanges() {
        let service = makeService()
        let macDeviceID = "mac-\(UUID().uuidString)"

        service.relaySessionId = "stale-session"
        service.relayUrl = "wss://relay.local/relay"
        service.relayMacDeviceId = macDeviceID
        service.lastAppliedBridgeOutboundSeq = 17
        SecureStore.writeString("17", for: CodexSecureKeys.relayLastAppliedBridgeOutboundSeq)

        service.applyResolvedTrustedSession(
            CodexTrustedSessionResolveResponse(
                ok: true,
                macDeviceId: macDeviceID,
                macIdentityPublicKey: Data(repeating: 7, count: 32).base64EncodedString(),
                displayName: "Desk Mac",
                sessionId: "fresh-session"
            ),
            relayURL: "wss://relay.local/relay"
        )

        XCTAssertEqual(service.lastAppliedBridgeOutboundSeq, 0)
        XCTAssertEqual(
            SecureStore.readString(for: CodexSecureKeys.relayLastAppliedBridgeOutboundSeq),
            "0"
        )
    }

    func testApplyingResolvedTrustedSessionKeepsReplayCursorWhenLiveSessionIsUnchanged() {
        let service = makeService()
        let macDeviceID = "mac-\(UUID().uuidString)"

        service.relaySessionId = "same-session"
        service.relayUrl = "wss://relay.local/relay"
        service.relayMacDeviceId = macDeviceID
        service.lastAppliedBridgeOutboundSeq = 17
        SecureStore.writeString("17", for: CodexSecureKeys.relayLastAppliedBridgeOutboundSeq)

        service.applyResolvedTrustedSession(
            CodexTrustedSessionResolveResponse(
                ok: true,
                macDeviceId: macDeviceID,
                macIdentityPublicKey: Data(repeating: 8, count: 32).base64EncodedString(),
                displayName: "Desk Mac",
                sessionId: "same-session"
            ),
            relayURL: "wss://relay.local/relay"
        )

        XCTAssertEqual(service.lastAppliedBridgeOutboundSeq, 17)
        XCTAssertEqual(
            SecureStore.readString(for: CodexSecureKeys.relayLastAppliedBridgeOutboundSeq),
            "17"
        )
    }

    func testApplyingResolvedTrustedSessionPersistsLocalRelayDiscoveryMetadata() {
        let service = makeService()
        let macDeviceID = "mac-\(UUID().uuidString)"
        let remoteRelayURL = "wss://relay.example/relay"
        let remoteSessionID = "saved-session"
        let relayURL = "ws://macbook-pro.local:9000/relay"

        SecureStore.writeString(remoteSessionID, for: CodexSecureKeys.relaySessionId)
        service.relaySessionId = remoteSessionID
        service.trustedMacRegistry.records[macDeviceID] = CodexTrustedMacRecord(
            macDeviceId: macDeviceID,
            macIdentityPublicKey: Data(repeating: 9, count: 32).base64EncodedString(),
            lastPairedAt: Date(),
            relayURL: remoteRelayURL
        )

        service.applyResolvedTrustedSession(
            CodexTrustedSessionResolveResponse(
                ok: true,
                macDeviceId: macDeviceID,
                macIdentityPublicKey: Data(repeating: 10, count: 32).base64EncodedString(),
                displayName: "Desk Mac",
                sessionId: "fresh-session"
            ),
            relayURL: relayURL
        )

        let record = service.trustedMacRegistry.records[macDeviceID]
        // Session IDs are now always persisted (universal across relay paths) for cellular fallback.
        XCTAssertEqual(SecureStore.readString(for: CodexSecureKeys.relaySessionId), "fresh-session")
        XCTAssertEqual(record?.relayURL, remoteRelayURL)
        XCTAssertEqual(record?.lastResolvedSessionId, "fresh-session")
        XCTAssertEqual(record?.lastLocalRelayURL, relayURL)
        XCTAssertNil(record?.lastOverlayRelayURL)
        XCTAssertNotNil(record?.lastDiscoveredAt)
    }

    func testApplyingResolvedTrustedSessionPersistsOverlayRelayDiscoveryMetadata() {
        let service = makeService()
        let macDeviceID = "mac-\(UUID().uuidString)"
        let remoteRelayURL = "wss://relay.example/relay"
        let remoteSessionID = "saved-session"
        let relayURL = "ws://100.122.27.82:9000/relay"

        SecureStore.writeString(remoteSessionID, for: CodexSecureKeys.relaySessionId)
        service.relaySessionId = remoteSessionID
        service.trustedMacRegistry.records[macDeviceID] = CodexTrustedMacRecord(
            macDeviceId: macDeviceID,
            macIdentityPublicKey: Data(repeating: 11, count: 32).base64EncodedString(),
            lastPairedAt: Date(),
            relayURL: remoteRelayURL
        )

        service.applyResolvedTrustedSession(
            CodexTrustedSessionResolveResponse(
                ok: true,
                macDeviceId: macDeviceID,
                macIdentityPublicKey: Data(repeating: 12, count: 32).base64EncodedString(),
                displayName: "Desk Mac",
                sessionId: "fresh-session"
            ),
            relayURL: relayURL
        )

        let record = service.trustedMacRegistry.records[macDeviceID]
        // Session IDs are now always persisted (universal across relay paths) for cellular fallback.
        XCTAssertEqual(SecureStore.readString(for: CodexSecureKeys.relaySessionId), "fresh-session")
        XCTAssertEqual(record?.relayURL, remoteRelayURL)
        XCTAssertEqual(record?.lastResolvedSessionId, "fresh-session")
        XCTAssertNil(record?.lastLocalRelayURL)
        XCTAssertEqual(record?.lastOverlayRelayURL, relayURL)
        XCTAssertNotNil(record?.lastDiscoveredAt)
    }

    // Clears the persisted relay session keys touched by secure reconnect tests.
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

    private func makeService() -> CodexService {
        let defaults = makeTestDefaults()
        let service = CodexService(
            defaults: defaults,
            userNotificationCenter: FakeUserNotificationCenter(),
            remoteNotificationRegistrar: FakeRemoteNotificationRegistrar()
        )
        Self.retainedServices.append(service)
        return service
    }

    private func makeTestDefaults() -> UserDefaults {
        let suiteName = "CodexSecurePairingStateTests.\(UUID().uuidString)"
        defaultsSuiteNamesToClear.append(suiteName)
        return UserDefaults(suiteName: suiteName) ?? .standard
    }
}

private final class FakeRemoteNotificationRegistrar: CodexRemoteNotificationRegistering {
    func registerForRemoteNotifications() {}
}

private final class FakeUserNotificationCenter: CodexUserNotificationCentering {
    weak var delegate: UNUserNotificationCenterDelegate?

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        true
    }

    func add(_ request: UNNotificationRequest) async throws {}

    func authorizationStatus() async -> UNAuthorizationStatus {
        .authorized
    }
}
