// UpgradeSheet.swift
// WraithVPN
//
// Contextual upgrade prompt shown when a Haven user tries to use VPN features,
// or an Enclave user tries to use Enclave+ features. Explains what each tier
// provides and routes to the paywall.

import SwiftUI

enum UpgradeReason: Identifiable {
    var id: Int { highlightTier }

    case vpnRequiresEnclave     // Haven → Enclave
    case multiHopRequiresPlus   // Enclave → Enclave+

    var title: String {
        switch self {
        case .vpnRequiresEnclave:   return "VPN Requires Enclave"
        case .multiHopRequiresPlus: return "Multi-Hop Requires Enclave+"
        }
    }

    var subtitle: String {
        switch self {
        case .vpnRequiresEnclave:
            return "Your DNS protection and ad blocking are active. Add a full WireGuard VPN tunnel with Enclave."
        case .multiHopRequiresPlus:
            return "Your single-hop VPN is active. Enclave+ routes your traffic through two separate nodes — neither hop can see both who you are and what you're doing."
        }
    }

    var highlightTier: Int { // 0 = Haven, 1 = Enclave, 2 = Enclave+
        switch self {
        case .vpnRequiresEnclave:   return 1
        case .multiHopRequiresPlus: return 2
        }
    }
}

struct UpgradeSheet: View {

    let reason: UpgradeReason
    @Environment(\.dismiss) private var dismiss
    @State private var showPaywall = false

    // MARK: - Tier definitions

    private struct Tier {
        let name: String
        let price: String
        let features: [String]
        let accent: Color
    }

    private let tiers: [Tier] = [
        Tier(
            name: "Haven",
            price: "$1.99/mo",
            features: [
                "DNS ad & tracker blocking",
                "5 protection levels",
                "Works on all apps"
            ],
            accent: Color(hex: "#38bdf8")
        ),
        Tier(
            name: "Enclave",
            price: "$4.99/mo",
            features: [
                "Everything in Haven",
                "WireGuard VPN tunnel",
                "7 global exit nodes",
                "Kill switch"
            ],
            accent: Color.kfAccentPurple
        ),
        Tier(
            name: "Enclave+",
            price: "$9.99/mo",
            features: [
                "Everything in Enclave",
                "Double-hop multi-hop routing",
                "Entry + exit node separation",
                "Maximum anonymity"
            ],
            accent: Color(hex: "#f59e0b")
        ),
    ]

    // MARK: - Body

    var body: some View {
        ZStack {
            Color(hex: "#0d0f14").ignoresSafeArea()

            VStack(spacing: 0) {
                // Handle
                Capsule()
                    .fill(Color.kfBorder)
                    .frame(width: 40, height: 4)
                    .padding(.top, 12)
                    .padding(.bottom, 20)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: KFSpacing.xl) {
                        // Header
                        VStack(spacing: KFSpacing.sm) {
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(tiers[reason.highlightTier].accent)

                            Text(reason.title)
                                .font(KFFont.heading(22))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)

                            Text(reason.subtitle)
                                .font(KFFont.body(15))
                                .foregroundStyle(Color.kfTextSecondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, KFSpacing.lg)

                        // Tier cards
                        VStack(spacing: KFSpacing.sm) {
                            ForEach(tiers.indices, id: \.self) { i in
                                tierCard(tiers[i], highlight: i == reason.highlightTier)
                            }
                        }
                        .padding(.horizontal, KFSpacing.lg)

                        // CTA
                        VStack(spacing: KFSpacing.sm) {
                            Button {
                                showPaywall = true
                            } label: {
                                Text("Upgrade to \(tiers[reason.highlightTier].name)")
                                    .font(KFFont.caption(16, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(tiers[reason.highlightTier].accent)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            }

                            Button("Not now") {
                                dismiss()
                            }
                            .font(KFFont.body(15))
                            .foregroundStyle(Color.kfTextMuted)
                        }
                        .padding(.horizontal, KFSpacing.lg)
                        .padding(.bottom, KFSpacing.xl)
                    }
                }
            }
        }
        .sheet(isPresented: $showPaywall) {
            NavigationStack {
                PaywallView()
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Tier card

    private func tierCard(_ tier: Tier, highlight: Bool) -> some View {
        VStack(alignment: .leading, spacing: KFSpacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tier.name)
                        .font(KFFont.heading(16))
                        .foregroundStyle(highlight ? tier.accent : .white)
                    Text(tier.price)
                        .font(KFFont.caption(13))
                        .foregroundStyle(Color.kfTextMuted)
                }
                Spacer()
                if highlight {
                    Text("UPGRADE TO THIS")
                        .font(KFFont.caption(10, weight: .bold))
                        .kerning(1)
                        .foregroundStyle(tier.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(tier.accent.opacity(0.15))
                        .clipShape(Capsule())
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(tier.features, id: \.self) { feature in
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(highlight ? tier.accent : Color.kfTextMuted)
                        Text(feature)
                            .font(KFFont.body(13))
                            .foregroundStyle(highlight ? Color.kfTextSecondary : Color.kfTextMuted)
                    }
                }
            }
        }
        .padding(KFSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.kfSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(highlight ? tier.accent.opacity(0.5) : Color.kfBorder, lineWidth: highlight ? 1.5 : 1)
                )
        )
    }
}
