// FILE: BackgroundLocationKeepaliveService.swift
// Purpose: Wraps CLLocationManager for the background keepalive feature without coupling callers to CoreLocation APIs.
// Layer: Service
// Exports: BackgroundLocationKeepaliveService, BackgroundLocationManaging
// Depends on: CoreLocation, Foundation

import CoreLocation
import Foundation

protocol BackgroundLocationManaging: AnyObject {
    var currentAuthorizationStatus: CLAuthorizationStatus { get }
    var delegate: CLLocationManagerDelegate? { get set }
    var allowsBackgroundLocationUpdates: Bool { get set }
    var pausesLocationUpdatesAutomatically: Bool { get set }

    func requestWhenInUseAuthorization()
    func requestAlwaysAuthorization()
    func startUpdatingLocation()
    func stopUpdatingLocation()
    func startMonitoringSignificantLocationChanges()
    func stopMonitoringSignificantLocationChanges()
}

extension CLLocationManager: BackgroundLocationManaging {
    var currentAuthorizationStatus: CLAuthorizationStatus {
        if #available(iOS 14.0, *) {
            return self.authorizationStatus
        }
        return Self.authorizationStatus()
    }
}

@MainActor
protocol BackgroundLocationKeepaliveControlling: AnyObject {
    var authorizationStatus: CLAuthorizationStatus { get }
    var hasBackgroundKeepaliveAuthorization: Bool { get }
    var hasLimitedKeepaliveAuthorization: Bool { get }
    var isKeepaliveActive: Bool { get }

    func requestFullAuthorization()
    func startKeepaliveIfPossible()
    func stopKeepalive()
    func setWakeHandler(_ handler: (@MainActor () -> Void)?)
}

@MainActor
final class BackgroundLocationKeepaliveService: NSObject, BackgroundLocationKeepaliveControlling, CLLocationManagerDelegate {
    private let manager: BackgroundLocationManaging
    private var wakeHandler: (@MainActor () -> Void)?

    private(set) var isKeepaliveActive = false

    init(manager: BackgroundLocationManaging = CLLocationManager()) {
        self.manager = manager
        super.init()
        self.manager.delegate = self
    }

    var authorizationStatus: CLAuthorizationStatus {
        manager.currentAuthorizationStatus
    }

    var hasBackgroundKeepaliveAuthorization: Bool {
        authorizationStatus == .authorizedAlways
    }

    var hasLimitedKeepaliveAuthorization: Bool {
        authorizationStatus == .authorizedWhenInUse
    }

    func requestFullAuthorization() {
        switch authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
        default:
            break
        }
    }

    func setWakeHandler(_ handler: (@MainActor () -> Void)?) {
        wakeHandler = handler
    }

    func startKeepaliveIfPossible() {
        guard hasBackgroundKeepaliveAuthorization, !isKeepaliveActive else {
            return
        }

        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.startUpdatingLocation()
        manager.startMonitoringSignificantLocationChanges()
        isKeepaliveActive = true
    }

    func stopKeepalive() {
        guard isKeepaliveActive else {
            return
        }

        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
        manager.allowsBackgroundLocationUpdates = false
        manager.pausesLocationUpdatesAutomatically = true
        isKeepaliveActive = false
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if authorizationStatus == .authorizedWhenInUse {
            self.manager.requestAlwaysAuthorization()
        }
        wakeHandler?()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        wakeHandler?()
    }
}
