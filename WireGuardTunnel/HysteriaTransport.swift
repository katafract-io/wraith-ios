// HysteriaTransport.swift
// WireGuardTunnel
//
// Hysteria 2 stealth transport. Replaces ShadowsocksTransport in Stealth-Auto
// mode after the SS+v2ray-plugin data plane was proven broken (server tcpdump
// 0 packets while iOS reported "pumps running" — see memory file
// project_wraith_stealth_dataplane_broken_2026_05_01.md).
//
// Architecture (Pattern B — local UDP forwarder, no custom WG Bind):
//
//   1. NE extension reads activeHysteriaConfig from App Group.
//   2. Starts hysbind.Client.start() → opens local UDP listener on
//      127.0.0.1:NNNNN, returns that address as a string.
//   3. We rewrite the parsed WG TunnelConfiguration's peer endpoint from the
//      real server (e.g. 5.78.207.199:51820) to 127.0.0.1:NNNNN.
//   4. WireGuardKit starts normally. Every WG datagram it sends to the local
//      port is read by hysbind, wrapped in QUIC, and tunneled to the
//      Hysteria 2 server (port 443 fleet default, 8444 pdx-02 canary).
//   5. Server-side: Hysteria forwards inbound UDP to "127.0.0.1:51820" — its
//      own wg0 kernel listener. Replies trace the same path back.
//
// No custom Bind, no manual packetFlow plumbing, no DNS/WAN-snapshot dance:
// WireGuardKit thinks it's talking to a normal UDP peer, the kernel routes
// 127.0.0.1 over loopback, and the Hysteria goroutine handles QUIC.

import Foundation
import Hysteria

/// Thin Swift wrapper around the gomobile-bound `HysHysbindClient`. Owned by
/// PacketTunnelProvider for the lifetime of a Stealth-mode session.
final class HysteriaTransport {

    private var client: HysHysbindClient?

    /// Local UDP endpoint set after `start` succeeds, e.g. "127.0.0.1:54321".
    /// PacketTunnelProvider rewrites the WG peer endpoint to this value.
    private(set) var localEndpoint: String?

    /// Open a Hysteria 2 connection and the local UDP forwarder.
    ///
    /// - Parameters:
    ///   - server:    Hysteria server FQDN (also used as TLS SNI).
    ///   - port:      Hysteria UDP port (443 fleet default, 8444 pdx-02 canary).
    ///   - auth:      Sigil bearer token. Validated server-side via
    ///                `/internal/hysteria/auth` HTTP callback.
    ///   - wgRemote:  Address Hysteria forwards to on the server side. We use
    ///                "127.0.0.1:51820" because every node co-locates wg0
    ///                with hysteria-server.
    /// - Returns: the local listen address ("127.0.0.1:NNNNN").
    /// - Throws: any error surfaced by the Go binding (DNS resolve, TLS
    ///           handshake, auth deny — all rolled up as NSError).
    func start(server: String, port: Int, auth: String, sni: String, wgRemote: String) throws -> String {
        guard let c = HysHysbindNewClient() else {
            throw NSError(domain: "HysteriaTransport", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "HysHysbindNewClient returned nil"])
        }
        // gomobile-generated Swift signature is non-throwing because the Go
        // shim's `Start` returns (string, error) with both nonnull on success
        // — the Objective-C bridging rule for `func foo(...) throws` requires
        // the success-return to be nullable. So we use the explicit
        // NSErrorPointer pattern and re-throw.
        var err: NSError?
        let local = c.start(server,
                            serverPort: port,
                            auth: auth,
                            sni: sni,
                            insecureSkipVerify: false,
                            wgRemote: wgRemote,
                            error: &err)
        if let err = err { throw err }
        client = c
        localEndpoint = local
        return local
    }

    /// Tear down the local listener and close the Hysteria connection.
    /// Idempotent — safe to call after a failed start or twice on shutdown.
    func stop() {
        if let c = client {
            _ = c.stop()
            // Stop errors are logged but don't bubble — teardown is best-effort.
        }
        client = nil
        localEndpoint = nil
    }

    /// Cumulative bytes the iOS side has sent into the tunnel since `start`.
    var txBytes: Int64 { client?.txBytes() ?? 0 }

    /// Cumulative bytes received from the server since `start`.
    var rxBytes: Int64 { client?.rxBytes() ?? 0 }

    /// True between successful `start` and `stop`. Does NOT probe the
    /// underlying QUIC session — use a tx/rx delta to spot a dead pipe.
    var isConnected: Bool { client?.connected() ?? false }
}
