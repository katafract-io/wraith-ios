import Foundation

/// Mock data seeder for screenshot mode (--screenshots launch argument).
/// Provides sample VPN regions + connection state for fastlane snapshot CI.
///
/// Activate via launch arguments handled by ScreenshotMode.swift:
///   --screenshots               (master switch)
///   --mock-subscribed           (force isSubscribed = true)
///   --mock-unsubscribed         (force unsubscribed for paywall capture)
///   --mock-connected            (force connection state = .connected)
///   --mock-disconnected-advanced (kill-switch / advanced view)
///   --mock-regions              (force exit-node region list to canonical demo set)
///   --mock-haven-prefs          (force Haven DNS settings = standard tier)
///   --mock-dns-stats            (seed DNS query/block counters)
///   --paywall-sovereign-annual  (force paywall to land on Sovereign annual)
struct MockDataSeeder {
    @MainActor
    static func seedConnectedState(
        regionManager: ServerListManager,
        connectionManager: WireGuardManager,
        havenManager: HavenDNSManager
    ) {
        // Select Singapore (sgp2) as the demo region with 47ms latency.
        let singaporeServer = VPNServer(
            nodeId: "sgp2",
            site: "sgp2",
            region: "sg",
            displayName: "Singapore",
            ipv4: "149.28.132.184",
            ipv6: "fd10:0:8::1",
            endpoints: .init(
                primary: "sgp2.example.com",
                secondary: "149.28.132.184"
            ),
            publicKey: "mock-pubkey-sgp2",
            wgPort: 51820,
            loadScore: 0.5,
            ipv6Available: true,
            geodnsWeight: 100
        )

        // Prime the region manager.
        regionManager.selectedServer = singaporeServer

        // Prime the connection manager: set status to .connected, assign the region,
        // and set connectedSince to 90 seconds ago so the UI timer reads "1m 30s".
        connectionManager.status = .connected
        connectionManager.connectedServer = singaporeServer
        connectionManager.assignedIP = "10.11.8.47"
        connectionManager.activePeerId = "sgp2-peer-001"
        connectionManager.isProvisioned = true
        connectionManager.exitIP = "149.28.132.184"
        connectionManager.activeTransport = .wireguard
        connectionManager.connectedSince = Date().addingTimeInterval(-90)

        // Prime Haven DNS manager: set it enabled with standard tier prefs.
        havenManager.isEnabled = true
        havenManager.preferences = DnsPreferences(
            tier: "standard",
            protectionLevel: "default",
            protectionLevels: ["default", "strict"],
            safeBrowsing: true,
            familyFilter: false,
            blockedServices: [],
            blockableServices: ["facebook", "twitter", "linkedin", "amazon"],
            updatedAt: nil
        )
    }
}
