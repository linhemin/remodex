// FILE: BackgroundConnectionPreference.swift
// Purpose: Persists the user's background-connection opt-in state independently of CodexService.
// Layer: Model
// Exports: BackgroundConnectionPreference
// Depends on: Foundation

import Foundation

struct BackgroundConnectionPreference: Codable, Equatable, Sendable {
    var hasPresentedFirstRunPrompt: Bool
    var isEnabled: Bool

    static let defaultsKey = "codex.backgroundConnectionPreference"

    static func load(defaults: UserDefaults) -> BackgroundConnectionPreference {
        guard let data = defaults.data(forKey: defaultsKey),
              let preference = try? JSONDecoder().decode(BackgroundConnectionPreference.self, from: data) else {
            return BackgroundConnectionPreference(
                hasPresentedFirstRunPrompt: false,
                isEnabled: false
            )
        }

        return preference
    }

    func save(defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else {
            return
        }

        defaults.set(data, forKey: Self.defaultsKey)
    }
}
