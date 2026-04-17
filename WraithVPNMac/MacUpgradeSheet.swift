// MacUpgradeSheet.swift
// WraithVPNMac
//
// macOS subscription paywall — 3-tier ladder (Haven Pro / Enclave / Enclave+)
// with monthly/annual toggle, live App Store prices, and feature bullets.
// Sheet is ~420 pt wide; tiers stack vertically for readability.

import SwiftUI
import StoreKit

// MARK: - UpgradeReason (Mac-side definition; mirrors WraithVPN/Views/UpgradeSheet.swift)

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

    var highlightTier: Int { // 0 = Haven Pro, 1 = Enclave, 2 = Enclave+
        switch self {
        case .vpnRequiresEnclave:   return 1
        case .multiHopRequiresPlus: return 2
        }
    }
}

// MARK: - MacUpgradeSheet

struct MacUpgradeSheet: View {

    let reason: UpgradeReason
    @EnvironmentObject var storeKit: StoreKitManager
    @Environment(\.dismiss) private var dismiss

    // Default selection: the tier the reason points at, annual billing
    @State private var selectedTier: WraithTier
    @State private var showAnnual: Bool = true
    @State private var showTokenEntry = false

    init(reason: UpgradeReason) {
        self.reason = reason
        // Map highlightTier index → WraithTier
        let tiers: [WraithTier] = [.havenPro, .enclave, .enclavePlus]
        let idx = min(reason.highlightTier, tiers.count - 1)
        _selectedTier = State(initialValue: tiers[idx])
    }

    // MARK: - Derived

    private var selectedProduct: WraithProduct {
        switch (selectedTier, showAnnual) {
        case (.havenPro,    true):  return .havenProAnnual
        case (.havenPro,    false): return .havenProMonthly
        case (.enclave,     true):  return .enclaveAnnual
        case (.enclave,     false): return .enclaveMonthly
        case (.enclavePlus, true):  return .enclavePlusAnnual
        case (.enclavePlus, false): return .enclavePlusMonthly
        default:                    return .enclaveAnnual
        }
    }

    private var activeStoreProduct: Product? {
        storeKit.products.first { $0.id == selectedProduct.rawValue }
    }

    private var accentColor: Color { Color(hex: selectedTier.accentColorHex) }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // ── Title bar ──────────────────────────────────────────────────
            HStack {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(accentColor)
                Text("Choose your Enclave")
                    .font(KFFont.heading(15))
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

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    // subtitle
                    Text(reason.subtitle)
                        .font(KFFont.body(12))
                        .foregroundStyle(Color.kfTextSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    tierSelector
                    billingToggle
                    featureCard
                    ctaButton
                    freeHavenButton
                    legalFooter
                }
                .padding(16)
            }
        }
        .frame(width: 420)
        .background(Color.kfBackground)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showTokenEntry) {
            TokenEntryView().environmentObject(storeKit)
        }
        .onChange(of: storeKit.hasMultiHop) { hasIt in
            if hasIt && reason == .multiHopRequiresPlus { dismiss() }
        }
        .onChange(of: storeKit.hasVPN) { hasIt in
            if hasIt && reason == .vpnRequiresEnclave { dismiss() }
        }
    }

    // MARK: - Tier selector

    private var tierSelector: some View {
        HStack(spacing: 8) {
            ForEach([WraithTier.havenPro, .enclave, .enclavePlus], id: \.rawValue) { tier in
                MacTierTabView(tier: tier, isSelected: selectedTier == tier)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.18)) { selectedTier = tier }
                    }
            }
        }
    }

    // MARK: - Monthly / Annual toggle

    private var billingToggle: some View {
        HStack(spacing: 0) {
            macTogglePill(label: "Monthly", isActive: !showAnnual) {
                withAnimation(.easeInOut(duration: 0.2)) { showAnnual = false }
            }
            macTogglePill(label: "Annual", isActive: showAnnual, badge: savingsBadge) {
                withAnimation(.easeInOut(duration: 0.2)) { showAnnual = true }
            }
        }
        .background(Color.kfSurface)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.kfBorder, lineWidth: 1))
    }

    private func macTogglePill(label: String, isActive: Bool, badge: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(label)
                    .font(KFFont.caption(12, weight: .semibold))
                    .foregroundStyle(isActive ? .white : Color.kfTextMuted)
                if let badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.kfConnected)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isActive ? LinearGradient.kfAccent : LinearGradient(colors: [Color.clear], startPoint: .top, endPoint: .bottom))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isActive)
    }

    private var savingsBadge: String? {
        let monthlyId = showAnnual
            ? selectedProduct.monthlyVariant?.rawValue
            : selectedProduct.rawValue
        let annualId = showAnnual
            ? selectedProduct.rawValue
            : selectedProduct.annualVariant?.rawValue

        guard let mId = monthlyId,
              let aId = annualId,
              let monthly = storeKit.products.first(where: { $0.id == mId }),
              let annual  = storeKit.products.first(where: { $0.id == aId }) else {
            return "Save ~33%"
        }
        let monthlyAnnualised = monthly.price * 12
        guard monthlyAnnualised > 0 else { return nil }
        let savingDecimal = (monthlyAnnualised - annual.price) / monthlyAnnualised * 100
        guard savingDecimal > 0 else { return nil }
        let savingInt = Int((savingDecimal as NSDecimalNumber).intValue)
        return "Save \(savingInt)%"
    }

    // MARK: - Feature card

    private var featureCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if storeKit.isLoading && storeKit.products.isEmpty {
                ProgressView()
                    .tint(accentColor)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                // Price row
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    if let product = activeStoreProduct {
                        Text(product.displayPrice)
                            .font(KFFont.display(24))
                            .foregroundStyle(.white)
                        Text(showAnnual ? "/ year" : "/ month")
                            .font(KFFont.body(13))
                            .foregroundStyle(Color.kfTextMuted)
                        if showAnnual, let monthly = monthlyEquivalent {
                            Text("(\(monthly)/mo)")
                                .font(KFFont.caption(11))
                                .foregroundStyle(Color.kfTextMuted)
                        }
                    } else {
                        Text("Loading…")
                            .font(KFFont.body(13))
                            .foregroundStyle(Color.kfTextMuted)
                    }
                    Spacer()
                }

                Divider().background(Color.kfBorder)

                // Feature bullets
                ForEach(selectedTier.features, id: \.self) { feature in
                    HStack(spacing: 8) {
                        Image(systemName: featureIcon(feature))
                            .font(.system(size: 12))
                            .foregroundStyle(accentColor)
                            .frame(width: 18)
                        Text(feature)
                            .font(KFFont.body(12))
                            .foregroundStyle(Color.kfTextSecondary)
                        Spacer()
                    }
                }
            }
        }
        .padding(12)
        .background(Color.kfSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(accentColor.opacity(0.35), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.2), value: selectedTier)
    }

    private var monthlyEquivalent: String? {
        guard let product = activeStoreProduct else { return nil }
        let monthly = product.price / 12
        return monthly.formatted(product.priceFormatStyle)
    }

    private func featureIcon(_ feature: String) -> String {
        if feature.contains("DNS") || feature.contains("tracker") || feature.contains("ad") { return "shield.lefthalf.filled" }
        if feature.contains("VPN") || feature.contains("WireGuard") { return "bolt.fill" }
        if feature.contains("multi-hop") || feature.contains("Multi-hop") || feature.contains("2 nodes") { return "arrow.triangle.branch" }
        if feature.contains("Kill switch") { return "xmark.shield.fill" }
        if feature.contains("device") { return "iphone.and.arrow.forward" }
        if feature.contains("exit node") || feature.contains("global") { return "network.badge.shield.half.filled" }
        if feature.contains("Maximum") || feature.contains("privacy") { return "lock.fill" }
        if feature.contains("Entry") || feature.contains("separation") { return "arrow.left.arrow.right" }
        if feature.contains("Everything") { return "checkmark.seal.fill" }
        return "checkmark.circle"
    }

    // MARK: - CTA button

    private var ctaButton: some View {
        Button {
            guard let product = activeStoreProduct else { return }
            Task { await storeKit.purchase(product) }
        } label: {
            Group {
                if storeKit.isLoading {
                    ProgressView().tint(.white)
                } else {
                    Text("Subscribe to \(selectedTier.displayName)")
                        .font(KFFont.caption(13, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(accentColor)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(storeKit.isLoading || activeStoreProduct == nil)
    }

    // MARK: - Free Haven button

    private var freeHavenButton: some View {
        Button {
            dismiss()
        } label: {
            Text("Continue with Free Haven")
                .font(KFFont.caption(12))
                .foregroundStyle(Color.kfTextMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.kfSurface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.kfBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Legal footer

    private var legalFooter: some View {
        VStack(spacing: 6) {
            HStack(spacing: 16) {
                Button("Restore Purchase") {
                    Task { await storeKit.restorePurchases() }
                }
                .font(KFFont.caption(11))
                .foregroundStyle(Color.kfAccentBlue)
                .buttonStyle(.plain)

                Button("Have a token?") {
                    showTokenEntry = true
                }
                .font(KFFont.caption(11))
                .foregroundStyle(Color.kfAccentBlue)
                .buttonStyle(.plain)

                Spacer()

                Link("Terms", destination: URL(string: "https://katafract.com/legal/terms")!)
                    .font(KFFont.caption(11))
                    .foregroundStyle(Color.kfTextMuted)

                Link("Privacy", destination: URL(string: "https://katafract.com/legal/privacy")!)
                    .font(KFFont.caption(11))
                    .foregroundStyle(Color.kfTextMuted)
            }

            Text("Payment charged to your Apple ID at confirmation. Subscriptions renew automatically unless cancelled at least 24 hours before the end of the current period.")
                .font(KFFont.caption(10))
                .foregroundStyle(Color.kfTextMuted)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
    }
}

// MARK: - Tier tab (Mac)

private struct MacTierTabView: View {
    let tier: WraithTier
    let isSelected: Bool

    private var accent: Color { Color(hex: tier.accentColorHex) }

    var body: some View {
        Text(tier.displayName)
            .font(KFFont.caption(11, weight: .semibold))
            .foregroundStyle(isSelected ? accent : Color.kfTextMuted)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? accent.opacity(0.12) : Color.kfSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isSelected ? accent : Color.kfBorder, lineWidth: isSelected ? 1.5 : 1)
            )
            .animation(.easeInOut(duration: 0.18), value: isSelected)
    }
}
