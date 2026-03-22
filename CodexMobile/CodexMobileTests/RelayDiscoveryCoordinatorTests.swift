// FILE: RelayDiscoveryCoordinatorTests.swift
// Purpose: Verifies LAN-first relay candidate ranking, filtering, and normalization.
// Layer: Unit Test
// Exports: RelayDiscoveryCoordinatorTests
// Depends on: XCTest, Foundation, CodexMobile

import Foundation
import XCTest
@testable import CodexMobile

final class RelayDiscoveryCoordinatorTests: XCTestCase {
    func testRankCandidatesPrefersBonjourThenOverlayThenSavedRelay() {
        let ranked = RelayDiscoveryCoordinator.rankCandidates([
            .savedRelay("wss://relay.example/relay", macDeviceId: "mac-1"),
            .overlay("ws://mac-1.ts.net:9000/relay", macDeviceId: "mac-1"),
            .bonjour("ws://macbook-pro.local:9000/relay", macDeviceId: "mac-1"),
        ])

        XCTAssertEqual(ranked.map(\.url.absoluteString), [
            "ws://macbook-pro.local:9000/relay",
            "ws://mac-1.ts.net:9000/relay",
            "wss://relay.example/relay",
        ])
    }

    func testRankCandidatesFiltersForPreferredMacDeviceId() {
        let ranked = RelayDiscoveryCoordinator.rankCandidates(
            [
                .bonjour("ws://wrong.local:9000/relay", macDeviceId: "mac-2"),
                .overlay("ws://mac-1.ts.net:9000/relay", macDeviceId: "mac-1"),
                .savedRelay("wss://relay.example/relay", macDeviceId: nil),
            ],
            preferredMacDeviceId: "mac-1"
        )

        XCTAssertEqual(ranked.map(\.url.absoluteString), [
            "ws://mac-1.ts.net:9000/relay",
            "wss://relay.example/relay",
        ])
    }

    func testRankCandidatesNormalizesAndDeduplicatesRelayBaseURLs() {
        let ranked = RelayDiscoveryCoordinator.rankCandidates([
            .savedRelay("wss://relay.example/relay/live-session", macDeviceId: "mac-1"),
            .savedRelay("wss://relay.example/relay/", macDeviceId: "mac-1"),
        ])

        XCTAssertEqual(ranked.map(\.url.absoluteString), ["wss://relay.example/relay"])
    }
}
