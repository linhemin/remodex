// FILE: BackgroundLocationKeepaliveServiceTests.swift
// Purpose: Verifies location keepalive requests the right authorization and only starts background updates when fully authorized.
// Layer: Unit Test
// Exports: BackgroundLocationKeepaliveServiceTests
// Depends on: XCTest, CoreLocation, CodexMobile

import CoreLocation
import XCTest
@testable import CodexMobile

@MainActor
final class BackgroundLocationKeepaliveServiceTests: XCTestCase {
    func testRequestFullAuthorizationRequestsWhenInUseFirst() {
        let manager = FakeBackgroundLocationManager(authorizationStatus: .notDetermined)
        let service = BackgroundLocationKeepaliveService(manager: manager)

        service.requestFullAuthorization()

        XCTAssertEqual(manager.requestWhenInUseAuthorizationCallCount, 1)
        XCTAssertEqual(manager.requestAlwaysAuthorizationCallCount, 0)
    }

    func testRequestFullAuthorizationEscalatesWhenAlreadyWhenInUse() {
        let manager = FakeBackgroundLocationManager(authorizationStatus: .authorizedWhenInUse)
        let service = BackgroundLocationKeepaliveService(manager: manager)

        service.requestFullAuthorization()

        XCTAssertEqual(manager.requestWhenInUseAuthorizationCallCount, 0)
        XCTAssertEqual(manager.requestAlwaysAuthorizationCallCount, 1)
    }

    func testAuthorizationChangeEscalatesToAlwaysAfterWhenInUseGrant() {
        let manager = FakeBackgroundLocationManager(authorizationStatus: .notDetermined)
        let service = BackgroundLocationKeepaliveService(manager: manager)

        service.requestFullAuthorization()
        manager.currentAuthorizationStatus = .authorizedWhenInUse
        manager.triggerAuthorizationChange()

        XCTAssertEqual(manager.requestWhenInUseAuthorizationCallCount, 1)
        XCTAssertEqual(manager.requestAlwaysAuthorizationCallCount, 1)
    }

    func testStartKeepaliveConfiguresManagerForBackgroundUpdates() {
        let manager = FakeBackgroundLocationManager(authorizationStatus: .authorizedAlways)
        let service = BackgroundLocationKeepaliveService(manager: manager)

        service.startKeepaliveIfPossible()

        XCTAssertTrue(manager.allowsBackgroundLocationUpdates)
        XCTAssertFalse(manager.pausesLocationUpdatesAutomatically)
        XCTAssertEqual(manager.startUpdatingLocationCallCount, 1)
        XCTAssertEqual(manager.startMonitoringSignificantLocationChangesCallCount, 1)
        XCTAssertTrue(service.isKeepaliveActive)
    }

    func testStartKeepaliveIsIdempotentOnceActive() {
        let manager = FakeBackgroundLocationManager(authorizationStatus: .authorizedAlways)
        let service = BackgroundLocationKeepaliveService(manager: manager)

        service.startKeepaliveIfPossible()
        service.startKeepaliveIfPossible()

        XCTAssertEqual(manager.startUpdatingLocationCallCount, 1)
        XCTAssertEqual(manager.startMonitoringSignificantLocationChangesCallCount, 1)
        XCTAssertTrue(manager.allowsBackgroundLocationUpdates)
        XCTAssertFalse(manager.pausesLocationUpdatesAutomatically)
        XCTAssertTrue(service.isKeepaliveActive)
    }

    func testStartKeepaliveDoesNothingWithoutAlwaysAuthorization() {
        let manager = FakeBackgroundLocationManager(authorizationStatus: .authorizedWhenInUse)
        let service = BackgroundLocationKeepaliveService(manager: manager)

        service.startKeepaliveIfPossible()

        XCTAssertFalse(manager.allowsBackgroundLocationUpdates)
        XCTAssertEqual(manager.startUpdatingLocationCallCount, 0)
        XCTAssertEqual(manager.startMonitoringSignificantLocationChangesCallCount, 0)
        XCTAssertFalse(service.isKeepaliveActive)
    }

    func testStopKeepaliveStopsBothLocationStreams() {
        let manager = FakeBackgroundLocationManager(authorizationStatus: .authorizedAlways)
        let service = BackgroundLocationKeepaliveService(manager: manager)
        service.startKeepaliveIfPossible()

        service.stopKeepalive()

        XCTAssertEqual(manager.stopUpdatingLocationCallCount, 1)
        XCTAssertEqual(manager.stopMonitoringSignificantLocationChangesCallCount, 1)
        XCTAssertFalse(manager.allowsBackgroundLocationUpdates)
        XCTAssertTrue(manager.pausesLocationUpdatesAutomatically)
        XCTAssertFalse(service.isKeepaliveActive)
    }

    func testLocationUpdatesInvokeWakeHandler() {
        let manager = FakeBackgroundLocationManager(authorizationStatus: .authorizedAlways)
        let service = BackgroundLocationKeepaliveService(manager: manager)
        var wakeCallCount = 0

        service.setWakeHandler {
            wakeCallCount += 1
        }

        manager.triggerLocationUpdate()

        XCTAssertEqual(wakeCallCount, 1)
    }
}

private final class FakeBackgroundLocationManager: BackgroundLocationManaging {
    var currentAuthorizationStatus: CLAuthorizationStatus
    var allowsBackgroundLocationUpdates = false
    var pausesLocationUpdatesAutomatically = true
    weak var delegate: CLLocationManagerDelegate?

    private(set) var requestWhenInUseAuthorizationCallCount = 0
    private(set) var requestAlwaysAuthorizationCallCount = 0
    private(set) var startUpdatingLocationCallCount = 0
    private(set) var stopUpdatingLocationCallCount = 0
    private(set) var startMonitoringSignificantLocationChangesCallCount = 0
    private(set) var stopMonitoringSignificantLocationChangesCallCount = 0

    init(authorizationStatus: CLAuthorizationStatus) {
        self.currentAuthorizationStatus = authorizationStatus
    }

    func requestWhenInUseAuthorization() {
        requestWhenInUseAuthorizationCallCount += 1
    }

    func requestAlwaysAuthorization() {
        requestAlwaysAuthorizationCallCount += 1
    }

    func startUpdatingLocation() {
        startUpdatingLocationCallCount += 1
    }

    func stopUpdatingLocation() {
        stopUpdatingLocationCallCount += 1
    }

    func startMonitoringSignificantLocationChanges() {
        startMonitoringSignificantLocationChangesCallCount += 1
    }

    func stopMonitoringSignificantLocationChanges() {
        stopMonitoringSignificantLocationChangesCallCount += 1
    }

    func triggerAuthorizationChange() {
        delegate?.locationManagerDidChangeAuthorization?(CLLocationManager())
    }

    func triggerLocationUpdate() {
        delegate?.locationManager?(CLLocationManager(), didUpdateLocations: [])
    }
}
