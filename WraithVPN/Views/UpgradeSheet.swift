// UpgradeSheet.swift
// WraithVPN
//
// Contextual upgrade prompt shown when a Haven user tries to use VPN features,
// or an Enclave user tries to use Enclave+ features. Explains what each tier
// provides and routes to the paywall.

import SwiftUI
import StoreKit

enum UpgradeReason: Identifiable {
    var id: Int { highlightTier }

    case vpnRequiresEnclave       // Haven → Enclave
    case multiHopRequiresSovereign // Enclave → Sovereign
    case storageRequiresSovereign  // Enclave → Sovereign

    var title: String {
        switch self {
        case .vpnRequiresEnclave:        return "VPN Requires Enclave"
        case .multiHopRequiresSovereign: return "Multi-Hop Requires Sovereign"
        case .storageRequiresSovereign:  return "Storage Requires Sovereign"
        }
    }

    var subtitle: String {
        switch self {
        case .vpnRequiresEnclave:
            return "Your DNS protection is active. Add a full WireGuard VPN tunnel with Enclave for traffic privacy."
        case .multiHopRequiresSovereign:
            return "Your single-hop VPN is active. Sovereign routes your traffic through two nodes — maximum privacy where neither hop knows both your identity and destination."
        case .storageRequiresSovereign:
            return "Upgrade to Sovereign to unlock 1 TB of encrypted cloud storage and cross-device sync with Vaultyx."
        }
    }

    var highlightTier: Int { // 0 = Enclave, 1 = Sovereign
        switch self {
        case .vpnRequiresEnclave:        return 0
        case .multiHopRequiresSovereign: return 1
        case .storageRequiresSovereign:  return 1
        }
    }
}

struct UpgradeSheet: View {

    let reason: UpgradeReason
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var storeKit: StoreKitManager
    @State private var showPaywall = false

    // MARK: - Tier definitions

    private struct Tier {
        let name: String
        let productGroup: [WraithProduct]
        let features: [String]
        let accent: Color
    }

    private let tiers: [Tier] = [
        Tier(
            name: "Enclave",
            productGroup: [.enclaveMonthly, .enclaveAnnual],
            features: [
                "Haven DNS protection",
                "Single-hop WireGuard VPN",
                "10 global WraithGate nodes",
                "Kill switch · 5 devices"
            ],
            accent: Color.kfAccentPurple
        ),
        Tier(
            name: "Sovereign",
            productGroup: [.sovereignMonthly, .sovereignAnnual],
            features: [
                "Everything in Enclave",
                "Multi-hop routing (2 nodes)",
                "Entry + exit node separation",
                "1 TB Vaultyx storage",
                "Cross-device sync"
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
                    .environmentObject(storeKit)
            }
        }
        .preferredColorScheme(.dark)
        // Auto-dismiss once the user acquires the required capability
        // (e.g. they entered a token or upgraded inside the nested PaywallView).
        .onChange(of: storeKit.hasMultiHop) { _, hasIt in
            if hasIt && reason == .multiHopRequiresSovereign { dismiss() }
        }
        .onChange(of: storeKit.hasSovereign) { _, hasIt in
            if hasIt && reason == .storageRequiresSovereign { dismiss() }
        }
        .onChange(of: storeKit.hasVPN) { _, hasIt in
            if hasIt && reason == .vpnRequiresEnclave { dismiss() }
        }
    }

    // MARK: - Tier card

    private func tierCard(_ tier: Tier, highlight: Bool) -> some View {
        VStack(alignment: .leading, spacing: KFSpacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tier.name)
                        .font(KFFont.heading(16))
                        .foregroundStyle(highlight ? tier.accent : .white)
                    Text(priceText(for: tier))
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

    private func priceText(for tier: Tier) -> String {
        let monthlyProduct = storeKit.products.first {
            $0.id == tier.productGroup.first(where: { $0.period == .monthly })?.rawValue
        }
        let annualProduct = storeKit.products.first {
            $0.id == tier.productGroup.first(where: { $0.period == .annual })?.rawValue
        }

        switch (monthlyProduct, annualProduct) {
        case let (monthly?, annual?):
            return "\(monthly.displayPrice)/mo • \(annual.displayPrice)/yr"
        case let (monthly?, nil):
            return "\(monthly.displayPrice)/mo"
        case let (nil, annual?):
            return "\(annual.displayPrice)/yr"
        case (nil, nil):
            return "Pricing unavailable"
        }
    }
}
