// FILE: CodexService+TrustedPairPresentation.swift
// Purpose: Derives UI-facing summary and list models for paired computers.
// Layer: Service extension
// Exports: CodexTrustedPairPresentation, CodexTrustedHostPresentation, CodexService trusted-host helpers
// Depends on: Foundation

import Foundation

struct CodexTrustedPairPresentation: Equatable, Sendable {
    let deviceId: String?
    let title: String
    let name: String
    let systemName: String?
    let detail: String?
    let platform: CodexHostPlatform
    let pairedDeviceCount: Int
}

struct CodexTrustedHostPresentation: Equatable, Identifiable, Sendable {
    let deviceId: String
    let name: String
    let systemName: String?
    let detail: String?
    let platform: CodexHostPlatform
    let isCurrent: Bool
    let isConnected: Bool
    let lastActivityAt: Date?

    var id: String { deviceId }
}

extension CodexHostPlatform {
    var displayName: String {
        switch self {
        case .macOS:
            return "macOS"
        case .windows:
            return "Windows"
        case .linux:
            return "Linux"
        case .unknown:
            return "Computer"
        }
    }

    var symbolName: String {
        switch self {
        case .macOS:
            return "desktopcomputer"
        case .windows:
            return "laptopcomputer"
        case .linux:
            return "terminal"
        case .unknown:
            return "desktopcomputer"
        }
    }
}

enum SidebarMacNicknameStore {
    private static let keyPrefix = "codex.sidebarMacNickname."

    static func nickname(for deviceId: String?) -> String {
        guard let storageKey = storageKey(for: deviceId) else {
            return ""
        }

        return UserDefaults.standard.string(forKey: storageKey) ?? ""
    }

    static func setNickname(_ nickname: String, for deviceId: String?) {
        guard let storageKey = storageKey(for: deviceId) else {
            return
        }

        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: storageKey)
            return
        }

        UserDefaults.standard.set(trimmed, forKey: storageKey)
    }

    private static func storageKey(for deviceId: String?) -> String? {
        guard let deviceId = deviceId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !deviceId.isEmpty else {
            return nil
        }

        return keyPrefix + deviceId
    }
}

extension CodexService {
    var pairedHostCount: Int {
        trustedMacRegistry.records.count
    }

    var trustedPairPresentation: CodexTrustedPairPresentation? {
        guard let trustedHost = visibleTrustedHostRecord else {
            return nil
        }

        let macName = nonEmptyTrimmedString(trustedHost.displayName)
        let fingerprint = trustedPairFingerprint
        let fallbackName = "\(trustedHostPlatform(for: trustedHost).displayName) \(fingerprint ?? "")"
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let systemName = macName ?? fallbackName
        let nickname = SidebarMacNicknameStore.nickname(for: trustedPairDeviceId)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveName = nickname.isEmpty ? systemName : nickname

        return CodexTrustedPairPresentation(
            deviceId: trustedPairDeviceId,
            title: trustedPairTitle,
            name: effectiveName,
            systemName: nickname.isEmpty ? nil : systemName,
            detail: trustedPairDetail(displayName: macName, fingerprint: fingerprint),
            platform: trustedHostPlatform(for: trustedHost),
            pairedDeviceCount: pairedHostCount
        )
    }

    var trustedHostPresentations: [CodexTrustedHostPresentation] {
        let activeDeviceId = activeTrustedHostDeviceId

        return trustedMacRegistry.records.values
            .sorted { lhs, rhs in
                let lhsIsActive = lhs.macDeviceId == activeDeviceId
                let rhsIsActive = rhs.macDeviceId == activeDeviceId
                if lhsIsActive != rhsIsActive {
                    return lhsIsActive
                }

                let lhsActivity = lhs.lastUsedAt ?? lhs.lastResolvedAt ?? lhs.lastPairedAt
                let rhsActivity = rhs.lastUsedAt ?? rhs.lastResolvedAt ?? rhs.lastPairedAt
                if lhsActivity != rhsActivity {
                    return lhsActivity > rhsActivity
                }

                return lhs.macDeviceId < rhs.macDeviceId
            }
            .map { record in
                let displayName = trustedHostDisplayName(for: record)
                let nickname = SidebarMacNicknameStore.nickname(for: record.macDeviceId)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let effectiveName = nickname.isEmpty ? displayName.systemName : nickname
                let detail = trustedHostListDetail(for: record)

                return CodexTrustedHostPresentation(
                    deviceId: record.macDeviceId,
                    name: effectiveName,
                    systemName: nickname.isEmpty ? nil : displayName.systemName,
                    detail: detail,
                    platform: trustedHostPlatform(for: record),
                    isCurrent: record.macDeviceId == activeDeviceId,
                    isConnected: record.macDeviceId == normalizedRelayMacDeviceId && isConnected,
                    lastActivityAt: record.lastUsedAt ?? record.lastResolvedAt ?? record.lastPairedAt
                )
            }
    }

    func selectTrustedHost(deviceId: String) {
        guard trustedMacRegistry.records[deviceId] != nil else {
            return
        }

        setSelectedHostDeviceId(deviceId)
        SecureStore.writeString(deviceId, for: CodexSecureKeys.lastTrustedMacDeviceId)
        lastTrustedMacDeviceId = deviceId

        if normalizedRelayMacDeviceId != deviceId {
            if isConnected {
                secureConnectionState = .trustedMac
            } else {
                resetSecureTransportState()
            }
        }
    }
}

private extension CodexService {
    var activeTrustedHostDeviceId: String? {
        normalizedRelayMacDeviceId ?? preferredTrustedMacDeviceId
    }

    var visibleTrustedHostRecord: CodexTrustedMacRecord? {
        if let activeTrustedHostDeviceId {
            return trustedMacRegistry.records[activeTrustedHostDeviceId]
        }
        return nil
    }

    var trustedPairDeviceId: String? {
        activeTrustedHostDeviceId
    }

    var trustedPairFingerprint: String? {
        nonEmptyTrimmedString(secureMacFingerprint)
            ?? normalizedRelayMacIdentityPublicKey.map { codexSecureFingerprint(for: $0) }
            ?? visibleTrustedHostRecord.map { codexSecureFingerprint(for: $0.macIdentityPublicKey) }
    }

    var trustedPairTitle: String {
        if isConnected || secureConnectionState == .encrypted {
            return "Current Computer"
        }

        switch secureConnectionState {
        case .handshaking:
            return "Pairing Computer"
        case .liveSessionUnresolved, .reconnecting, .trustedMac:
            return "Ready Computer"
        case .rePairRequired:
            return "Previous Computer"
        case .updateRequired, .notPaired:
            return "Paired Computer"
        case .encrypted:
            return "Current Computer"
        }
    }

    func trustedPairDetail(displayName: String?, fingerprint: String?) -> String? {
        var parts: [String] = [secureConnectionState.statusLabel]
        if pairedHostCount > 1 {
            parts.append("\(pairedHostCount) paired")
        }
        if displayName != nil, let fingerprint {
            parts.append(fingerprint)
        }
        let joined = parts.joined(separator: " · ")
        return joined.isEmpty ? nil : joined
    }

    func trustedHostDisplayName(for record: CodexTrustedMacRecord) -> (systemName: String, displayName: String?) {
        let displayName = nonEmptyTrimmedString(record.displayName)
        let fingerprint = codexSecureFingerprint(for: record.macIdentityPublicKey)
        let systemName = displayName
            ?? "\(trustedHostPlatform(for: record).displayName) \(fingerprint)"
        return (systemName: systemName, displayName: displayName)
    }

    func trustedHostPlatform(for record: CodexTrustedMacRecord) -> CodexHostPlatform {
        record.platform ?? .unknown
    }

    func trustedHostListDetail(for record: CodexTrustedMacRecord) -> String? {
        var parts: [String] = [trustedHostPlatform(for: record).displayName]

        if record.macDeviceId == normalizedRelayMacDeviceId, isConnected {
            parts.append("Connected")
        } else if record.macDeviceId == preferredTrustedMacDeviceId {
            parts.append("Current")
        } else if record.relayURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            parts.append("Ready")
        }

        let fingerprint = codexSecureFingerprint(for: record.macIdentityPublicKey)
        parts.append(fingerprint)
        return parts.joined(separator: " · ")
    }

    func nonEmptyTrimmedString(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }
}
