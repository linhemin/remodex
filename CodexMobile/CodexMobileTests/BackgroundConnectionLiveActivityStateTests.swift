// FILE: BackgroundConnectionLiveActivityStateTests.swift
// Purpose: Verifies background connection Live Activity states map cleanly from connection and permission inputs.
// Layer: Unit Test
// Exports: BackgroundConnectionLiveActivityStateTests
// Depends on: XCTest, CodexMobile

import XCTest
@testable import CodexMobile

@MainActor
final class BackgroundConnectionLiveActivityStateTests: XCTestCase {
    func testMakeReturnsConnectedStateWithHostNameAndConnectionStartTime() {
        let connectedAt = Date(timeIntervalSince1970: 1_710_000_000)
        let state = BackgroundConnectionLiveActivityState.make(
            hostName: "Studio Mac",
            connectedAt: connectedAt
        )

        XCTAssertEqual(state.hostName, "Studio Mac")
        XCTAssertEqual(state.connectedAt, connectedAt)
        XCTAssertTrue(state.isConnected)
    }
}
