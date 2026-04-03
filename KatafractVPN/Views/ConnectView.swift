// ConnectView.swift
// KatafractVPN
//
// Main screen: animated connect button, status label, selected server location,
// current assigned IP when connected, and quick-access to server picker.

import SwiftUI

struct ConnectView: View {

    @EnvironmentObject var vpn:    WireGuardManager
    @EnvironmentObject var servers: ServerListManager

    @State private var showServerPicker = false
    @State private var isAnimatingRing  = false
    @State private var errorMessage: String? = nil
    @State private var showError = false

    // MARK: - Body

    var body: some View {
        ZStack {
            backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Spacer()
                connectButton
                Spacer()
                statusSection
                Spacer()
                serverButton
                    .padding(.bottom, KFSpacing.xxl)
            }
            .padding(.horizontal, KFSpacing.lg)
        }
        .sheet(isPresented: $showServerPicker) {
            ServerPickerView()
                .environmentObject(servers)
                .environmentObject(vpn)
        }
        .alert("Connection Error", isPresented: $showError, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text(errorMessage ?? "Unknown error")
        })
        .preferredColorScheme(.dark)
        .task {
            await servers.refresh()
            await servers.preselectNearest()
        }
    }

    // MARK: - Sub-views

    private var backgroundGradient: some View {
        ZStack {
            Color.kfBackground
            // Subtle radial glow at top-center
            RadialGradient(
                colors: [
                    vpn.status == .connected
                        ? Color.kfConnected.opacity(0.12)
                        : Color.kfAccentPurple.opacity(0.08),
                    Color.clear
                ],
                center: .top,
                startRadius: 0,
                endRadius: 400
            )
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("KATAFRACT")
                    .font(KFFont.caption(11, weight: .bold))
                    .kerning(3)
                    .foregroundStyle(.kfTextMuted)
                Text("VPN")
                    .font(KFFont.display(28))
                    .foregroundStyle(.white)
            }
            Spacer()
            NavigationLink(destination: SettingsView()) {
                Image(systemName: "person.circle")
                    .font(.system(size: 24))
                    .foregroundStyle(.kfTextSecondary)
            }
        }
        .padding(.top, KFSpacing.lg)
    }

    // MARK: - Connect button

    private var connectButton: some View {
        Button(action: handleConnectTap) {
            ZStack {
                // Outer animated ring
                Circle()
                    .stroke(
                        AngularGradient.kfConnectButtonRing(status: vpn.status),
                        lineWidth: 4
                    )
                    .frame(width: 220, height: 220)
                    .rotationEffect(.degrees(isAnimatingRing ? 360 : 0))
                    .animation(
                        vpn.status == .connecting || vpn.status == .disconnecting
                            ? .linear(duration: 1.5).repeatForever(autoreverses: false)
                            : .easeOut(duration: 0.5),
                        value: isAnimatingRing
                    )

                // Inner glow ring
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                ringCenterColor.opacity(0.25),
                                ringCenterColor.opacity(0.05),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 95
                        )
                    )
                    .frame(width: 190, height: 190)

                // Button face
                Circle()
                    .fill(Color.kfSurface)
                    .frame(width: 160, height: 160)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.kfBorder, lineWidth: 1)
                            .frame(width: 160, height: 160)
                    )

                // Icon
                Image(systemName: buttonIcon)
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(
                        vpn.status == .connected
                            ? LinearGradient(colors: [.kfConnected, Color(hex: "#86efac")], startPoint: .top, endPoint: .bottom)
                            : LinearGradient(colors: [.kfTextSecondary, .kfTextMuted], startPoint: .top, endPoint: .bottom)
                    )
                    .animation(.easeInOut(duration: 0.3), value: vpn.status)
            }
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(vpn.status == .connecting || vpn.status == .disconnecting)
        .onChange(of: vpn.status) { newStatus in
            isAnimatingRing = (newStatus == .connecting || newStatus == .disconnecting)
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: vpn.status == .connected)
        .sensoryFeedback(.impact(weight: .light),  trigger: vpn.status == .disconnected)
    }

    // MARK: - Status section

    private var statusSection: some View {
        VStack(spacing: KFSpacing.sm) {
            // Main status label
            Text(vpn.status.label)
                .font(KFFont.heading(22))
                .foregroundStyle(vpn.status.swiftUIColor)
                .animation(.easeInOut(duration: 0.3), value: vpn.status)
                .contentTransition(.numericText())

            // Assigned IP when connected
            if let ip = vpn.assignedIP, vpn.status == .connected {
                HStack(spacing: KFSpacing.xs) {
                    Image(systemName: "network")
                        .font(.system(size: 12))
                    Text(ip)
                        .font(KFFont.mono(13))
                }
                .foregroundStyle(.kfTextMuted)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeInOut(duration: 0.4), value: vpn.assignedIP)
    }

    // MARK: - Server button

    private var serverButton: some View {
        Button {
            showServerPicker = true
        } label: {
            HStack(spacing: KFSpacing.sm) {
                // Flag + location
                if let server = servers.selectedServer {
                    Text(server.flagEmoji)
                        .font(.system(size: 24))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(server.cityName)
                            .font(KFFont.heading(17))
                            .foregroundStyle(.white)
                        Text("Tap to change")
                            .font(KFFont.caption(12))
                            .foregroundStyle(.kfTextMuted)
                    }
                } else {
                    Image(systemName: "globe")
                        .font(.system(size: 22))
                        .foregroundStyle(.kfTextSecondary)
                    Text("Select Server")
                        .font(KFFont.heading(17))
                        .foregroundStyle(.white)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.kfTextMuted)
            }
            .padding(KFSpacing.md)
            .kfCard()
        }
    }

    // MARK: - Actions

    private func handleConnectTap() {
        Task {
            do {
                if vpn.status == .connected {
                    vpn.disconnect()
                } else {
                    if let server = servers.selectedServer {
                        try await vpn.connectToServer(server)
                    } else {
                        try vpn.connect()
                    }
                }
            } catch {
                errorMessage = error.localizedDescription
                showError = true
                vpn.status = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Computed helpers

    private var buttonIcon: String {
        switch vpn.status {
        case .connected:    return "power"
        case .connecting:   return "ellipsis"
        case .disconnecting: return "ellipsis"
        default:            return "power"
        }
    }

    private var ringCenterColor: Color {
        switch vpn.status {
        case .connected:    return .kfConnected
        case .connecting, .disconnecting: return .kfConnecting
        default:            return .kfAccentPurple
        }
    }
}

// MARK: - Scale button style

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ConnectView()
            .environmentObject(WireGuardManager())
            .environmentObject(ServerListManager())
    }
}
