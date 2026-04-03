// PaywallView.swift
// KatafractVPN
//
// Subscription paywall shown when the user has no active token.
// Presents both products (monthly / annual), highlights the annual as "Best Value",
// and shows the feature list.

import SwiftUI
import StoreKit

struct PaywallView: View {

    @EnvironmentObject var storeKit: StoreKitManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedProductId: String = KatafractProduct.armorAnnual.rawValue

    // MARK: - Body

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color(hex: "#0d0f14"), Color(hex: "#110d1a")],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: KFSpacing.xl) {
                    header
                    featureList
                    productPicker
                    ctaButton
                    legalFooter
                }
                .padding(KFSpacing.lg)
                .padding(.top, KFSpacing.lg)
            }
        }
        .navigationTitle("Subscribe")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.kfBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .preferredColorScheme(.dark)
        .alert("Purchase Error", isPresented: .init(
            get: { storeKit.purchaseError != nil },
            set: { if !$0 { storeKit.purchaseError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(storeKit.purchaseError ?? "")
        }
    }

    // MARK: - Sub-views

    private var header: some View {
        VStack(spacing: KFSpacing.sm) {
            ZStack {
                Circle()
                    .fill(Color.kfAccentPurple.opacity(0.2))
                    .frame(width: 90, height: 90)
                    .blur(radius: 20)
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(LinearGradient.kfAccent)
            }

            Text("VPN Armor")
                .font(KFFont.display(34))
                .foregroundStyle(.white)

            Text("Privacy that never compromises.")
                .font(KFFont.body(16))
                .foregroundStyle(.kfTextSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: KFSpacing.sm) {
            FeatureRow(icon: "lock.fill",            text: "AES-256 + ChaCha20 encryption")
            FeatureRow(icon: "bolt.fill",            text: "WireGuard — fastest VPN protocol")
            FeatureRow(icon: "eye.slash.fill",       text: "Strict no-logs policy")
            FeatureRow(icon: "globe",                text: "Servers in Frankfurt, Helsinki, Singapore & New York")
            FeatureRow(icon: "iphone.and.arrow.forward", text: "5 simultaneous devices")
            FeatureRow(icon: "arrow.2.circlepath",   text: "Unlimited bandwidth")
        }
        .padding(KFSpacing.md)
        .kfCard()
    }

    private var productPicker: some View {
        VStack(spacing: KFSpacing.sm) {
            if storeKit.isLoading && storeKit.products.isEmpty {
                ProgressView()
                    .tint(.kfAccentBlue)
                    .frame(height: 120)
            } else {
                ForEach(storeKit.products, id: \.id) { product in
                    ProductOptionView(
                        product: product,
                        isSelected: selectedProductId == product.id,
                        isBestValue: product.id == KatafractProduct.armorAnnual.rawValue
                    )
                    .onTapGesture { selectedProductId = product.id }
                }
            }
        }
    }

    private var ctaButton: some View {
        Button {
            guard let product = storeKit.products.first(where: { $0.id == selectedProductId }) else { return }
            Task { await storeKit.purchase(product) }
        } label: {
            Group {
                if storeKit.isLoading {
                    ProgressView().tint(.white)
                } else {
                    Text("Subscribe Now")
                        .font(KFFont.heading(18))
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, KFSpacing.md)
            .background(LinearGradient.kfAccent)
            .clipShape(Capsule())
        }
        .disabled(storeKit.isLoading)
    }

    private var legalFooter: some View {
        VStack(spacing: KFSpacing.xs) {
            Button("Restore Purchase") {
                Task { await storeKit.restorePurchases() }
            }
            .font(KFFont.caption(13))
            .foregroundStyle(.kfAccentBlue)

            Text("Payment will be charged to your Apple ID account at confirmation of purchase. Subscriptions automatically renew unless cancelled at least 24 hours before the end of the current period. You can manage and cancel your subscription in your App Store account settings.")
                .font(KFFont.caption(11))
                .foregroundStyle(.kfTextMuted)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
    }
}

// MARK: - Feature row

private struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: KFSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.kfAccentBlue)
                .frame(width: 20)
            Text(text)
                .font(KFFont.body(14))
                .foregroundStyle(.kfTextSecondary)
            Spacer()
        }
    }
}

// MARK: - Product option

private struct ProductOptionView: View {
    let product: Product
    let isSelected: Bool
    let isBestValue: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: KFSpacing.xs) {
                    Text(displayName)
                        .font(KFFont.heading(15))
                        .foregroundStyle(.white)
                    if isBestValue {
                        Text("BEST VALUE")
                            .font(KFFont.caption(10, weight: .bold))
                            .kerning(1)
                            .foregroundStyle(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.kfConnected)
                            .clipShape(Capsule())
                    }
                }
                if isBestValue, let monthlyEquivalent {
                    Text("Just \(monthlyEquivalent)/mo — save ~33%")
                        .font(KFFont.caption(12))
                        .foregroundStyle(.kfTextMuted)
                }
            }
            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(product.displayPrice)
                    .font(KFFont.heading(16))
                    .foregroundStyle(.white)
                Text(periodLabel)
                    .font(KFFont.caption(11))
                    .foregroundStyle(.kfTextMuted)
            }
        }
        .padding(KFSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: KFRadius.md, style: .continuous)
                .fill(isSelected ? Color.kfAccentBlue.opacity(0.12) : Color.kfSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: KFRadius.md, style: .continuous)
                .strokeBorder(
                    isSelected
                        ? LinearGradient.kfAccent
                        : LinearGradient(colors: [Color.kfBorder], startPoint: .top, endPoint: .bottom),
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }

    private var displayName: String {
        product.id == KatafractProduct.armorAnnual.rawValue
            ? "Annual Plan"
            : "Monthly Plan"
    }

    private var periodLabel: String {
        product.id == KatafractProduct.armorAnnual.rawValue ? "per year" : "per month"
    }

    /// Rough monthly equivalent for the annual plan (hardcoded to match spec)
    private var monthlyEquivalent: String? {
        guard product.id == KatafractProduct.armorAnnual.rawValue else { return nil }
        return "$3.33"
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        PaywallView()
            .environmentObject(StoreKitManager())
    }
}
