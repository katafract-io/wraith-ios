// HavenDNSManager.swift
// WraithVPN
//
// Manages the Haven DNS-over-HTTPS profile using NEDNSSettingsManager.
// Haven DNS is available for free — no subscription required.
// It installs a system DNS profile that routes all DNS queries through
// Katafract's WraithGate nodes (AdGuard Home, blocking ads + trackers).

import Foundation
import NetworkExtension
import Combine

@MainActor
final class HavenDNSManager: ObservableObject {

    // MARK: - Published

    @Published var isEnabled: Bool = false
    @Published var isLoading: Bool = false
    @Published var error: String? = nil

    // MARK: - Private

    private let dohURL = "https://haven.katafract.com/dns-query"
    private let profileDescription = "Haven DNS — Ad & tracker blocking by WraithVPN"

    // MARK: - Init

    init() {
        Task { await refreshStatus() }
    }

    // MARK: - Public

    func enable() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let manager = NEDNSSettingsManager.shared()
            try await manager.loadFromPreferences()

            let settings = NEDNSOverHTTPSSettings(servers: [dohURL])
            manager.dnsSettings = settings
            manager.localizedDescription = profileDescription

            try await manager.saveToPreferences()
            await refreshStatus()
        } catch {
            self.error = "Could not enable Haven DNS: \(error.localizedDescription)"
        }
    }

    func disable() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let manager = NEDNSSettingsManager.shared()
            try await manager.loadFromPreferences()
            try await manager.removeFromPreferences()
            isEnabled = false
        } catch {
            self.error = "Could not disable Haven DNS: \(error.localizedDescription)"
        }
    }

    func toggle() async {
        if isEnabled { await disable() } else { await enable() }
    }

    func refreshStatus() async {
        let manager = NEDNSSettingsManager.shared()
        do {
            try await manager.loadFromPreferences()
            isEnabled = manager.isEnabled
        } catch {
            isEnabled = false
        }
    }
}
