// FILE: BackgroundConnectionCoordinator.swift
// Purpose: Owns the background-connection preference and coordinates location keepalive plus Live Activity updates.
// Layer: Service
// Exports: BackgroundConnectionCoordinator
// Depends on: Foundation, Observation, CoreLocation

import CoreLocation
import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class BackgroundConnectionCoordinator {
    private let defaults: UserDefaults
    private let locationService: BackgroundLocationKeepaliveControlling
    private let liveActivityService: LiveActivityControlling
    private let connectionService: BackgroundConnectionSnapshotControlling?
    private var latestSnapshot: CodexServiceConnectionSnapshot?

    private(set) var preference: BackgroundConnectionPreference
    private(set) var authorizationStatus: CLAuthorizationStatus
    private(set) var isKeepaliveActive: Bool

    init(
        defaults: UserDefaults = .standard,
        locationService: BackgroundLocationKeepaliveControlling? = nil,
        liveActivityService: LiveActivityControlling? = nil,
        connectionService: BackgroundConnectionSnapshotControlling? = nil
    ) {
        self.defaults = defaults
        self.locationService = locationService ?? BackgroundLocationKeepaliveService()
        self.liveActivityService = liveActivityService ?? LiveActivityService()
        self.connectionService = connectionService
        self.preference = BackgroundConnectionPreference.load(defaults: defaults)
        self.authorizationStatus = self.locationService.authorizationStatus
        self.isKeepaliveActive = self.locationService.isKeepaliveActive
        self.latestSnapshot = connectionService?.connectionSnapshot

        self.locationService.setWakeHandler { [weak self] in
            guard let self else {
                return
            }

            Task { @MainActor [weak self] in
                await self?.handleKeepaliveWake()
            }
        }

        // Clean up stale Live Activities from previous app sessions on launch.
        Task { @MainActor [liveActivityService = self.liveActivityService] in
            await liveActivityService.endAllStale()
        }
    }

    var shouldPresentFirstRunPrompt: Bool {
        !preference.hasPresentedFirstRunPrompt
    }

    var isEnabled: Bool {
        preference.isEnabled
    }

    var hasBackgroundKeepaliveAuthorization: Bool {
        authorizationStatus == .authorizedAlways
    }

    var hasLimitedKeepaliveAuthorization: Bool {
        authorizationStatus == .authorizedWhenInUse
    }

    func markFirstRunPromptPresented() {
        guard !preference.hasPresentedFirstRunPrompt else {
            return
        }

        preference.hasPresentedFirstRunPrompt = true
        savePreference()
    }

    func enableFeatureAndRequestPermissions() {
        preference.isEnabled = true
        preference.hasPresentedFirstRunPrompt = true
        savePreference()
        locationService.requestFullAuthorization()
        refreshLocationState()
    }

    func disableFeature() async {
        preference.isEnabled = false
        savePreference()
        locationService.stopKeepalive()
        refreshLocationState()
        await liveActivityService.end()
    }

    func refreshLocationState() {
        authorizationStatus = locationService.authorizationStatus
        isKeepaliveActive = locationService.isKeepaliveActive
    }

    func handle(connectionSnapshot snapshot: CodexServiceConnectionSnapshot) async {
        latestSnapshot = snapshot
        await reconcileState(shouldAttemptReconnect: false)
    }

    private func savePreference() {
        preference.save(defaults: defaults)
    }

    func handleKeepaliveWake() async {
        await reconcileState(shouldAttemptReconnect: true)
    }

    private func reconcileState(shouldAttemptReconnect: Bool) async {
        refreshLocationState()

        var snapshot = latestSnapshot ?? connectionService?.connectionSnapshot

        guard preference.isEnabled else {
            locationService.stopKeepalive()
            refreshLocationState()
            await liveActivityService.end()
            return
        }

        if shouldAttemptReconnect,
           let connectionService,
           var currentSnapshot = snapshot,
           !currentSnapshot.isAppInForeground,
           hasBackgroundKeepaliveAuthorization,
           currentSnapshot.hasReconnectCandidate,
           !currentSnapshot.isConnected {
            await connectionService.attemptBackgroundReconnectIfNeeded()
            currentSnapshot = connectionService.connectionSnapshot
            latestSnapshot = currentSnapshot
            snapshot = currentSnapshot
        }

        guard let snapshot else {
            locationService.stopKeepalive()
            refreshLocationState()
            await liveActivityService.end()
            return
        }

        let shouldKeepalive = !snapshot.isAppInForeground
            && hasBackgroundKeepaliveAuthorization
            && (snapshot.isConnected || snapshot.hasReconnectCandidate)

        if shouldKeepalive {
            locationService.startKeepaliveIfPossible()
        } else {
            locationService.stopKeepalive()
        }
        refreshLocationState()

        guard shouldPresentLiveActivity(for: snapshot),
              let state = liveActivityState(for: snapshot) else {
            await liveActivityService.end()
            return
        }

        await liveActivityService.startOrUpdate(state: state)
    }

    private func shouldPresentLiveActivity(for snapshot: CodexServiceConnectionSnapshot) -> Bool {
        snapshot.isConnected
            && !snapshot.isAppInForeground
            && hasBackgroundKeepaliveAuthorization
    }

    private func liveActivityState(for snapshot: CodexServiceConnectionSnapshot) -> BackgroundConnectionLiveActivityState? {
        guard let connectedAt = snapshot.connectedAt else {
            return nil
        }

        let normalizedHostName = snapshot.pairDisplayName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveHostName: String
        if let normalizedHostName, !normalizedHostName.isEmpty {
            effectiveHostName = normalizedHostName
        } else {
            effectiveHostName = "Paired Mac"
        }
        return BackgroundConnectionLiveActivityState.make(
            hostName: effectiveHostName,
            connectedAt: connectedAt
        )
    }
}
