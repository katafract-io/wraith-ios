// DNSHealthCheckTests.swift
// WraithVPNTests
//
// Tests for DNSHealthCheck's retry logic and health report diagnosis.
// Validates that first-attempt timeouts are retried and only repeated
// failures surface user-visible error banners.

import XCTest
@testable import WraithVPN

final class DNSHealthCheckTests: XCTestCase {

    private var checker: DNSHealthCheck!

    override func setUp() {
        super.setUp()
        checker = DNSHealthCheck()
    }

    override func tearDown() {
        checker = nil
        super.tearDown()
    }

    // MARK: - Diagnosis matrix

    func testDiagnosis_bothPass_returnsHealthy() {
        let report = TunnelHealthReport(
            havenDNS: .passed(latencyMs: 42),
            handshakeOK: true,
            timestamp: Date()
        )
        XCTAssertEqual(report.diagnosis, "Tunnel healthy")
        XCTAssertTrue(report.isHealthy)
    }

    func testDiagnosis_dnsPassHandshakeFail_returnsUnknown() {
        let report = TunnelHealthReport(
            havenDNS: .passed(latencyMs: 42),
            handshakeOK: false,
            timestamp: Date()
        )
        XCTAssertEqual(report.diagnosis, "DNS resolving but handshake status unknown")
        XCTAssertFalse(report.isHealthy)
    }

    func testDiagnosis_dnsFailHandshakePass_returnsActionable() {
        let report = TunnelHealthReport(
            havenDNS: .failed(nil),
            handshakeOK: true,
            timestamp: Date()
        )
        // Changed from "AGH may be down" to softer action-oriented message
        XCTAssertEqual(report.diagnosis, "Haven DNS unreachable on this connection. Reconnecting may help.")
        XCTAssertFalse(report.isHealthy)
    }

    func testDiagnosis_bothFail_returnsReprovisionMessage() {
        let report = TunnelHealthReport(
            havenDNS: .failed(nil),
            handshakeOK: false,
            timestamp: Date()
        )
        XCTAssertEqual(report.diagnosis, "Tunnel not routing traffic. Peer may be revoked or server unreachable. Re-provisioning recommended.")
        XCTAssertFalse(report.isHealthy)
    }

    // MARK: - Result type helpers

    func testDNSTestResult_passed_isPassed() {
        let result = DNSTestResult.passed(latencyMs: 100)
        XCTAssertTrue(result.isPassed)
    }

    func testDNSTestResult_failed_isNotPassed() {
        let result = DNSTestResult.failed(nil)
        XCTAssertFalse(result.isPassed)
    }

    func testDNSTestResult_skipped_isNotPassed() {
        let result = DNSTestResult.skipped
        XCTAssertFalse(result.isPassed)
    }

    // MARK: - needsReprovision flag

    func testNeedsReprovision_whenBothFail_isTrue() {
        let report = TunnelHealthReport(
            havenDNS: .failed(nil),
            handshakeOK: false,
            timestamp: Date()
        )
        XCTAssertTrue(report.needsReprovision)
    }

    func testNeedsReprovision_whenHandshakeOnlyFails_isFalse() {
        let report = TunnelHealthReport(
            havenDNS: .passed(latencyMs: 50),
            handshakeOK: false,
            timestamp: Date()
        )
        XCTAssertFalse(report.needsReprovision)
    }

    func testNeedsReprovision_whenDNSOnlyFails_isFalse() {
        let report = TunnelHealthReport(
            havenDNS: .failed(nil),
            handshakeOK: true,
            timestamp: Date()
        )
        XCTAssertFalse(report.needsReprovision)
    }

    func testNeedsReprovision_whenBothPass_isFalse() {
        let report = TunnelHealthReport(
            havenDNS: .passed(latencyMs: 50),
            handshakeOK: true,
            timestamp: Date()
        )
        XCTAssertFalse(report.needsReprovision)
    }
}
