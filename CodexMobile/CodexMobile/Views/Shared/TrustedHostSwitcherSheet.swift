// FILE: TrustedHostSwitcherSheet.swift
// Purpose: Shared list UI for switching between paired computers.
// Layer: View
// Exports: TrustedHostSwitcherSheet, TrustedHostRow
// Depends on: SwiftUI, CodexTrustedHostPresentation

import SwiftUI

struct TrustedHostRow: View {
    let host: CodexTrustedHostPresentation
    var showsChevron = false
    var trailingLabel: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: host.platform.symbolName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(Color.primary.opacity(0.06))
                )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(host.name)
                        .font(AppFont.subheadline(weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if host.isCurrent {
                        Text("Current")
                            .font(AppFont.caption(weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.primary.opacity(0.07))
                            )
                    }
                }

                if let systemName = host.systemName, !systemName.isEmpty {
                    Text(systemName)
                        .font(AppFont.caption())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let detail = host.detail, !detail.isEmpty {
                    Text(detail)
                        .font(AppFont.caption())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if let lastActivityAt = host.lastActivityAt {
                    Text(lastActivityAt, style: .relative)
                        .font(AppFont.caption())
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 8)

            if let trailingLabel, !trailingLabel.isEmpty {
                Text(trailingLabel)
                    .font(AppFont.caption(weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(AppFont.caption(weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemFill).opacity(host.isCurrent ? 0.55 : 0.32))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(host.isCurrent ? 0.09 : 0.04), lineWidth: 1)
        )
    }
}

struct TrustedHostSwitcherSheet: View {
    let hosts: [CodexTrustedHostPresentation]
    let onSelect: (String) -> Void
    let onPairNewComputer: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Paired Computers")
                            .font(AppFont.title3(weight: .semibold))
                            .foregroundStyle(.primary)

                        Text("Choose the computer this iPhone should control next.")
                            .font(AppFont.subheadline())
                            .foregroundStyle(.secondary)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .adaptiveGlass(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                    VStack(spacing: 10) {
                        ForEach(hosts) { host in
                            Button {
                                onSelect(host.deviceId)
                                dismiss()
                            } label: {
                                TrustedHostRow(host: host, trailingLabel: host.isCurrent ? nil : "Use")
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Button {
                        dismiss()
                        onPairNewComputer()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "qrcode.viewfinder")
                            Text("Pair New Computer")
                        }
                        .font(AppFont.body(weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(.primary)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color(.tertiarySystemFill).opacity(0.7))
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)
            }
            .navigationTitle("Switch Computer")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
