// SettingsView.swift
// KatafractVPN
//
// Account & settings screen: plan info, expiry, manage subscription link,
// sign-out, regenerate keypair option, and app version.

import SwiftUI
import StoreKit

struct SettingsView: View {

    @EnvironmentObject var storeKit: StoreKitManager
    @EnvironmentObject var vpn:      WireGuardManager

    @State private var showSignOutAlert    = false
    @State private var showRevokeAlert     = false
    @State private var showRegenerateAlert = false
    @State private var isRestoring         = false

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.kfBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: KFSpacing.lg) {
                    accountCard
                    connectionCard
                    subscriptionCard
                    supportCard
                    dangerCard
                    versionFooter
                }
                .padding(KFSpacing.md)
            }
        }
        .navigationTitle("Account & Settings")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.kfBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .preferredColorScheme(.dark)
        .alert("Sign Out", isPresented: $showSignOutAlert) {
            Button("Sign Out", role: .destructive) { storeKit.signOut() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your subscription token will be removed from this device. You can sign in again by restoring your purchase.")
        }
        .alert("Revoke Active Peer", isPresented: $showRevokeAlert) {
            Button("Revoke", role: .destructive) {
                Task { await vpn.revokePeer() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will disconnect the VPN and delete your current WireGuard configuration from the server. A new one will be created on next connect.")
        }
        .alert("Regenerate Keys", isPresented: $showRegenerateAlert) {
            Button("Regenerate", role: .destructive) { regenerateKeys() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your existing WireGuard keypair will be replaced. You will need to reconnect afterwards. This is useful if you believe your private key has been compromised.")
        }
    }

    // MARK: - Account card

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: KFSpacing.md) {
            sectionHeader("Subscription")

            if let sub = storeKit.subscription {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(sub.planDisplayName)
                            .font(KFFont.heading(16))
                            .foregroundStyle(.white)
                        Text("Expires \(sub.expiryFormatted)")
                            .font(KFFont.caption())
                            .foregroundStyle(sub.isExpired ? .kfError : .kfTextMuted)
                    }
                    Spacer()
                    if sub.isExpired {
                        Label("Expired", systemImage: "exclamationmark.circle.fill")
                            .font(KFFont.caption(12, weight: .semibold))
                            .foregroundStyle(.kfError)
                    } else {
                        Label("Active", systemImage: "checkmark.circle.fill")
                            .font(KFFont.caption(12, weight: .semibold))
                            .foregroundStyle(.kfConnected)
                    }
                }
            } else {
                HStack {
                    Text("No active subscription")
                        .font(KFFont.body())
                        .foregroundStyle(.kfTextSecondary)
                    Spacer()
                    NavigationLink("Subscribe") {
                        PaywallView()
                            .environmentObject(storeKit)
                    }
                    .font(KFFont.body(14))
                    .foregroundStyle(.kfAccentBlue)
                }
            }
        }
        .padding(KFSpacing.md)
        .kfCard()
    }

    // MARK: - Connection card

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: KFSpacing.md) {
            sectionHeader("Connection")

            SettingsRow(icon: "server.rack", label: "Active Server") {
                Text(vpn.connectedServer?.cityName ?? "None")
                    .font(KFFont.body(14))
                    .foregroundStyle(.kfTextMuted)
            }

            Divider().background(Color.kfBorder)

            SettingsRow(icon: "network", label: "Assigned IP") {
                Text(vpn.assignedIP ?? "—")
                    .font(KFFont.mono(13))
                    .foregroundStyle(.kfTextMuted)
            }

            Divider().background(Color.kfBorder)

            SettingsRow(icon: "shield.lefthalf.fill", label: "Status") {
                Text(vpn.status.label)
                    .font(KFFont.body(14))
                    .foregroundStyle(vpn.status.swiftUIColor)
            }

            Divider().background(Color.kfBorder)

            Button {
                showRevokeAlert = true
            } label: {
                SettingsRow(icon: "arrow.counterclockwise", label: "Revoke & Reset Peer") {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13))
                        .foregroundStyle(.kfTextMuted)
                }
            }
        }
        .padding(KFSpacing.md)
        .kfCard()
    }

    // MARK: - Subscription management card

    private var subscriptionCard: some View {
        VStack(alignment: .leading, spacing: KFSpacing.md) {
            sectionHeader("Manage")

            Link(destination: URL(string: "https://apps.apple.com/account/subscriptions")!) {
                SettingsRow(icon: "creditcard", label: "Manage Subscription") {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 14))
                        .foregroundStyle(.kfAccentBlue)
                }
            }

            Divider().background(Color.kfBorder)

            Button {
                isRestoring = true
                Task {
                    await storeKit.restorePurchases()
                    isRestoring = false
                }
            } label: {
                SettingsRow(icon: "arrow.clockwise", label: "Restore Purchase") {
                    if isRestoring {
                        ProgressView().tint(.kfAccentBlue)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13))
                            .foregroundStyle(.kfTextMuted)
                    }
                }
            }
            .disabled(isRestoring)
        }
        .padding(KFSpacing.md)
        .kfCard()
    }

    // MARK: - Support card

    private var supportCard: some View {
        VStack(alignment: .leading, spacing: KFSpacing.md) {
            sectionHeader("Support")

            Link(destination: URL(string: "https://katafract.com/privacy")!) {
                SettingsRow(icon: "hand.raised.fill", label: "Privacy Policy") {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 14))
                        .foregroundStyle(.kfAccentBlue)
                }
            }

            Divider().background(Color.kfBorder)

            Link(destination: URL(string: "https://katafract.com/terms")!) {
                SettingsRow(icon: "doc.text.fill", label: "Terms of Service") {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 14))
                        .foregroundStyle(.kfAccentBlue)
                }
            }

            Divider().background(Color.kfBorder)

            Link(destination: URL(string: "mailto:support@katafract.com")!) {
                SettingsRow(icon: "envelope.fill", label: "Contact Support") {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 14))
                        .foregroundStyle(.kfAccentBlue)
                }
            }
        }
        .padding(KFSpacing.md)
        .kfCard()
    }

    // MARK: - Danger zone

    private var dangerCard: some View {
        VStack(alignment: .leading, spacing: KFSpacing.md) {
            sectionHeader("Security")

            Button { showRegenerateAlert = true } label: {
                SettingsRow(icon: "key.fill", label: "Regenerate WireGuard Keys") {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13))
                        .foregroundStyle(.kfTextMuted)
                }
            }

            Divider().background(Color.kfBorder)

            Button { showSignOutAlert = true } label: {
                SettingsRow(icon: "rectangle.portrait.and.arrow.right", label: "Sign Out") {
                    EmptyView()
                }
                .foregroundStyle(.kfError)
            }
        }
        .padding(KFSpacing.md)
        .kfCard()
    }

    private var versionFooter: some View {
        VStack(spacing: 4) {
            Text("Katafract VPN")
                .font(KFFont.caption(12, weight: .semibold))
                .foregroundStyle(.kfTextMuted)
            Text("Version \(appVersion) (\(buildNumber))")
                .font(KFFont.caption(11))
                .foregroundStyle(.kfTextMuted.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, KFSpacing.lg)
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(KFFont.caption(11, weight: .bold))
            .kerning(1.5)
            .foregroundStyle(.kfTextMuted)
    }

    private func regenerateKeys() {
        Task {
            vpn.disconnect()
            try? vpn.generateKeypair()
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}

// MARK: - Settings row

struct SettingsRow<Trailing: View>: View {
    let icon: String
    let label: String
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: KFSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .frame(width: 20)
                .foregroundStyle(.kfAccentBlue)

            Text(label)
                .font(KFFont.body(15))
                .foregroundStyle(.kfTextPrimary)

            Spacer()

            trailing()
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(StoreKitManager())
            .environmentObject(WireGuardManager())
    }
}
