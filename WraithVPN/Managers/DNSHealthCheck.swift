// DNSHealthCheck.swift
// WraithVPN
//
// Post-connect tunnel self-test. Runs automatically after the tunnel reports
// .connected and surfaces results as a banner or debug log entry.
//
// Test 1: resolve google.com via Haven DNS at the node's WG mesh IP (10.11.x.1)
// Test 2: WG handshake via NETunnelProviderSession.sendProviderMessage
//
// (Public-IP DNS reachability is a separate concern for off-VPN Haven-DoH
// users and doesn't belong in a post-connect tunnel health check.)
//
// Diagnosis matrix:
//   T1 pass + T2 pass: tunnel healthy
//   T1 pass + T2 fail: DNS resolves but handshake status unknown (unusual — timing)
//   T1 fail + T2 pass: WG connected but Haven DNS unreachable -- AGH down on this node, or AllowedIPs wrong
//   T1 fail + T2 fail: tunnel not routing -- peer revoked or server unreachable, reprovision

import Foundation
import Network

// MARK: - Result types

enum DNSTestResult {
    case passed(latencyMs: Int)
    case failed(Error?)
    case skipped

    var isPassed: Bool {
        if case .passed = self { return true }
        return false
    }
}

struct TunnelHealthReport {
    let havenDNS: DNSTestResult
    let handshakeOK: Bool
    let timestamp: Date

    var isHealthy: Bool {
        handshakeOK
    }

    var diagnosis: String {
        switch (havenDNS.isPassed, handshakeOK) {
        case (true, true):
            return "Tunnel healthy"
        case (true, false):
            return "DNS resolving but handshake status unknown"
        case (false, true):
            return "Tunnel active. Haven DNS probe inconclusive."
        case (false, false):
            return "Tunnel not routing traffic. Peer may be revoked or server unreachable. Re-provisioning recommended."
        }
    }

    var needsReprovision: Bool {
        !handshakeOK && !havenDNS.isPassed
    }
}

// MARK: - Health checker

final class DNSHealthCheck {

    static let shared = DNSHealthCheck()
    private init() {}

    /// Runs the full health check suite. Timeout per test: 5 seconds.
    func runHealthCheck(havenDNSIP: String?, connection: Any?) async -> TunnelHealthReport {
        let dbg = await DebugLogger.shared

        await dbg.dns("Starting post-connect health check")

        // Test 1: Haven DNS (node's WG interface IP, in-tunnel)
        let havenResult: DNSTestResult
        if let havenIP = havenDNSIP, !havenIP.isEmpty {
            await dbg.dns("Test 1: resolving google.com via Haven DNS \(havenIP)")
            havenResult = await resolveDNS(server: havenIP, hostname: "google.com")
        } else {
            await dbg.dns("Test 1: skipped (no Haven DNS IP)")
            havenResult = .skipped
        }

        // Test 2: WG handshake check via tunnel provider message
        await dbg.dns("Test 2: checking WG handshake status")
        let handshakeOK = await checkHandshake(connection: connection)

        let report = TunnelHealthReport(
            havenDNS: havenResult,
            handshakeOK: handshakeOK,
            timestamp: Date()
        )

        await dbg.dns("Health check complete: \(report.diagnosis)")
        if case .passed(let ms) = report.havenDNS {
            await dbg.dns("Haven DNS: OK (\(ms)ms)")
        }
        if case .failed(let err) = report.havenDNS {
            await dbg.dns("Haven DNS: FAILED (\(err?.localizedDescription ?? "timeout"))")
        }
        await dbg.dns("WG handshake: \(handshakeOK ? "OK" : "FAILED")")

        return report
    }

    // MARK: - DNS resolution test

    /// Sends a raw UDP DNS query to the specified server and waits for a response.
    /// This bypasses the system resolver so we test the exact DNS server we want.
    private func resolveDNS(server: String, hostname: String, timeoutSecs: Double = 5.0) async -> DNSTestResult {
        let start = CFAbsoluteTimeGetCurrent()

        return await withCheckedContinuation { continuation in
            let host = NWEndpoint.Host(server)
            let port = NWEndpoint.Port(integerLiteral: 53)
            let params = NWParameters.udp
            let connection = NWConnection(host: host, port: port, using: params)

            var completed = false
            let lock = NSLock()

            func complete(_ result: DNSTestResult) {
                lock.lock()
                guard !completed else { lock.unlock(); return }
                completed = true
                lock.unlock()
                connection.cancel()
                continuation.resume(returning: result)
            }

            // Timeout
            DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSecs) {
                complete(.failed(nil))
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    // Build a minimal DNS A query for the hostname
                    let query = Self.buildDNSQuery(for: hostname)
                    connection.send(content: query, completion: .contentProcessed({ error in
                        if let error {
                            complete(.failed(error))
                            return
                        }
                        // Wait for response
                        connection.receive(minimumIncompleteLength: 1, maximumLength: 512) { data, _, _, error in
                            if let error {
                                complete(.failed(error))
                                return
                            }
                            guard let data, data.count >= 12 else {
                                complete(.failed(nil))
                                return
                            }
                            // Check RCODE in DNS header (bits 12-15 of byte 3)
                            let flags = data[3]
                            let rcode = flags & 0x0F
                            let elapsed = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
                            if rcode == 0 { // NOERROR
                                complete(.passed(latencyMs: elapsed))
                            } else {
                                complete(.failed(nil))
                            }
                        }
                    }))
                case .failed(let error):
                    complete(.failed(error))
                case .cancelled:
                    break
                default:
                    break
                }
            }

            connection.start(queue: .global())
        }
    }

    /// Builds a minimal DNS A query packet for the given hostname.
    private static func buildDNSQuery(for hostname: String) -> Data {
        var data = Data()
        // Transaction ID
        data.append(contentsOf: [0xAB, 0xCD])
        // Flags: standard query, recursion desired
        data.append(contentsOf: [0x01, 0x00])
        // Questions: 1, Answers: 0, Authority: 0, Additional: 0
        data.append(contentsOf: [0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        // QNAME: encode each label
        for label in hostname.split(separator: ".") {
            data.append(UInt8(label.count))
            data.append(contentsOf: label.utf8)
        }
        data.append(0x00) // root label
        // QTYPE: A (1)
        data.append(contentsOf: [0x00, 0x01])
        // QCLASS: IN (1)
        data.append(contentsOf: [0x00, 0x01])
        return data
    }

    // MARK: - WG handshake check

    /// Queries the tunnel extension for runtime config. If the extension responds
    /// with a config that includes a recent last_handshake_time_sec, the tunnel is live.
    private func checkHandshake(connection: Any?) async -> Bool {
        // The tunnel extension responds to a single-byte message (0x00) with
        // the WireGuard runtime configuration as UTF-8 text.
        guard let session = connection as? NETunnelProviderSessionProtocol else {
            return false
        }

        return await withCheckedContinuation { continuation in
            do {
                var completed = false
                let lock = NSLock()

                func complete(_ result: Bool) {
                    lock.lock()
                    guard !completed else { lock.unlock(); return }
                    completed = true
                    lock.unlock()
                    continuation.resume(returning: result)
                }

                // Timeout after 3 seconds
                DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                    complete(false)
                }

                try session.sendProviderMessage(Data([0])) { response in
                    guard let data = response,
                          let text = String(data: data, encoding: .utf8) else {
                        complete(false)
                        return
                    }
                    // Parse last_handshake_time_sec from the runtime config.
                    // Format: "last_handshake_time_sec=1712345678\n"
                    // A value of 0 means no handshake has occurred.
                    let handshakeOK = text.contains("last_handshake_time_sec=")
                        && !text.contains("last_handshake_time_sec=0\n")
                    complete(handshakeOK)
                }
            } catch {
                continuation.resume(returning: false)
            }
        }
    }
}

// MARK: - Protocol for testability

/// Abstraction over NETunnelProviderSession so we can send provider messages.
/// The real NETunnelProviderSession doesn't conform to any useful protocol,
/// so we define one and extend it.
protocol NETunnelProviderSessionProtocol {
    func sendProviderMessage(_ messageData: Data, responseHandler: ((Data?) -> Void)?) throws
}

import NetworkExtension

extension NETunnelProviderSession: NETunnelProviderSessionProtocol {}
