// FILE: BackgroundConnectionPreferenceTests.swift
// Purpose: Verifies background-connection preferences persist independently and CodexService exposes a read-only connection snapshot.
// Layer: Unit Test
// Exports: BackgroundConnectionPreferenceTests
// Depends on: XCTest, CodexMobile

import XCTest
@testable import CodexMobile

@MainActor
final class BackgroundConnectionPreferenceTests: XCTestCase {
    private static var retainedServices: [CodexService] = []

    func testPreferenceRoundTripsFirstPromptAndEnablement() {
        let suiteName = "BackgroundConnectionPreferenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)

        var preference = BackgroundConnectionPreference.load(defaults: defaults)

        XCTAssertFalse(preference.hasPresentedFirstRunPrompt)
        XCTAssertFalse(preference.isEnabled)

        preference.hasPresentedFirstRunPrompt = true
        preference.isEnabled = true
        preference.save(defaults: defaults)

        let reloaded = BackgroundConnectionPreference.load(defaults: defaults)

        XCTAssertTrue(reloaded.hasPresentedFirstRunPrompt)
        XCTAssertTrue(reloaded.isEnabled)
    }

    func testCodexServiceConnectionSnapshotReflectsCoreConnectionState() {
        let service = makeService()
        service.isConnected = true
        service.isAppInForeground = false
        service.runningThreadIDs = ["thread-running"]
        service.isLoadingThreads = true

        let snapshot = service.connectionSnapshot

        XCTAssertTrue(snapshot.isConnected)
        XCTAssertEqual(snapshot.connectionPhase, .loadingChats)
        XCTAssertTrue(snapshot.hasAnyRunningTurn)
        XCTAssertFalse(snapshot.isAppInForeground)
    }

    private func makeService() -> CodexService {
        let suiteName = "BackgroundConnectionPreferenceTests.Service.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        let service = CodexService(defaults: defaults)
        Self.retainedServices.append(service)
        return service
    }
}
