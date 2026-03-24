// FILE: BackgroundConnectionCoordinatorTests.swift
// Purpose: Verifies the coordinator starts and stops keepalive plus Live Activity updates from connection snapshots.
// Layer: Unit Test
// Exports: BackgroundConnectionCoordinatorTests
// Depends on: XCTest, CoreLocation, CodexMobile

import CoreLocation
import XCTest
@testable import CodexMobile

@MainActor
final class BackgroundConnectionCoordinatorTests: XCTestCase {
    func testHandleStartsKeepaliveAndUpdatesLiveActivityWhenEnabledAndBackgroundConnected() async {
        let defaults = isolatedDefaults()
        let locationService = FakeBackgroundLocationKeepaliveService(authorizationStatus: .authorizedAlways)
        let liveActivityService = FakeLiveActivityService()
        let connectionService = FakeBackgroundConnectionSnapshotService()
        let connectedAt = Date(timeIntervalSince1970: 1_710_000_000)
        let coordinator = BackgroundConnectionCoordinator(
            defaults: defaults,
            locationService: locationService,
            liveActivityService: liveActivityService,
            connectionService: connectionService
        )

        coordinator.enableFeatureAndRequestPermissions()

        let snapshot = CodexServiceConnectionSnapshot(
            isConnected: true,
            connectionPhase: .connected,
            hasAnyRunningTurn: false,
            isAppInForeground: false,
            hasReconnectCandidate: true,
            pairDisplayName: "Studio Mac",
            connectedAt: connectedAt
        )
        connectionService.snapshot = snapshot
        await coordinator.handle(connectionSnapshot: snapshot)

        XCTAssertEqual(locationService.requestFullAuthorizationCallCount, 1)
        XCTAssertEqual(locationService.startKeepaliveCallCount, 1)
        XCTAssertTrue(locationService.isKeepaliveActive)
        XCTAssertEqual(liveActivityService.states.count, 1)
        XCTAssertEqual(liveActivityService.states.first?.hostName, "Studio Mac")
        XCTAssertEqual(liveActivityService.states.first?.connectedAt, connectedAt)
        XCTAssertEqual(liveActivityService.endCallCount, 0)
    }

    func testDisableFeatureStopsKeepaliveAndEndsLiveActivity() async {
        let defaults = isolatedDefaults()
        let locationService = FakeBackgroundLocationKeepaliveService(authorizationStatus: .authorizedAlways)
        let liveActivityService = FakeLiveActivityService()
        let connectionService = FakeBackgroundConnectionSnapshotService()
        let coordinator = BackgroundConnectionCoordinator(
            defaults: defaults,
            locationService: locationService,
            liveActivityService: liveActivityService,
            connectionService: connectionService
        )

        coordinator.enableFeatureAndRequestPermissions()

        let snapshot = CodexServiceConnectionSnapshot(
            isConnected: true,
            connectionPhase: .connected,
            hasAnyRunningTurn: false,
            isAppInForeground: false,
            hasReconnectCandidate: true,
            pairDisplayName: "Studio Mac",
            connectedAt: Date(timeIntervalSince1970: 1_710_000_000)
        )
        connectionService.snapshot = snapshot
        await coordinator.handle(connectionSnapshot: snapshot)

        await coordinator.disableFeature()

        XCTAssertEqual(locationService.stopKeepaliveCallCount, 1)
        XCTAssertFalse(locationService.isKeepaliveActive)
        XCTAssertEqual(liveActivityService.endCallCount, 1)
    }

    func testHandleEndsLiveActivityWhenReturningToForeground() async {
        let defaults = isolatedDefaults()
        let locationService = FakeBackgroundLocationKeepaliveService(authorizationStatus: .authorizedAlways)
        let liveActivityService = FakeLiveActivityService()
        let connectionService = FakeBackgroundConnectionSnapshotService()
        let coordinator = BackgroundConnectionCoordinator(
            defaults: defaults,
            locationService: locationService,
            liveActivityService: liveActivityService,
            connectionService: connectionService
        )

        coordinator.enableFeatureAndRequestPermissions()

        let backgroundSnapshot = CodexServiceConnectionSnapshot(
            isConnected: true,
            connectionPhase: .connected,
            hasAnyRunningTurn: false,
            isAppInForeground: false,
            hasReconnectCandidate: true,
            pairDisplayName: "Studio Mac",
            connectedAt: Date(timeIntervalSince1970: 1_710_000_000)
        )
        connectionService.snapshot = backgroundSnapshot
        await coordinator.handle(connectionSnapshot: backgroundSnapshot)

        let foregroundSnapshot = CodexServiceConnectionSnapshot(
            isConnected: true,
            connectionPhase: .connected,
            hasAnyRunningTurn: false,
            isAppInForeground: true,
            hasReconnectCandidate: true,
            pairDisplayName: "Studio Mac",
            connectedAt: Date(timeIntervalSince1970: 1_710_000_000)
        )
        connectionService.snapshot = foregroundSnapshot
        await coordinator.handle(connectionSnapshot: foregroundSnapshot)

        XCTAssertEqual(locationService.startKeepaliveCallCount, 1)
        XCTAssertEqual(locationService.stopKeepaliveCallCount, 1)
        XCTAssertFalse(locationService.isKeepaliveActive)
        XCTAssertEqual(liveActivityService.states.count, 1)
        XCTAssertEqual(liveActivityService.endCallCount, 1)
    }

    func testHandleEndsLiveActivityWhenConnectionDrops() async {
        let defaults = isolatedDefaults()
        let locationService = FakeBackgroundLocationKeepaliveService(authorizationStatus: .authorizedAlways)
        let liveActivityService = FakeLiveActivityService()
        let connectionService = FakeBackgroundConnectionSnapshotService()
        let coordinator = BackgroundConnectionCoordinator(
            defaults: defaults,
            locationService: locationService,
            liveActivityService: liveActivityService,
            connectionService: connectionService
        )

        coordinator.enableFeatureAndRequestPermissions()

        let connectedSnapshot = CodexServiceConnectionSnapshot(
            isConnected: true,
            connectionPhase: .connected,
            hasAnyRunningTurn: true,
            isAppInForeground: false,
            hasReconnectCandidate: true,
            pairDisplayName: "Studio Mac",
            connectedAt: Date(timeIntervalSince1970: 1_710_000_000)
        )
        connectionService.snapshot = connectedSnapshot
        await coordinator.handle(connectionSnapshot: connectedSnapshot)

        let disconnectedSnapshot = CodexServiceConnectionSnapshot(
            isConnected: false,
            connectionPhase: .offline,
            hasAnyRunningTurn: false,
            isAppInForeground: false,
            hasReconnectCandidate: true,
            pairDisplayName: "Studio Mac",
            connectedAt: nil
        )
        connectionService.snapshot = disconnectedSnapshot
        await coordinator.handle(connectionSnapshot: disconnectedSnapshot)

        XCTAssertEqual(locationService.startKeepaliveCallCount, 1)
        XCTAssertEqual(locationService.stopKeepaliveCallCount, 0)
        XCTAssertTrue(locationService.isKeepaliveActive)
        XCTAssertEqual(liveActivityService.states.count, 1)
        XCTAssertEqual(liveActivityService.endCallCount, 1)
    }

    func testKeepaliveWakeReconnectsInBackgroundAndRestartsLiveActivity() async {
        let defaults = isolatedDefaults()
        let locationService = FakeBackgroundLocationKeepaliveService(authorizationStatus: .authorizedAlways)
        let liveActivityService = FakeLiveActivityService()
        let connectionService = FakeBackgroundConnectionSnapshotService()
        let coordinator = BackgroundConnectionCoordinator(
            defaults: defaults,
            locationService: locationService,
            liveActivityService: liveActivityService,
            connectionService: connectionService
        )

        coordinator.enableFeatureAndRequestPermissions()

        connectionService.snapshot = CodexServiceConnectionSnapshot(
            isConnected: false,
            connectionPhase: .offline,
            hasAnyRunningTurn: false,
            isAppInForeground: false,
            hasReconnectCandidate: true,
            pairDisplayName: "Studio Mac",
            connectedAt: nil
        )
        connectionService.snapshotAfterReconnect = CodexServiceConnectionSnapshot(
            isConnected: true,
            connectionPhase: .connected,
            hasAnyRunningTurn: false,
            isAppInForeground: false,
            hasReconnectCandidate: true,
            pairDisplayName: "Studio Mac",
            connectedAt: Date(timeIntervalSince1970: 1_710_000_100)
        )

        await coordinator.handle(connectionSnapshot: connectionService.snapshot)
        await coordinator.handleKeepaliveWake()

        XCTAssertEqual(connectionService.reconnectAttemptCount, 1)
        XCTAssertEqual(liveActivityService.states.last?.hostName, "Studio Mac")
        XCTAssertEqual(liveActivityService.endCallCount, 1)
    }

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "BackgroundConnectionCoordinatorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

@MainActor
private final class FakeBackgroundLocationKeepaliveService: BackgroundLocationKeepaliveControlling {
    var authorizationStatus: CLAuthorizationStatus
    var hasBackgroundKeepaliveAuthorization: Bool { authorizationStatus == .authorizedAlways }
    var hasLimitedKeepaliveAuthorization: Bool { authorizationStatus == .authorizedWhenInUse }
    private(set) var isKeepaliveActive = false
    private var wakeHandler: (@MainActor () -> Void)?

    private(set) var requestFullAuthorizationCallCount = 0
    private(set) var startKeepaliveCallCount = 0
    private(set) var stopKeepaliveCallCount = 0

    init(authorizationStatus: CLAuthorizationStatus) {
        self.authorizationStatus = authorizationStatus
    }

    func requestFullAuthorization() {
        requestFullAuthorizationCallCount += 1
    }

    func setWakeHandler(_ handler: (@MainActor () -> Void)?) {
        wakeHandler = handler
    }

    func startKeepaliveIfPossible() {
        guard hasBackgroundKeepaliveAuthorization else {
            return
        }

        guard !isKeepaliveActive else {
            return
        }

        startKeepaliveCallCount += 1
        isKeepaliveActive = true
    }

    func stopKeepalive() {
        guard isKeepaliveActive else {
            return
        }

        stopKeepaliveCallCount += 1
        isKeepaliveActive = false
    }

    func triggerWake() {
        wakeHandler?()
    }
}

@MainActor
private final class FakeLiveActivityService: LiveActivityControlling {
    private(set) var states: [BackgroundConnectionLiveActivityState] = []
    private(set) var endCallCount = 0

    func startOrUpdate(state: BackgroundConnectionLiveActivityState) async {
        states.append(state)
    }

    func end() async {
        endCallCount += 1
    }

    func endAllStale() async {
        // no-op in tests
    }
}

@MainActor
private final class FakeBackgroundConnectionSnapshotService: BackgroundConnectionSnapshotControlling {
    var snapshot = CodexServiceConnectionSnapshot(
        isConnected: false,
        connectionPhase: .offline,
        hasAnyRunningTurn: false,
        isAppInForeground: true,
        hasReconnectCandidate: false,
        pairDisplayName: nil,
        connectedAt: nil
    )
    var snapshotAfterReconnect: CodexServiceConnectionSnapshot?
    private(set) var reconnectAttemptCount = 0

    var connectionSnapshot: CodexServiceConnectionSnapshot {
        snapshot
    }

    func attemptBackgroundReconnectIfNeeded() async {
        reconnectAttemptCount += 1
        if let snapshotAfterReconnect {
            snapshot = snapshotAfterReconnect
        }
    }
}
