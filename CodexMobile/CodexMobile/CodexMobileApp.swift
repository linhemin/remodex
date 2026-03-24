// FILE: CodexMobileApp.swift
// Purpose: App entry point and root dependency wiring for CodexService.
// Layer: App
// Exports: CodexMobileApp

import SwiftUI

@MainActor
@main
struct CodexMobileApp: App {
    @UIApplicationDelegateAdaptor(CodexMobileAppDelegate.self) private var appDelegate
    @State private var codexService: CodexService
    @State private var backgroundConnectionCoordinator: BackgroundConnectionCoordinator

    init() {
        let service = CodexService()
        let backgroundConnectionCoordinator = BackgroundConnectionCoordinator(connectionService: service)
        service.configureNotifications()
        _codexService = State(initialValue: service)
        _backgroundConnectionCoordinator = State(initialValue: backgroundConnectionCoordinator)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(codexService)
                .environment(backgroundConnectionCoordinator)
                .task {
                    await codexService.requestNotificationPermissionOnFirstLaunchIfNeeded()
                }
                .onOpenURL { url in
                    Task { @MainActor in
                        guard CodexService.legacyGPTLoginCallbackEnabled else {
                            return
                        }
                        await codexService.handleGPTLoginCallbackURL(url)
                    }
                }
        }
    }
}
