// MacUpgradeSheet.swift
// WraithVPNMac
//
// macOS port of UpgradeSheet. Sheet/popover with tier comparison + upgrade button.

import SwiftUI

struct MacUpgradeSheet: View {

    let reason: UpgradeReason
    @EnvironmentObject var storeKit: StoreKitManager
    @Environment(\.dismiss) private var dismiss
    @State private var showTokenEntry = false

    private struct MacTier {
        let name: String
        let price: String
        let features: [String]
        let accent: Color
    }

    private let tiers: [MacTier] = [
        MacTier(name: "Haven", price: "$1.99/mo",
                features: ["DNS ad & tracker blocking", "5 protection levels", "Works on all apps"],
                accent: Color(hex: "#38bdf8")),
        MacTier(name: "Enclave", price: "$4.99/mo",
                features: ["Everything in Haven", "WireGuard VPN tunnel", "7 global exit nodes", "Kill switch"],
                accent: Color.kfAccentPurple),
        MacTier(name: "Enclave+", price: "$9.99/mo",
                features: ["Everything in Enclave", "Double-hop multi-hop routing", "Maximum anonymity"],
                accent: Color(hex: "#f59e0b")),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(tiers[reason.highlightTier].accent)
                Text(reason.title)
                    .font(KFFont.heading(16))
                    .foregroundStyle(.white)
                Spacer()
                Button("Not now") { dismiss() }
                    .foregroundStyle(Color.kfTextMuted)
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.kfSurface)

            Divider().background(Color.kfBorder)

            VStack(spacing: 16) {
                Text(reason.subtitle)
                    .font(KFFont.body(13))
                    .foregroundStyle(Color.kfTextSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(tiers.indices, id: \.self) { i in
                    let tier = tiers[i]
                    let highlight = i == reason.highlightTier
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tier.name)
                                    .font(KFFont.heading(14))
                                    .foregroundStyle(highlight ? tier.accent : .white)
                                Text(tier.price)
                                    .font(KFFont.caption(12))
                                    .foregroundStyle(Color.kfTextMuted)
                            }
                            Spacer()
                            if highlight {
                                Text("UPGRADE TO THIS")
                                    .font(.system(size: 9, weight: .bold))
                                    .kerning(1)
                                    .foregroundStyle(tier.accent)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(tier.accent.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                        }
                        ForEach(tier.features, id: \.self) { feature in
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(highlight ? tier.accent : Color.kfTextMuted)
                                Text(feature)
                                    .font(KFFont.body(12))
                                    .foregroundStyle(highlight ? Color.kfTextSecondary : Color.kfTextMuted)
                            }
                        }
                    }
                    .padding(12)
                    .background(Color.kfSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(highlight ? tier.accent.opacity(0.5) : Color.kfBorder, lineWidth: highlight ? 1.5 : 1)
                    )
                }

                Button {
                    showTokenEntry = true
                } label: {
                    Text("Upgrade to \(tiers[reason.highlightTier].name)")
                        .font(KFFont.caption(13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(tiers[reason.highlightTier].accent)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        }
        .frame(width: 400)
        .background(Color.kfBackground)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showTokenEntry) {
            TokenEntryView().environmentObject(storeKit)
        }
        .onChange(of: storeKit.hasMultiHop) { _, hasIt in
            if hasIt && reason == .multiHopRequiresPlus { dismiss() }
        }
        .onChange(of: storeKit.hasVPN) { _, hasIt in
            if hasIt && reason == .vpnRequiresEnclave { dismiss() }
        }
    }
}
