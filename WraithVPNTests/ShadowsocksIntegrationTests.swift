// ShadowsocksIntegrationTests.swift
// WraithVPNTests
//
// Integration tests for the SS-2022 fallback transport.
// All tests require WRAITH_INTEGRATION_TESTS=1 in the environment.
// Run only on a physical device or a host with network access to vpn-iad-01.

import XCTest
@testable import WraithVPN
import Foundation

final class ShadowsocksIntegrationTests: XCTestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        guard ProcessInfo.processInfo.environment["WRAITH_INTEGRATION_TESTS"] == "1" else {
            throw XCTSkip("Set WRAITH_INTEGRATION_TESTS=1 to run integration tests")
        }
    }

    // MARK: - ProvisionResponse decode (no network)

    func testProvisionResponseDecodesShadowsocksFallback() throws {
        // Verify that ProvisionResponse properly decodes the shadowsocks_fallback block
        // returned by POST /v1/peers/provision.
        let json = """
        {
            "config": "# This would be a WireGuard config string",
            "config_qr": null,
            "node_id": "vpn-iad-01",
            "endpoint": "87.99.128.159:51820",
            "assigned_ipv4": "10.10.6.15",
            "shadowsocks_fallback": {
                "server": "vpn-iad-01.vpn.katafract.com",
                "port": 8443,
                "method": "2022-blake3-aes-256-gcm",
                "password": "UjZyxPKMWrhIqQk/icUUVk5RH0QZCJrREQaZWahMK2s=:A4aTuxJuOX5elNa99mgNUFhrDwsIvqLLTUu82X0SEmY=",
                "plugin": "v2ray-plugin",
                "plugin_opts": "tls;host=vpn-iad-01.vpn.katafract.com"
            }
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(ProvisionResponse.self, from: json)

        XCTAssertNotNil(response.shadowsocksFallback, "shadowsocksFallback must be decoded")

        let fb = try XCTUnwrap(response.shadowsocksFallback)
        XCTAssertEqual(fb.server, "vpn-iad-01.vpn.katafract.com")
        XCTAssertEqual(fb.port, 8443)
        XCTAssertEqual(fb.method, "2022-blake3-aes-256-gcm")
        XCTAssertEqual(fb.plugin, "v2ray-plugin")
        XCTAssertEqual(fb.pluginOpts, "tls;host=vpn-iad-01.vpn.katafract.com")
        XCTAssertTrue(fb.password.contains(":"), "Password must contain ':' PSK separator")

        // Verify the two PSK components are both valid base64
        let parts = fb.password.split(separator: ":", maxSplits: 1)
        XCTAssertEqual(parts.count, 2, "Password must have exactly two ':'-separated parts")
        let serverPSK = Data(base64Encoded: String(parts[0]))
        let userPSK = Data(base64Encoded: String(parts[1]))
        XCTAssertEqual(serverPSK?.count, 32, "Server PSK must be 32 bytes")
        XCTAssertEqual(userPSK?.count, 32, "User PSK must be 32 bytes")
    }

    // MARK: - TCP reachability (live network)

    func testShadowsocksEndpointTCPReachability() throws {
        // Verify TCP + TLS reachability to vpn-iad-01:8443.
        // The server runs ssservice+v2ray-plugin behind TLS. An HTTP request will
        // fail at the app layer (SS is not HTTP), but any response — including a TLS
        // error or reset — proves the TCP/TLS path is open.
        let url = URL(string: "https://vpn-iad-01.vpn.katafract.com:8443/")!
        var request = URLRequest(url: url, timeoutInterval: 5.0)
        request.httpMethod = "GET"

        let expectation = expectation(description: "TCP reachability")
        let session = URLSession(configuration: .ephemeral)
        var tcpReached = false

        session.dataTask(with: request) { _, _, error in
            defer { expectation.fulfill() }
            if let nsError = error as NSError? {
                // A TLS/protocol error means TCP connected successfully
                let acceptableDomains = [NSURLErrorDomain, "kCFErrorDomainCFNetwork"]
                let acceptableCodes = [
                    NSURLErrorBadServerResponse,        // got a response but not HTTP
                    NSURLErrorSecureConnectionFailed,   // TLS connected, protocol mismatch
                    NSURLErrorServerCertificateUntrusted,
                    -1200  // SSL error — connection made but cert check
                ]
                if acceptableDomains.contains(nsError.domain) &&
                   !acceptableCodes.contains(nsError.code) &&
                   nsError.code != NSURLErrorTimedOut &&
                   nsError.code != NSURLErrorCannotConnectToHost &&
                   nsError.code != NSURLErrorNetworkConnectionLost {
                    // Any error except "couldn't connect" means TCP succeeded
                    tcpReached = true
                } else if acceptableCodes.contains(nsError.code) {
                    tcpReached = true
                }
                // If timeout or can't connect → tcpReached stays false
            } else {
                // Got an HTTP response — definitely connected
                tcpReached = true
            }
        }.resume()

        waitForExpectations(timeout: 10.0)
        XCTAssertTrue(tcpReached,
            "vpn-iad-01.vpn.katafract.com:8443 must be TCP-reachable for SS fallback to work")
    }
}
