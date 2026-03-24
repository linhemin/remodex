// FILE: LiveActivityService.swift
// Purpose: Starts, updates, and ends the background connection Live Activity without leaking ActivityKit into views.
// Layer: Service
// Exports: LiveActivityService, LiveActivityControlling
// Depends on: ActivityKit, Foundation

import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

@MainActor
protocol LiveActivityControlling: AnyObject {
    func startOrUpdate(state: BackgroundConnectionLiveActivityState) async
    func end() async
    func endAllStale() async
}

@MainActor
final class LiveActivityService: LiveActivityControlling {
#if canImport(ActivityKit)
    private var activity: Activity<BackgroundConnectionLiveActivityAttributes>?
#endif

    func startOrUpdate(state: BackgroundConnectionLiveActivityState) async {
#if canImport(ActivityKit)
        guard #available(iOS 16.2, *),
              ActivityAuthorizationInfo().areActivitiesEnabled else {
            return
        }

        let contentState = state.contentState
        if let activity {
            await activity.update(ActivityContent(state: contentState, staleDate: nil))
            return
        }

        // End any stale activities from previous launches before creating a new one.
        await endAllStale()

        activity = try? Activity.request(
            attributes: BackgroundConnectionLiveActivityAttributes(name: "Background Connection"),
            content: ActivityContent(state: contentState, staleDate: nil),
            pushType: nil
        )
#else
        _ = state
#endif
    }

    func end() async {
#if canImport(ActivityKit)
        guard #available(iOS 16.2, *) else {
            return
        }

        if let activity {
            await activity.end(nil, dismissalPolicy: .immediate)
            self.activity = nil
        }

        // Also sweep any orphaned activities from previous sessions.
        await endAllStale()
#endif
    }

    func endAllStale() async {
#if canImport(ActivityKit)
        guard #available(iOS 16.2, *) else {
            return
        }

        for ongoing in Activity<BackgroundConnectionLiveActivityAttributes>.activities {
            // Skip the one we're actively managing.
            if ongoing.id == activity?.id {
                continue
            }
            await ongoing.end(nil, dismissalPolicy: .immediate)
        }
#endif
    }
}
