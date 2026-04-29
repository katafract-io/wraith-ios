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
///
/// Tek wires this to the real RegionStore / ConnectionManager / DNSStatsStore
/// when the Sprint 4 device-test branch is App-Store-ready. Until then this
/// is a call-site stub so XCUITests can launch with --screenshots and not
/// crash when ViewModels probe ScreenshotMode.
struct MockDataSeeder {
    static func seedDataIfNeeded() {
        guard CommandLine.arguments.contains("--screenshots") else { return }
        // TODO: wire to RegionStore / ConnectionManager / DNSStatsStore.
        // Sample seed data per launch flag should live alongside ScreenshotMode.
        print("MockDataSeeder: TODO — wire to WraithVPN region/connection/DNS models")
    }
}
