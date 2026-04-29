// ModelTests.swift
// WraithVPNTests
//
// Unit tests for all computed properties and decoding logic in Models.swift.
// No network, no Keychain, no system APIs — pure logic.

import XCTest
@testable import WraithVPN

final class ModelTests: XCTestCase {

    // MARK: - RegionInfo (region-only fallback path)

    func testCityName_regionFallback_knownRegions() {
        // site is unknown to siteMap → falls back to regionMap.
        XCTAssertEqual(RegionInfo.cityName(site: "",    region: "eu-west"),      "Frankfurt")
        XCTAssertEqual(RegionInfo.cityName(site: "",    region: "eu-north"),     "Helsinki")
        XCTAssertEqual(RegionInfo.cityName(site: "",    region: "ap-southeast"), "Singapore")
        XCTAssertEqual(RegionInfo.cityName(site: "",    region: "us-central"),   "Missouri")
        XCTAssertEqual(RegionInfo.cityName(site: "",    region: "us-east"),      "Virginia")
        XCTAssertEqual(RegionInfo.cityName(site: "",    region: "us-west"),      "Oregon")
    }

    func testCityName_unknownSiteAndRegion_returnsRegionCode() {
        XCTAssertEqual(RegionInfo.cityName(site: "xx", region: "xx-unknown"), "xx-unknown")
        XCTAssertEqual(RegionInfo.cityName(site: "",   region: ""),           "")
    }

    func testFlag_regionFallback_knownRegions() {
        XCTAssertEqual(RegionInfo.flag(site: "", region: "eu-west"),      "🇩🇪")
        XCTAssertEqual(RegionInfo.flag(site: "", region: "eu-north"),     "🇫🇮")
        XCTAssertEqual(RegionInfo.flag(site: "", region: "ap-southeast"), "🇸🇬")
        XCTAssertEqual(RegionInfo.flag(site: "", region: "us-central"),   "🇺🇸")
        XCTAssertEqual(RegionInfo.flag(site: "", region: "us-east"),      "🇺🇸")
        XCTAssertEqual(RegionInfo.flag(site: "", region: "us-west"),      "🇺🇸")
    }

    func testFlag_unknownSiteAndRegion_returnsGlobe() {
        XCTAssertEqual(RegionInfo.flag(site: "xx", region: "xx-unknown"), "🌐")
        XCTAssertEqual(RegionInfo.flag(site: "",   region: ""),           "🌐")
    }

    // MARK: - RegionInfo (site-keyed map — preferred resolution)
    //
    // Bug B regression test: nodeId vpn-iad-01 (artemis-api site=ash) MUST render
    // as Ashburn, NOT Newark. Newark is vpn-ewr-01 (site=ewr1). The TestFlight
    // 1456 bug was that picker showed "Newark" while tunnel ran on vpn-iad-01;
    // the iOS site map was correct, the bug was that connectedServer reflected
    // the user's requested node not the actual provisioned node (fixed in
    // WireGuardManager.resolveProvisionedServer).

    func testCityName_siteMap_iad_isAshburn_not_newark() {
        // site=ash is what artemis-api returns for vpn-iad-01 (Hetzner ASH).
        XCTAssertEqual(RegionInfo.cityName(site: "ash", region: "us-east"), "Ashburn")
        XCTAssertNotEqual(RegionInfo.cityName(site: "ash", region: "us-east"), "Newark",
                          "vpn-iad-01 (site=ash) must NEVER render as Newark — that is vpn-ewr-01")
    }

    func testCityName_siteMap_ewr_isNewark() {
        XCTAssertEqual(RegionInfo.cityName(site: "ewr1", region: "us-east"), "Newark")
    }

    func testCityName_siteMap_allKnownNodes() {
        // Every production node id → expected city, locking in the truth contract.
        let cases: [(site: String, region: String, expected: String)] = [
            ("ash",  "us-east",      "Ashburn"),     // vpn-iad-01
            ("ewr1", "us-east",      "Newark"),      // vpn-ewr-01
            ("hil",  "us-west",      "Hillsboro"),   // vpn-pdx-01 + vpn-pdx-02
            ("nbg1", "eu-west",      "Nuremberg"),   // vpn-nbg-01
            ("hel1", "eu-north",     "Helsinki"),    // vpn-hel-01
            ("sgp2", "ap-southeast", "Singapore"),   // vpn-sin-02
            ("sgp3", "ap-southeast", "Singapore"),   // vpn-sin-03
            ("nrt1", "ap-northeast", "Tokyo"),       // vpn-nrt-01
            ("bom1", "ap-south",     "Mumbai"),      // vpn-bom-01
        ]
        for c in cases {
            XCTAssertEqual(
                RegionInfo.cityName(site: c.site, region: c.region),
                c.expected,
                "site=\(c.site) region=\(c.region) should render as \(c.expected)"
            )
        }
    }

    func testFlag_siteMap_iad_isUS() {
        XCTAssertEqual(RegionInfo.flag(site: "ash", region: "us-east"), "🇺🇸")
    }

    // MARK: - VPNServer computed props

    func testServer_cityName_delegatesToRegionInfo() {
        let server = makeServer(region: "eu-north")
        XCTAssertEqual(server.cityName, "Helsinki")
    }

    func testServer_flagEmoji_delegatesToRegionInfo() {
        let server = makeServer(region: "ap-southeast")
        XCTAssertEqual(server.flagEmoji, "🇸🇬")
    }

    func testServer_cityName_iad_node_rendersAshburn() {
        // Direct check against the Bug B failure mode: a VPNServer with the
        // canonical metadata for vpn-iad-01 must produce "Ashburn" and never
        // "Newark", regardless of region.
        let iad = VPNServer(
            nodeId: "vpn-iad-01",
            site: "ash",
            region: "us-east",
            displayName: "Ashburn",
            ipv4: "87.99.128.159",
            ipv6: nil,
            endpoints: VPNServer.Endpoints(primary: "87.99.128.159:51820", secondary: nil),
            publicKey: "",
            wgPort: 51820,
            loadScore: 0,
            ipv6Available: false,
            geodnsWeight: 100
        )
        XCTAssertEqual(iad.cityName, "Ashburn")
        XCTAssertNotEqual(iad.cityName, "Newark")
    }

    // MARK: - VPNStatus

    func testIsActive_connected() {
        XCTAssertTrue(VPNStatus.connected.isActive)
    }

    func testIsActive_connecting() {
        XCTAssertTrue(VPNStatus.connecting.isActive)
    }

    func testIsActive_disconnected() {
        XCTAssertFalse(VPNStatus.disconnected.isActive)
    }

    func testIsActive_disconnecting() {
        XCTAssertFalse(VPNStatus.disconnecting.isActive)
    }

    func testIsActive_failed() {
        XCTAssertFalse(VPNStatus.failed("timeout").isActive)
    }

    func testLabel_allStatuses() {
        XCTAssertEqual(VPNStatus.disconnected.label,      "Disconnected")
        XCTAssertEqual(VPNStatus.connecting.label,        "Connecting…")
        XCTAssertEqual(VPNStatus.connected.label,         "Connected")
        XCTAssertEqual(VPNStatus.disconnecting.label,     "Disconnecting…")
        XCTAssertEqual(VPNStatus.failed("oops").label,    "Error: oops")
        XCTAssertEqual(VPNStatus.failed("").label,        "Error: ")
    }

    func testColor_connected_returnsConnected() {
        XCTAssertEqual(VPNStatus.connected.color, .connected)
    }

    func testColor_connecting_returnsConnecting() {
        XCTAssertEqual(VPNStatus.connecting.color, .connecting)
    }

    func testColor_disconnecting_returnsConnecting() {
        XCTAssertEqual(VPNStatus.disconnecting.color, .connecting)
    }

    func testColor_disconnected_returnsDisconnected() {
        XCTAssertEqual(VPNStatus.disconnected.color, .disconnected)
    }

    func testColor_failed_returnsDisconnected() {
        XCTAssertEqual(VPNStatus.failed("err").color, .disconnected)
    }

    // MARK: - SubscriptionInfo.planDisplayName

    func testPlanDisplayName_founder() {
        XCTAssertEqual(makeSubscription(plan: "founder").planDisplayName, "Founder")
    }

    func testPlanDisplayName_total() {
        XCTAssertEqual(makeSubscription(plan: "total").planDisplayName, "Founder")
    }

    func testPlanDisplayName_total_annual() {
        XCTAssertEqual(makeSubscription(plan: "total_annual").planDisplayName, "Founder")
    }

    func testPlanDisplayName_haven() {
        XCTAssertEqual(makeSubscription(plan: "haven").planDisplayName, "Haven DNS")
    }

    func testPlanDisplayName_veil() {
        XCTAssertEqual(makeSubscription(plan: "veil").planDisplayName, "WraithVPN")
    }

    func testPlanDisplayName_vpn_armor() {
        XCTAssertEqual(makeSubscription(plan: "vpn_armor").planDisplayName, "WraithVPN")
    }

    func testPlanDisplayName_veil_annual() {
        XCTAssertEqual(makeSubscription(plan: "veil_annual").planDisplayName, "WraithVPN Annual")
    }

    func testPlanDisplayName_enclave() {
        XCTAssertEqual(makeSubscription(plan: "enclave").planDisplayName, "Enclave")
    }

    func testPlanDisplayName_enclave_annual() {
        XCTAssertEqual(makeSubscription(plan: "enclave_annual").planDisplayName, "Enclave")
    }

    func testPlanDisplayName_unknown_returnsRawPlan() {
        XCTAssertEqual(makeSubscription(plan: "mystery_plan").planDisplayName, "mystery_plan")
    }

    // MARK: - SubscriptionInfo.isExpired

    func testIsExpired_pastDate_returnsTrue() {
        let past = Date(timeIntervalSinceNow: -3600)
        XCTAssertTrue(makeSubscription(expiresAt: past).isExpired)
    }

    func testIsExpired_futureDate_returnsFalse() {
        let future = Date(timeIntervalSinceNow: 3600)
        XCTAssertFalse(makeSubscription(expiresAt: future).isExpired)
    }

    func testIsExpired_nilDate_returnsFalse() {
        XCTAssertFalse(makeSubscription(expiresAt: nil).isExpired)
    }

    // MARK: - SubscriptionInfo.expiryFormatted

    func testExpiryFormatted_founder_nilDate_returnsNever() {
        XCTAssertEqual(makeSubscription(plan: "founder", expiresAt: nil).expiryFormatted, "Never")
    }

    func testExpiryFormatted_total_nilDate_returnsNever() {
        XCTAssertEqual(makeSubscription(plan: "total", expiresAt: nil).expiryFormatted, "Never")
    }

    func testExpiryFormatted_total_annual_nilDate_returnsNever() {
        XCTAssertEqual(makeSubscription(plan: "total_annual", expiresAt: nil).expiryFormatted, "Never")
    }

    func testExpiryFormatted_havens_nilDate_returnsUnknown() {
        XCTAssertEqual(makeSubscription(plan: "haven", expiresAt: nil).expiryFormatted, "Unknown")
    }

    func testExpiryFormatted_withDate_returnsFormattedDate() {
        var comps = DateComponents()
        comps.year = 2027; comps.month = 6; comps.day = 15
        let date = Calendar.current.date(from: comps)!
        let result = makeSubscription(expiresAt: date).expiryFormatted
        XCTAssertFalse(result.isEmpty)
        XCTAssertNotEqual(result, "Never")
        XCTAssertNotEqual(result, "Unknown")
    }

    // MARK: - ServerLatency

    func testLatencyTier_excellent_below60() {
        XCTAssertEqual(makeLatency(ms: 0).latencyTier,  .excellent)
        XCTAssertEqual(makeLatency(ms: 59).latencyTier, .excellent)
    }

    func testLatencyTier_good_60to119() {
        XCTAssertEqual(makeLatency(ms: 60).latencyTier,  .good)
        XCTAssertEqual(makeLatency(ms: 119).latencyTier, .good)
    }

    func testLatencyTier_fair_120to199() {
        XCTAssertEqual(makeLatency(ms: 120).latencyTier, .fair)
        XCTAssertEqual(makeLatency(ms: 199).latencyTier, .fair)
    }

    func testLatencyTier_poor_200andAbove() {
        XCTAssertEqual(makeLatency(ms: 200).latencyTier, .poor)
        XCTAssertEqual(makeLatency(ms: 999).latencyTier, .poor)
    }

    func testLatencyTier_nil_returnsUnknown() {
        let sl = ServerLatency(server: makeServer(), milliseconds: nil)
        XCTAssertEqual(sl.latencyTier, .unknown)
    }

    func testDisplayLatency_withValue() {
        XCTAssertEqual(makeLatency(ms: 42).displayLatency,  "42 ms")
        XCTAssertEqual(makeLatency(ms: 0).displayLatency,   "0 ms")
        XCTAssertEqual(makeLatency(ms: 999).displayLatency, "999 ms")
    }

    func testDisplayLatency_nil_returnsDash() {
        let sl = ServerLatency(server: makeServer(), milliseconds: nil)
        XCTAssertEqual(sl.displayLatency, "—")
    }

    // MARK: - LatencyTier.colorHex

    func testColorHex_allTiers() {
        XCTAssertEqual(LatencyTier.excellent.colorHex, "#22c55e")
        XCTAssertEqual(LatencyTier.good.colorHex,      "#86efac")
        XCTAssertEqual(LatencyTier.fair.colorHex,      "#facc15")
        XCTAssertEqual(LatencyTier.poor.colorHex,      "#f87171")
        XCTAssertEqual(LatencyTier.unknown.colorHex,   "#6b7280")
    }

    // MARK: - DnsPreferences.isPro

    func testIsPro_proTier() {
        XCTAssertTrue(makeDnsPreferences(tier: "pro").isPro)
    }

    func testIsPro_founderTier() {
        XCTAssertTrue(makeDnsPreferences(tier: "founder").isPro)
    }

    func testIsPro_freeTier() {
        XCTAssertFalse(makeDnsPreferences(tier: "free").isPro)
    }

    func testIsPro_unknownTier() {
        XCTAssertFalse(makeDnsPreferences(tier: "haven").isPro)
    }

    // MARK: - PlatformStatus

    func testDisplayStatus_healthy() {
        XCTAssertEqual(makePlatformStatus("healthy").displayStatus, "All Systems Operational")
    }

    func testDisplayStatus_degraded() {
        XCTAssertEqual(makePlatformStatus("degraded").displayStatus, "Partial Degradation")
    }

    func testDisplayStatus_down() {
        XCTAssertEqual(makePlatformStatus("down").displayStatus, "Service Disruption")
    }

    func testDisplayStatus_unknownString() {
        XCTAssertEqual(makePlatformStatus("maintenance").displayStatus, "Service Disruption")
    }

    func testIsHealthy_healthy() {
        XCTAssertTrue(makePlatformStatus("healthy").isHealthy)
    }

    func testIsHealthy_degraded() {
        XCTAssertFalse(makePlatformStatus("degraded").isHealthy)
    }

    func testIsDegraded_degraded() {
        XCTAssertTrue(makePlatformStatus("degraded").isDegraded)
    }

    func testIsDegraded_healthy() {
        XCTAssertFalse(makePlatformStatus("healthy").isDegraded)
    }

    // MARK: - TokenResponse decoding

    func testTokenResponse_decoding_iso8601Timestamp() throws {
        let json = """
        {"token":"tok_abc","plan":"veil","expires_at":"2027-01-01T00:00:00Z"}
        """.data(using: .utf8)!
        let resp = try JSONDecoder().decode(TokenResponse.self, from: json)
        XCTAssertEqual(resp.token, "tok_abc")
        XCTAssertEqual(resp.plan,  "veil")
        XCTAssertTrue(resp.expiresAt.contains("2027"))
    }

    func testTokenResponse_decoding_intTimestamp() throws {
        let ts = Int(Date(timeIntervalSinceReferenceDate: 0).timeIntervalSince1970)
        let json = """
        {"token":"tok_xyz","plan":"founder","expires_at":\(ts)}
        """.data(using: .utf8)!
        let resp = try JSONDecoder().decode(TokenResponse.self, from: json)
        XCTAssertEqual(resp.token, "tok_xyz")
        XCTAssertEqual(resp.plan,  "founder")
        // Result should be a valid ISO8601 string
        XCTAssertNotNil(ISO8601DateFormatter().date(from: resp.expiresAt))
    }

    func testTokenResponse_decoding_missingToken_throws() {
        let json = """
        {"plan":"veil","expires_at":"2027-01-01T00:00:00Z"}
        """.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(TokenResponse.self, from: json))
    }

    // MARK: - TunnelMode

    func testTunnelMode_displayNames() {
        XCTAssertEqual(TunnelMode.standard.displayName, "Standard")
        XCTAssertEqual(TunnelMode.full.displayName,     "Full (Kill Switch)")
    }

    func testTunnelMode_rawValues() {
        XCTAssertEqual(TunnelMode.standard.rawValue, "standard")
        XCTAssertEqual(TunnelMode.full.rawValue,     "full")
    }
}

// MARK: - Helpers

private extension ModelTests {

    func makeServer(region: String = "us-west") -> VPNServer {
        VPNServer(
            nodeId: "node-1",
            site: "US West",
            region: region,
            displayName: "Oregon",
            ipv4: "1.2.3.4",
            ipv6: nil,
            endpoints: VPNServer.Endpoints(primary: "1.2.3.4:51820", secondary: nil),
            publicKey: "test-pubkey",
            wgPort: 51820,
            loadScore: 0.5,
            ipv6Available: false,
            geodnsWeight: 100
        )
    }

    func makeSubscription(plan: String = "veil", expiresAt: Date? = nil) -> SubscriptionInfo {
        SubscriptionInfo(plan: plan, expiresAt: expiresAt, token: "tok_test")
    }

    func makeLatency(ms: Double) -> ServerLatency {
        ServerLatency(server: makeServer(), milliseconds: ms)
    }

    func makeDnsPreferences(tier: String) -> DnsPreferences {
        DnsPreferences(
            tier: tier,
            protectionLevel: "STANDARD",
            protectionLevels: ["NONE", "LOW", "STANDARD"],
            safeBrowsing: false,
            familyFilter: false,
            blockedServices: [],
            blockableServices: [],
            updatedAt: nil
        )
    }

    func makePlatformStatus(_ status: String) -> PlatformStatus {
        PlatformStatus(
            status: status,
            totalNodes: 6,
            healthyNodes: 6,
            degradedNodes: 0,
            uptimePct: 99.9
        )
    }
}
