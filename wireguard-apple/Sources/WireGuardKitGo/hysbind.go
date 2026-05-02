// SPDX-License-Identifier: MIT
//
// hysbind.go — Hysteria 2 conn.Bind for AmneziaWG on iOS/macOS.
//
// Replaces the previous gomobile-bound Hysteria.xcframework path. Living
// inside the same Go module as wireguard-go means there is exactly one Go
// runtime in the appex binary, which avoids the dual-runtime crash that
// killed builds 1505–1519.
//
// Architecture (Pattern A — direct Bind, no loopback forwarder):
//
//   1. wgTurnOnHysteria(...) constructs a *hysteriaBind, hands it to
//      device.NewDevice as the conn.Bind.
//   2. WG sends every outbound datagram via hysteriaBind.Send → the bind
//      forwards each datagram over the Hysteria 2 QUIC session (UDP relay
//      mode) to the configured target ("127.0.0.1:51820" on the server,
//      since every WG node co-locates wg0 with hysteria-server).
//   3. A goroutine reads HyUDPConn.Receive() and feeds each reply into a
//      buffered channel; the conn.ReceiveFunc returned from Open drains
//      the channel into AWG's batched receive buffers.

package main

import (
	"errors"
	"fmt"
	"net"
	"net/netip"
	"sync"
	"sync/atomic"
	"time"

	"github.com/amnezia-vpn/amneziawg-go/conn"
	hyclient "github.com/apernet/hysteria/core/v2/client"
)

// hysRecvBufSize bounds the per-bind receive channel. WG itself blocks
// on reads when this is full, so we just size for ~64 KiB of in-flight
// datagrams which matches WG's own internal queues.
const hysRecvBufSize = 64

type hysRecv struct {
	data []byte
}

// hysteriaBind implements conn.Bind. One per active VPN session.
//
// All exported state is read after Open completes; we do not support
// concurrent Open/Close cycles — the Apple PacketTunnelProvider lifecycle
// guarantees exactly one Open before each Close.
type hysteriaBind struct {
	// Hysteria session
	client    hyclient.Client
	udpConn   hyclient.HyUDPConn
	target    string // "host:port" — the WG server listener address
	endpoint  *hysEndpoint

	// Receive plumbing
	recvCh   chan hysRecv
	recvOnce sync.Once
	closed   atomic.Bool
	wg       sync.WaitGroup
}

// newHysteriaBind dials the Hysteria 2 server, opens a UDP-relay session,
// and returns a conn.Bind whose Send/Receive proxy through it.
//
// server/serverPort — Hysteria 2 server (UDP/443 fleet default, 8444 pdx-02).
// auth              — Sigil bearer token; validated server-side via /internal/hysteria/auth.
// sni               — TLS SNI; usually equals server FQDN.
// wgRemote          — "host:port" the server forwards to (we always send
//                     "127.0.0.1:51820" since wg0 is co-located).
func newHysteriaBind(server string, serverPort uint16, auth, sni, wgRemote string) (*hysteriaBind, error) {
	serverAddr, err := net.ResolveUDPAddr("udp", net.JoinHostPort(server, fmt.Sprintf("%d", serverPort)))
	if err != nil {
		return nil, fmt.Errorf("hysbind: resolve %s: %w", server, err)
	}

	cfg := &hyclient.Config{
		ServerAddr: serverAddr,
		Auth:       auth,
		TLSConfig: hyclient.TLSConfig{
			ServerName:         sni,
			InsecureSkipVerify: false,
			RootCAs:            nil, // use system roots; LE certs on each node
		},
	}

	c, _, err := hyclient.NewClient(cfg)
	if err != nil {
		return nil, fmt.Errorf("hysbind: NewClient: %w", err)
	}

	udpConn, err := c.UDP()
	if err != nil {
		_ = c.Close()
		return nil, fmt.Errorf("hysbind: c.UDP(): %w", err)
	}

	b := &hysteriaBind{
		client:   c,
		udpConn:  udpConn,
		target:   wgRemote,
		recvCh:   make(chan hysRecv, hysRecvBufSize),
		endpoint: &hysEndpoint{raw: wgRemote},
	}
	return b, nil
}

// Open is called by AmneziaWG once when the device starts. We start the
// goroutine that pumps incoming datagrams from Hysteria into recvCh.
//
// The "port" argument is irrelevant to us (we never bind a local UDP
// socket); we still echo it back for API compliance. AWG only uses the
// returned port for its internal "actual port" book-keeping.
func (b *hysteriaBind) Open(port uint16) ([]conn.ReceiveFunc, uint16, error) {
	if b.closed.Load() {
		return nil, 0, errors.New("hysbind: bind closed")
	}

	b.recvOnce.Do(func() {
		b.wg.Add(1)
		go b.recvLoop()
	})

	return []conn.ReceiveFunc{b.makeReceiveFunc()}, port, nil
}

// Close tears down the Hysteria session. Idempotent.
func (b *hysteriaBind) Close() error {
	if !b.closed.CompareAndSwap(false, true) {
		return nil
	}
	// Closing udpConn unblocks recvLoop's Receive call.
	if b.udpConn != nil {
		_ = b.udpConn.Close()
	}
	if b.client != nil {
		_ = b.client.Close()
	}
	// Drain recvCh quickly so nothing leaks. recvLoop will exit on its own.
	go func() {
		for range b.recvCh {
		}
	}()
	close(b.recvCh)
	b.wg.Wait()
	return nil
}

// SetMark is meaningless on Apple platforms — wireguard-go on iOS/macOS
// never sets fwmark. Match ssBind's behavior.
func (b *hysteriaBind) SetMark(mark uint32) error { return nil }

// Send wraps each WG datagram and ships it through the Hysteria QUIC
// session to the server's WG listener.
func (b *hysteriaBind) Send(bufs [][]byte, ep conn.Endpoint) error {
	if b.closed.Load() {
		return net.ErrClosed
	}
	for _, buf := range bufs {
		if err := b.udpConn.Send(buf, b.target); err != nil {
			return fmt.Errorf("hysbind: Send: %w", err)
		}
	}
	return nil
}

// ParseEndpoint always returns the hard-coded relay endpoint — every
// outbound WG datagram is routed through Hysteria to the same target,
// regardless of what the WG settings string asks for.
func (b *hysteriaBind) ParseEndpoint(s string) (conn.Endpoint, error) {
	return b.endpoint, nil
}

// BatchSize: we never batch on the client side (Hysteria UDP relay is
// per-datagram), so 1 keeps WG's batching loop from over-allocating.
func (b *hysteriaBind) BatchSize() int { return 1 }

// GetOffloadInfo is an AWG-only diagnostic surface. Used by the Swift
// side via `wgGetConfig` to log "we're in Hysteria mode" plumbing.
func (b *hysteriaBind) GetOffloadInfo() string { return "hysteriaBind(quic-udp-relay)" }

// recvLoop is the only goroutine pulling from the Hysteria UDP session.
// It exits when Close() shuts udpConn — Receive returns an error and we
// drop out.
func (b *hysteriaBind) recvLoop() {
	defer b.wg.Done()
	for {
		data, _, err := b.udpConn.Receive()
		if err != nil {
			return
		}
		// Copy because Hysteria's internal buffer may be reused on next Receive.
		cp := make([]byte, len(data))
		copy(cp, data)
		select {
		case b.recvCh <- hysRecv{data: cp}:
		default:
			// Channel full → drop. Same back-pressure model as a real UDP
			// socket overflowing its kernel rx queue, which WG handles.
		}
	}
}

// makeReceiveFunc returns the conn.ReceiveFunc that AWG calls in a tight
// loop. We block (with a short timeout to allow shutdown) for the next
// datagram, then copy it into the caller's buffer.
func (b *hysteriaBind) makeReceiveFunc() conn.ReceiveFunc {
	return func(packets [][]byte, sizes []int, eps []conn.Endpoint) (int, error) {
		// Honor BatchSize=1: read one packet per call.
		select {
		case msg, ok := <-b.recvCh:
			if !ok {
				return 0, net.ErrClosed
			}
			n := copy(packets[0], msg.data)
			sizes[0] = n
			eps[0] = b.endpoint
			return 1, nil
		case <-time.After(250 * time.Millisecond):
			// Periodic wake so AWG can check device-stop signals.
			return 0, nil
		}
	}
}

// --------------------------------------------------------------------------
// hysEndpoint — fake conn.Endpoint mirroring ssEndpoint pattern
// --------------------------------------------------------------------------

type hysEndpoint struct {
	raw string
}

func (e *hysEndpoint) ClearSrc()           {}
func (e *hysEndpoint) SrcToString() string { return "" }
func (e *hysEndpoint) DstToString() string { return e.raw }
func (e *hysEndpoint) DstToBytes() []byte  { return []byte(e.raw) }
func (e *hysEndpoint) DstIP() netip.Addr   { return netip.Addr{} }
func (e *hysEndpoint) SrcIP() netip.Addr   { return netip.Addr{} }
