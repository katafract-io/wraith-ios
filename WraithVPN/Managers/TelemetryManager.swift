import Foundation
import NetworkExtension

@MainActor
final class TelemetryManager {
    static let shared = TelemetryManager()

    private var currentSession: SessionState?
    private var pollTask: Task<Void, Never>?
    private let pollInterval: TimeInterval = 30

    private struct SessionState {
        let startTime: Date
        let nodeId: String
        var connection: NETunnelProviderSession?
        var samples: [WireGuardSample] = []
        var handshakeFailures: Int = 0
        var reprovisionCount: Int = 0
    }

    private struct WireGuardSample {
        let timestamp: Date
        let rxBytes: Int64
        let txBytes: Int64
        let lastHandshakeTimeSec: Int64
    }

    private init() {}

    func sessionStarted(nodeId: String, connection: NETunnelProviderSession) {
        currentSession = SessionState(startTime: Date(), nodeId: nodeId, connection: connection)
        startPolling()
    }

    func recordHandshakeFailure() {
        currentSession?.handshakeFailures += 1
    }

    func recordReprovision() {
        currentSession?.reprovisionCount += 1
    }

    func sessionEnded(connection: NETunnelProviderSession?) async {
        guard let session = currentSession else { return }

        pollTask?.cancel()
        pollTask = nil

        let duration = Date().timeIntervalSince(session.startTime)
        guard duration >= 10 else {
            currentSession = nil
            return
        }

        let finalConnection = connection ?? session.connection
        let stats = await fetchWireGuardStats(from: finalConnection)

        let payload = buildPayload(
            session: session,
            duration: duration,
            finalStats: stats
        )

        await postTelemetry(payload)
        currentSession = nil
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                if let stats = await fetchWireGuardStats(from: currentSession?.connection) {
                    currentSession?.samples.append(stats)
                }
                try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
            }
        }
    }

    private func fetchWireGuardStats(from connection: NETunnelProviderSession?) async -> WireGuardSample? {
        guard let connection = connection else { return nil }

        let configText: String? = await withCheckedContinuation { continuation in
            var completed = false
            let lock = NSLock()
            func finish(_ value: String?) {
                lock.lock()
                guard !completed else { lock.unlock(); return }
                completed = true
                lock.unlock()
                continuation.resume(returning: value)
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) { finish(nil) }
            do {
                try connection.sendProviderMessage(Data([0])) { response in
                    guard let data = response else { finish(nil); return }
                    finish(String(data: data, encoding: .utf8))
                }
            } catch {
                finish(nil)
            }
        }

        guard let configText else { return nil }

        var rxBytes: Int64 = 0
        var txBytes: Int64 = 0
        var lastHandshakeTimeSec: Int64 = 0

        for line in configText.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
            switch key {
            case "rx_bytes":              rxBytes = Int64(value) ?? 0
            case "tx_bytes":              txBytes = Int64(value) ?? 0
            case "last_handshake_time_sec": lastHandshakeTimeSec = Int64(value) ?? 0
            default: break
            }
        }

        return WireGuardSample(
            timestamp: Date(),
            rxBytes: rxBytes,
            txBytes: txBytes,
            lastHandshakeTimeSec: lastHandshakeTimeSec
        )
    }

    private func buildPayload(
        session: SessionState,
        duration: TimeInterval,
        finalStats: WireGuardSample?
    ) -> SessionTelemetryPayload {
        let platform: String
        #if os(iOS)
        platform = "ios"
        #else
        platform = "macos"
        #endif

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"

        let (avgTx, avgRx, peakTx, peakRx) = computeThroughput()
        let finalRxBytes = finalStats?.rxBytes ?? (session.samples.last?.rxBytes ?? 0)
        let finalTxBytes = finalStats?.txBytes ?? (session.samples.last?.txBytes ?? 0)
        let lastHandshakeAge = computeLastHandshakeAge(finalStats: finalStats)

        return SessionTelemetryPayload(
            node_id: session.nodeId,
            platform: platform,
            app_version: appVersion,
            session_duration_s: Int(duration),
            tx_bytes: finalTxBytes,
            rx_bytes: finalRxBytes,
            peak_tx_kbps: peakTx,
            peak_rx_kbps: peakRx,
            avg_tx_kbps: avgTx,
            avg_rx_kbps: avgRx,
            last_handshake_age_s: lastHandshakeAge,
            handshake_failures: session.handshakeFailures,
            reprovision_count: session.reprovisionCount
        )
    }

    private func computeThroughput() -> (avgTx: Double, avgRx: Double, peakTx: Double, peakRx: Double) {
        guard let session = currentSession, session.samples.count >= 2 else {
            return (0, 0, 0, 0)
        }

        let duration = Date().timeIntervalSince(session.startTime)
        guard duration > 0 else { return (0, 0, 0, 0) }

        let totalRx = (session.samples.last?.rxBytes ?? 0) - (session.samples.first?.rxBytes ?? 0)
        let totalTx = (session.samples.last?.txBytes ?? 0) - (session.samples.first?.txBytes ?? 0)

        let avgRx = (Double(totalRx) / 1000) / duration
        let avgTx = (Double(totalTx) / 1000) / duration

        var peakRx: Double = 0
        var peakTx: Double = 0

        for i in 1..<session.samples.count {
            let prev = session.samples[i - 1]
            let curr = session.samples[i]
            let timeDelta = curr.timestamp.timeIntervalSince(prev.timestamp)

            if timeDelta > 0 {
                let rxDelta = Double(curr.rxBytes - prev.rxBytes) / 1000 / timeDelta
                let txDelta = Double(curr.txBytes - prev.txBytes) / 1000 / timeDelta
                peakRx = max(peakRx, rxDelta)
                peakTx = max(peakTx, txDelta)
            }
        }

        return (avgTx, avgRx, peakTx, peakRx)
    }

    private func computeLastHandshakeAge(finalStats: WireGuardSample?) -> Int {
        guard let finalStats = finalStats else { return 0 }
        let now = Int64(Date().timeIntervalSince1970)
        let age = now - finalStats.lastHandshakeTimeSec
        return max(0, Int(age))
    }

    private func postTelemetry(_ payload: SessionTelemetryPayload) async {
        let url = URL(string: "https://api.katafract.com/v1/telemetry/session")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let encoder = JSONEncoder()
            request.httpBody = try encoder.encode(payload)
        } catch {
            return
        }

        Task(priority: .background) {
            do {
                _ = try await URLSession.shared.data(for: request)
            } catch {
                // Silently ignore errors
            }
        }
    }
}

struct SessionTelemetryPayload: Codable {
    var node_id: String
    var platform: String
    var app_version: String
    var session_duration_s: Int
    var tx_bytes: Int64
    var rx_bytes: Int64
    var peak_tx_kbps: Double
    var peak_rx_kbps: Double
    var avg_tx_kbps: Double
    var avg_rx_kbps: Double
    var last_handshake_age_s: Int
    var handshake_failures: Int
    var reprovision_count: Int
}
