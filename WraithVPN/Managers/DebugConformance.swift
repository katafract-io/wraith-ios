// DebugConformance.swift
// WraithVPN
//
// Debug-only conformance runner for WG/SS mode toggles, region switches,
// reconnects, and packet/DNS verification. Founder-only feature.
// Cells are named test scenarios that exercise production code paths.
// Results are logged to DebugLogger and posted to the API for analysis.

import Foundation
import Combine
import Network

// MARK: - Cell enum

enum DebugConformanceCell: String, CaseIterable {
    case wgToSsToggle           = "wgToSsToggle"
    case ssToWgToggle           = "ssToWgToggle"
    case regionSwitchUnderWg    = "regionSwitchUnderWg"
    case regionSwitchUnderSs    = "regionSwitchUnderSs"
    case reconnectAfterKill     = "reconnectAfterKill"
    case packetFlowVerify       = "packetFlowVerify"
    case havenDnsBlockedDomain  = "havenDnsBlockedDomain"

    var displayName: String {
        switch self {
        case .wgToSsToggle:         return "WG → SS toggle on same node"
        case .ssToWgToggle:         return "SS → WG toggle on same node"
        case .regionSwitchUnderWg:  return "Region switch while on WG"
        case .regionSwitchUnderSs:  return "Region switch while on SS"
        case .reconnectAfterKill:   return "Re-engage after kill+relaunch (manual: kill the app first)"
        case .packetFlowVerify:     return "Packet flow through tunnel (HTTP GET ifconfig.me)"
        case .havenDnsBlockedDomain: return "Haven blocks ad domain (DNS resolves doubleclick.net to 0.0.0.0)"
        }
    }
}

// MARK: - Result

struct DebugConformanceResult: Identifiable, Codable {
    let id: UUID
    let cell: String
    let startedAt: Date
    let durationMs: Int
    let pass: Bool
    let reason: String
    let details: [String: String]

    enum CodingKeys: String, CodingKey {
        case id, cell, startedAt, durationMs, pass, reason, details
    }
}

// MARK: - Runner

@MainActor
final class DebugConformanceRunner: ObservableObject {

    static let shared = DebugConformanceRunner()

    @Published var lastResults: [String: DebugConformanceResult] = [:]
    @Published var isRunning: String? = nil

    private init() {}

    // MARK: - Public API

    func run(_ cell: DebugConformanceCell) async {
        guard isRunning == nil else {
            DebugLogger.shared.conformance("Cell \(cell.rawValue) already running")
            return
        }

        isRunning = cell.rawValue
        DebugLogger.shared.conformance("Starting cell: \(cell.displayName)")

        let start = Date()
        let result: DebugConformanceResult

        switch cell {
        case .wgToSsToggle:
            result = await runWgToSsToggle(startedAt: start)
        case .ssToWgToggle:
            result = await runSsToWgToggle(startedAt: start)
        case .regionSwitchUnderWg:
            result = await runRegionSwitchUnderWg(startedAt: start)
        case .regionSwitchUnderSs:
            result = await runRegionSwitchUnderSs(startedAt: start)
        case .reconnectAfterKill:
            result = await runReconnectAfterKill(startedAt: start)
        case .packetFlowVerify:
            result = await runPacketFlowVerify(startedAt: start)
        case .havenDnsBlockedDomain:
            result = await runHavenDnsBlockedDomain(startedAt: start)
        }

        lastResults[cell.rawValue] = result
        DebugLogger.shared.conformance(
            "Cell \(cell.rawValue) \(result.pass ? "PASS" : "FAIL"): \(result.reason) (\(result.durationMs)ms)"
        )

        // Best-effort upload; don't fail the cell if this fails
        await uploadResult(result)

        isRunning = nil
    }

    /// Run all cells sequentially with 2s gap.
    func runAll() async {
        for (index, cell) in DebugConformanceCell.allCases.enumerated() {
            if index > 0 {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
            await run(cell)
        }
    }

    // MARK: - Private: Cell implementations

    private func runWgToSsToggle(startedAt: Date) async -> DebugConformanceResult {
        let id = UUID()
        DebugLogger.shared.conformance("[\(id)] Toggle WG → SS on same node")

        // Stub: real impl would toggle transport and verify state
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        let duration = Int(Date().timeIntervalSince(startedAt) * 1000)
        return DebugConformanceResult(
            id: id,
            cell: DebugConformanceCell.wgToSsToggle.rawValue,
            startedAt: startedAt,
            durationMs: duration,
            pass: false,
            reason: "stub — implement per cell spec",
            details: [:]
        )
    }

    private func runSsToWgToggle(startedAt: Date) async -> DebugConformanceResult {
        let id = UUID()
        DebugLogger.shared.conformance("[\(id)] Toggle SS → WG on same node")

        try? await Task.sleep(nanoseconds: 1_000_000_000)

        let duration = Int(Date().timeIntervalSince(startedAt) * 1000)
        return DebugConformanceResult(
            id: id,
            cell: DebugConformanceCell.ssToWgToggle.rawValue,
            startedAt: startedAt,
            durationMs: duration,
            pass: false,
            reason: "stub — implement per cell spec",
            details: [:]
        )
    }

    private func runRegionSwitchUnderWg(startedAt: Date) async -> DebugConformanceResult {
        let id = UUID()
        DebugLogger.shared.conformance("[\(id)] Region switch while on WG")

        try? await Task.sleep(nanoseconds: 1_000_000_000)

        let duration = Int(Date().timeIntervalSince(startedAt) * 1000)
        return DebugConformanceResult(
            id: id,
            cell: DebugConformanceCell.regionSwitchUnderWg.rawValue,
            startedAt: startedAt,
            durationMs: duration,
            pass: false,
            reason: "stub — implement per cell spec",
            details: [:]
        )
    }

    private func runRegionSwitchUnderSs(startedAt: Date) async -> DebugConformanceResult {
        let id = UUID()
        DebugLogger.shared.conformance("[\(id)] Region switch while on SS")

        try? await Task.sleep(nanoseconds: 1_000_000_000)

        let duration = Int(Date().timeIntervalSince(startedAt) * 1000)
        return DebugConformanceResult(
            id: id,
            cell: DebugConformanceCell.regionSwitchUnderSs.rawValue,
            startedAt: startedAt,
            durationMs: duration,
            pass: false,
            reason: "stub — implement per cell spec",
            details: [:]
        )
    }

    private func runReconnectAfterKill(startedAt: Date) async -> DebugConformanceResult {
        let id = UUID()
        DebugLogger.shared.conformance("[\(id)] Reconnect after kill+relaunch")

        try? await Task.sleep(nanoseconds: 1_000_000_000)

        let duration = Int(Date().timeIntervalSince(startedAt) * 1000)
        return DebugConformanceResult(
            id: id,
            cell: DebugConformanceCell.reconnectAfterKill.rawValue,
            startedAt: startedAt,
            durationMs: duration,
            pass: false,
            reason: "stub — implement per cell spec",
            details: [:]
        )
    }

    /// Real implementation: fetch ifconfig.me and check response.
    private func runPacketFlowVerify(startedAt: Date) async -> DebugConformanceResult {
        let id = UUID()
        DebugLogger.shared.conformance("[\(id)] Verifying packet flow via ifconfig.me")

        var pass = false
        var reason = "timeout or network error"
        var details: [String: String] = [:]

        let url = URL(string: "https://ifconfig.me")!
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5.0
        let session = URLSession(configuration: config)

        do {
            let (data, _) = try await session.data(from: url)
            if let ip = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                DebugLogger.shared.conformance("[\(id)] ifconfig.me returned: \(ip)")
                details["exit_ip"] = ip
                pass = true
                reason = "received exit IP: \(ip)"
            }
        } catch {
            DebugLogger.shared.conformance("[\(id)] ifconfig.me error: \(error.localizedDescription)")
            reason = error.localizedDescription
        }

        let duration = Int(Date().timeIntervalSince(startedAt) * 1000)
        return DebugConformanceResult(
            id: id,
            cell: DebugConformanceCell.packetFlowVerify.rawValue,
            startedAt: startedAt,
            durationMs: duration,
            pass: pass,
            reason: reason,
            details: details
        )
    }

    /// Real implementation: query Haven DNS for doubleclick.net and verify 0.0.0.0 response.
    private func runHavenDnsBlockedDomain(startedAt: Date) async -> DebugConformanceResult {
        let id = UUID()
        DebugLogger.shared.conformance("[\(id)] Verifying Haven DNS blocks doubleclick.net")

        var pass = false
        var reason = "not tested or timeout"
        var details: [String: String] = [:]

        // Get Haven DNS IP from WireGuardManager
        let vpn = WireGuardManager.shared
        guard let assignedIP = vpn.assignedIP else {
            DebugLogger.shared.conformance("[\(id)] No assigned IP — tunnel may not be connected")
            reason = "tunnel not connected (no assigned IP)"
            let duration = Int(Date().timeIntervalSince(startedAt) * 1000)
            return DebugConformanceResult(
                id: id,
                cell: DebugConformanceCell.havenDnsBlockedDomain.rawValue,
                startedAt: startedAt,
                durationMs: duration,
                pass: pass,
                reason: reason,
                details: details
            )
        }

        let parts = assignedIP.split(separator: ".")
        guard parts.count == 4 else {
            DebugLogger.shared.conformance("[\(id)] Invalid assigned IP format: \(assignedIP)")
            reason = "invalid assigned IP"
            let duration = Int(Date().timeIntervalSince(startedAt) * 1000)
            return DebugConformanceResult(
                id: id,
                cell: DebugConformanceCell.havenDnsBlockedDomain.rawValue,
                startedAt: startedAt,
                durationMs: duration,
                pass: pass,
                reason: reason,
                details: details
            )
        }

        let havenIP = "\(parts[0]).\(parts[1]).\(parts[2]).1"
        DebugLogger.shared.conformance("[\(id)] Haven DNS IP: \(havenIP)")

        let result = await resolveDnsQuery(server: havenIP, hostname: "doubleclick.net", timeoutSecs: 5.0)

        switch result {
        case .passed(let rcode, let answers):
            // Check if the first answer is 0.0.0.0 (blocked)
            if answers.contains("0.0.0.0") {
                pass = true
                reason = "doubleclick.net resolved to 0.0.0.0 (blocked)"
                details["rcode"] = "\(rcode)"
                details["blocked"] = "true"
            } else {
                reason = "domain resolved but not to 0.0.0.0: \(answers.joined(separator: ", "))"
                details["rcode"] = "\(rcode)"
                details["answers"] = answers.joined(separator: ", ")
            }
            DebugLogger.shared.conformance("[\(id)] DNS result: \(reason)")
        case .failed(let error):
            reason = error ?? "unknown error"
            details["error"] = reason
            DebugLogger.shared.conformance("[\(id)] DNS query failed: \(reason)")
        }

        let duration = Int(Date().timeIntervalSince(startedAt) * 1000)
        return DebugConformanceResult(
            id: id,
            cell: DebugConformanceCell.havenDnsBlockedDomain.rawValue,
            startedAt: startedAt,
            durationMs: duration,
            pass: pass,
            reason: reason,
            details: details
        )
    }

    // MARK: - DNS query helper

    private func resolveDnsQuery(
        server: String,
        hostname: String,
        timeoutSecs: Double
    ) async -> DnsQueryResult {
        let start = CFAbsoluteTimeGetCurrent()

        return await withCheckedContinuation { continuation in
            let host = NWEndpoint.Host(server)
            let port = NWEndpoint.Port(integerLiteral: 53)
            let params = NWParameters.udp
            let connection = NWConnection(host: host, port: port, using: params)

            var completed = false
            let lock = NSLock()

            func complete(_ result: DnsQueryResult) {
                lock.lock()
                guard !completed else { lock.unlock(); return }
                completed = true
                lock.unlock()
                connection.cancel()
                continuation.resume(returning: result)
            }

            // Timeout
            DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSecs) {
                complete(.failed("timeout"))
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let query = buildDNSQuery(for: hostname)
                    connection.send(content: query, completion: .contentProcessed({ error in
                        if let error {
                            complete(.failed(error.localizedDescription))
                            return
                        }
                        // Wait for response
                        connection.receive(minimumIncompleteLength: 1, maximumLength: 512) { data, _, _, error in
                            if let error {
                                complete(.failed(error.localizedDescription))
                                return
                            }
                            guard let data, data.count >= 12 else {
                                complete(.failed("response too short"))
                                return
                            }

                            // Parse DNS response header
                            let flags = data[3]
                            let rcode = flags & 0x0F

                            // Extract answer count
                            let answerCount = Int(data[6]) << 8 | Int(data[7])

                            // Simple parser: skip questions, parse answers for A records (type 1)
                            var offset = 12
                            let questionCount = Int(data[4]) << 8 | Int(data[5])

                            // Skip questions
                            for _ in 0..<questionCount {
                                // Skip QNAME (variable length)
                                while offset < data.count && data[offset] != 0 {
                                    let len = Int(data[offset])
                                    offset += len + 1
                                }
                                offset += 1 // skip root label
                                offset += 4 // skip QTYPE + QCLASS
                            }

                            var addresses: [String] = []
                            // Parse answers
                            for _ in 0..<answerCount {
                                // Skip NAME (pointer or label)
                                if offset < data.count {
                                    let byte = data[offset]
                                    if byte & 0xC0 == 0xC0 {
                                        // Pointer
                                        offset += 2
                                    } else {
                                        // Label
                                        while offset < data.count && data[offset] != 0 {
                                            let len = Int(data[offset])
                                            offset += len + 1
                                        }
                                        offset += 1
                                    }

                                    // TYPE, CLASS, TTL
                                    if offset + 10 <= data.count {
                                        let recordType = Int(data[offset]) << 8 | Int(data[offset + 1])
                                        let dataLen = Int(data[offset + 8]) << 8 | Int(data[offset + 9])
                                        offset += 10

                                        // If A record (type 1), extract IP
                                        if recordType == 1 && dataLen == 4 && offset + 4 <= data.count {
                                            let ip = "\(data[offset]).\(data[offset + 1]).\(data[offset + 2]).\(data[offset + 3])"
                                            addresses.append(ip)
                                        }
                                        offset += dataLen
                                    }
                                }
                            }

                            let elapsed = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
                            complete(.passed(rcode: Int(rcode), answers: addresses))
                        }
                    }))
                case .failed(let error):
                    complete(.failed(error?.localizedDescription ?? "connection failed"))
                case .cancelled:
                    break
                default:
                    break
                }
            }

            connection.start(queue: .global())
        }
    }

    private func buildDNSQuery(for hostname: String) -> Data {
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

    // MARK: - Upload

    private func uploadResult(_ result: DebugConformanceResult) async {
        guard let token = try? await WireGuardManager.shared.currentToken() else {
            DebugLogger.shared.conformance("Upload: no auth token")
            return
        }

        let url = URL(string: "https://api.katafract.com/v1/internal/conformance/upload")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONEncoder().encode(result)
            let session = URLSession.shared
            let (_, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                DebugLogger.shared.conformance("Upload: cell \(result.cell) OK")
            } else {
                DebugLogger.shared.conformance("Upload: unexpected status code")
            }
        } catch {
            DebugLogger.shared.conformance("Upload: \(error.localizedDescription)")
        }
    }
}

// MARK: - DNS query result

enum DnsQueryResult {
    case passed(rcode: Int, answers: [String])
    case failed(String)
}
