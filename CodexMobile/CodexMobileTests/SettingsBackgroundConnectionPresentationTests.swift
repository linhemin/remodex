// FILE: SettingsBackgroundConnectionPresentationTests.swift
// Purpose: Verifies Settings background connection copy matches enablement and authorization state.
// Layer: Unit Test
// Exports: SettingsBackgroundConnectionPresentationTests
// Depends on: XCTest, CoreLocation, CodexMobile

import CoreLocation
import XCTest
@testable import CodexMobile

@MainActor
final class SettingsBackgroundConnectionPresentationTests: XCTestCase {
    func testMakeReturnsLimitedStateWhenAlwaysPermissionMissing() {
        let status = SettingsBackgroundConnectionPresentation.make(
            isEnabled: true,
            authorization: .authorizedWhenInUse,
            isKeepingAlive: false
        )

        XCTAssertEqual(status.title, "Enabled, limited")
        XCTAssertTrue(status.showsOpenSettingsButton)
    }

    func testMakeReturnsActiveStateWhenKeepaliveIsRunning() {
        let status = SettingsBackgroundConnectionPresentation.make(
            isEnabled: true,
            authorization: .authorizedAlways,
            isKeepingAlive: true
        )

        XCTAssertEqual(status.title, "Enabled, keeping alive")
        XCTAssertFalse(status.showsOpenSettingsButton)
    }

    func testMakeReturnsReadyStateWhenAuthorizedAlwaysButIdle() {
        let status = SettingsBackgroundConnectionPresentation.make(
            isEnabled: true,
            authorization: .authorizedAlways,
            isKeepingAlive: false
        )

        XCTAssertEqual(status.title, "Enabled")
        XCTAssertFalse(status.showsOpenSettingsButton)
    }

    func testMakeReturnsPermissionRequiredStateWhenAuthorizationDenied() {
        let status = SettingsBackgroundConnectionPresentation.make(
            isEnabled: true,
            authorization: .denied,
            isKeepingAlive: false
        )

        XCTAssertEqual(status.title, "Permission required")
        XCTAssertTrue(status.showsOpenSettingsButton)
    }

    func testMakeReturnsDisabledStateWhenFeatureIsOff() {
        let status = SettingsBackgroundConnectionPresentation.make(
            isEnabled: false,
            authorization: .notDetermined,
            isKeepingAlive: false
        )

        XCTAssertEqual(status.title, "Disabled")
        XCTAssertFalse(status.showsOpenSettingsButton)
    }
}
