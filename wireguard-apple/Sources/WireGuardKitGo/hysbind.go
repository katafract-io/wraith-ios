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
	"fmt"
	"net"
	"net/netip"
	"os"
	"sync"
	"sync/atomic"
	"time"

	"golang.zx2c4.com/wireguard/conn"
	hyclient "github.com/apernet/hysteria/core/v2/client"
)

// hysDebug routes through CLogger (defined in api-apple.go) so the message
// crosses C→Swift via the wgSetLogger callback. Swift's PacketTunnelProvider
// log handler grew a special-case for "[hysbind]" lines that mirrors them
// into TunnelLog.ne so they appear in the exported in-app debug log.
//
// Disabled by setting WRAITH_HYS_DEBUG=0; default-on while bringing up
// Pattern A. CLogger(0) = verbose level (matches Verbosef).
var hysDebugOn = os.Getenv("WRAITH_HYS_DEBUG") != "0"

func hysDebug(format string, args ...interface{}) {
	if hysDebugOn {
		CLogger(0).Printf("[hysbind] "+format, args...)
	}
}

// hysRecvBufSize bounds the per-bind receive channel. WG itself blocks
// on reads when this is full, so we just size for ~64 KiB of in-flight
// datagrams which matches WG's own internal queues.
const hysRecvBufSize = 64

type hysRecv struct {
	data []byte
}

// hysteriaBind implements conn.Bind. One per active VPN session.
//
// Lifecycle quirk that drove a real bug (build 1525-1528): wireguard-go's
// device.BindUpdate ALWAYS calls bind.Close() then bind.Open() — even on
// the very first Up(), where the bind was just installed by NewDevice.
// Earlier revisions of this file did the QUIC dial in newHysteriaBind and
// treated Close as terminal (one-shot atomic.Bool flip), so by the time WG
// got around to calling Open, our bind was already torn down and Open
// returned `bind closed`. Net effect: Send was never wired up, server saw
// connect-then-tx:0-disconnect, no inner WG handshake ever flowed.
//
// Fix: defer the dial to Open. newHysteriaBind only stashes config; Open
// dials and starts the receive pump; Close tears down and leaves the bind
// in a state where another Open (the second of WG's close-before-open
// dance, OR a subsequent BindUpdate triggered by listen_port change) will
// re-dial cleanly.
type hysteriaBind struct {
	// Immutable config (set in newHysteriaBind)
	cfg      *hyclient.Config // hysteria client config (server, auth, TLS)
	sni      string           // for log lines
	target   string           // "host:port" — the WG server listener
	endpoint *hysEndpoint     // hardcoded relay endpoint

	// Live session — guarded by mu, all reset by Open/Close
	mu      sync.Mutex
	client  hyclient.Client
	udpConn hyclient.HyUDPConn
	recvCh  chan hysRecv
	wg      sync.WaitGroup
	openGen uint64 // bumped each successful Open so log lines distinguish sessions

	// Deferred-close timer. iOS NEPathMonitor fires pathUpdate freely
	// (interface flap, DNS reload, screen lock, app foreground) →
	// WireGuardKit calls wgBumpSockets → BindUpdate (Close+Open back-to-back).
	// Each cycle was tearing down our QUIC session and re-handshaking.
	// Defer the actual teardown by 2s; if Open arrives within that window,
	// cancel the timer and reuse the live session.
	pendingClose *time.Timer

	// Diagnostic counters (atomic only)
	sendCount uint64
	sendErr   uint64
	recvCount uint64
	recvErr   uint64
}

// newHysteriaBind builds a conn.Bind whose Open will dial Hysteria 2 on
// first call. We deliberately do NOT dial here — see the lifecycle quirk
// in the type doc above.
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

	hysDebug("newHysteriaBind: cfg server=%s sni=%s wgRemote=%s (dial deferred to Open)",
		serverAddr, sni, wgRemote)

	return &hysteriaBind{
		cfg:      cfg,
		sni:      sni,
		target:   wgRemote,
		endpoint: &hysEndpoint{raw: wgRemote},
	}, nil
}

// Open dials Hysteria 2 (if needed) and starts the receive pump. Idempotent
// from WG's perspective: if called while already open, it just returns the
// existing ReceiveFunc set. After Close, a subsequent Open re-dials cleanly.
//
// The "port" argument is irrelevant to us (we never bind a local UDP socket);
// we echo it back for API compliance. WG only uses the returned port for its
// internal "actual port" bookkeeping.
func (b *hysteriaBind) Open(port uint16) ([]conn.ReceiveFunc, uint16, error) {
	b.mu.Lock()
	defer b.mu.Unlock()

	// Cancel any in-flight deferred close — we're being reopened immediately,
	// so reuse the live session and skip a full QUIC handshake.
	if b.pendingClose != nil {
		stopped := b.pendingClose.Stop()
		b.pendingClose = nil
		if stopped && b.client != nil {
			hysDebug("Open(port=%d): cancelled deferred close — reusing live session gen=%d", port, b.openGen)
			return []conn.ReceiveFunc{makeReceiveFuncFor(b.recvCh, b.endpoint)}, port, nil
		}
		// Timer already fired (actualClose ran) — fall through to fresh dial.
	}

	if b.client != nil {
		hysDebug("Open(port=%d): already open (gen=%d)", port, b.openGen)
		return []conn.ReceiveFunc{makeReceiveFuncFor(b.recvCh, b.endpoint)}, port, nil
	}

	hysDebug("Open(port=%d): dialing %s sni=%s target=%s", port, b.cfg.ServerAddr, b.sni, b.target)
	c, info, err := hyclient.NewClient(b.cfg)
	if err != nil {
		hysDebug("Open: NewClient err=%v", err)
		return nil, 0, fmt.Errorf("hysbind: NewClient: %w", err)
	}
	hysDebug("Open: NewClient ok info=%+v", info)

	udpConn, err := c.UDP()
	if err != nil {
		hysDebug("Open: c.UDP() err=%v — closing client", err)
		_ = c.Close()
		return nil, 0, fmt.Errorf("hysbind: c.UDP(): %w", err)
	}
	hysDebug("Open: c.UDP() ok — recvLoop starting")

	recvCh := make(chan hysRecv, hysRecvBufSize)
	b.client = c
	b.udpConn = udpConn
	b.recvCh = recvCh
	b.openGen++
	gen := b.openGen
	b.wg.Add(1)
	// recvLoop + makeReceiveFunc must NOT re-acquire b.mu — Open still holds
	// it via the defer above, and sync.Mutex is non-reentrant. Pass the
	// captured udpConn/recvCh/endpoint by value instead. (build 1529 deadlocked
	// here: Open held the lock, makeReceiveFunc tried to take it, dev.Up()
	// hung, NE stayed in "connecting" forever.)
	go b.recvLoop(gen, udpConn, recvCh)

	return []conn.ReceiveFunc{makeReceiveFuncFor(recvCh, b.endpoint)}, port, nil
}

// Close defers the actual teardown by 2 seconds. iOS NEPathMonitor fires
// pathUpdate frequently (interface flap, DNS reload, screen lock, app
// foreground) and each one triggers wgBumpSockets → BindUpdate (Close+Open
// back-to-back). Without deferral every cycle would re-handshake the QUIC
// session — expensive and disruptive. With deferral, an Open within 2s
// cancels the timer and reuses the live session.
//
// If a real shutdown happens (wgTurnOff), no Open follows and the timer
// fires normally to actualClose().
func (b *hysteriaBind) Close() error {
	b.mu.Lock()
	defer b.mu.Unlock()

	if b.client == nil {
		hysDebug("Close: no live session")
		return nil
	}

	if b.pendingClose != nil {
		// Already deferred; let the existing timer ride.
		return nil
	}

	hysDebug("Close: deferring teardown of gen=%d for 2s (absorb iOS path-update flapping)", b.openGen)
	b.pendingClose = time.AfterFunc(2*time.Second, b.actualClose)
	return nil
}

// actualClose performs the real teardown. Called by the deferred-close
// timer (Close() arms it) or by recvLoop when it gives up reconnecting.
func (b *hysteriaBind) actualClose() {
	b.mu.Lock()
	if b.pendingClose == nil && b.client == nil {
		// Already closed by a parallel actualClose; nothing to do.
		b.mu.Unlock()
		return
	}
	b.pendingClose = nil
	gen := b.openGen
	udpConn := b.udpConn
	client := b.client
	recvCh := b.recvCh
	b.udpConn = nil
	b.client = nil
	b.recvCh = nil
	b.mu.Unlock()

	hysDebug("Close: actual teardown gen=%d (sendCount=%d sendErr=%d recvCount=%d recvErr=%d)",
		gen, atomic.LoadUint64(&b.sendCount), atomic.LoadUint64(&b.sendErr),
		atomic.LoadUint64(&b.recvCount), atomic.LoadUint64(&b.recvErr))

	if udpConn != nil {
		_ = udpConn.Close() // unblocks recvLoop's Receive
	}
	if client != nil {
		_ = client.Close()
	}
	if recvCh != nil {
		// Drain in background so anything still queued doesn't pin memory.
		go func(ch chan hysRecv) {
			for range ch {
			}
		}(recvCh)
		close(recvCh)
	}
	b.wg.Wait()
}

// SetMark is meaningless on Apple platforms — wireguard-go on iOS/macOS
// never sets fwmark. Match ssBind's behavior.
func (b *hysteriaBind) SetMark(mark uint32) error { return nil }

// Send wraps each WG datagram and ships it through the Hysteria QUIC
// session to the server's WG listener.
//
// Counts every send + every error for diagnostic. The first 5 calls and
// every error are logged verbatim; after that we log only a per-1000 tick.
func (b *hysteriaBind) Send(bufs [][]byte, ep conn.Endpoint) error {
	b.mu.Lock()
	udpConn := b.udpConn
	target := b.target
	b.mu.Unlock()

	if udpConn == nil {
		hysDebug("Send: bind not open — refusing %d bufs", len(bufs))
		return net.ErrClosed
	}
	for i, buf := range bufs {
		n := atomic.AddUint64(&b.sendCount, 1)
		if n <= 5 || n%1000 == 0 {
			hysDebug("Send #%d (batch idx=%d/%d) len=%d target=%s", n, i, len(bufs), len(buf), target)
		}
		if err := udpConn.Send(buf, target); err != nil {
			atomic.AddUint64(&b.sendErr, 1)
			hysDebug("Send #%d ERR len=%d target=%s err=%v", n, len(buf), target, err)
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

// recvLoop is the only goroutine pulling from the Hysteria UDP session.
// It captures the udpConn + recvCh from the bind under lock at start so a
// concurrent Close() can swap b.udpConn/b.recvCh to nil without racing
// (the captured refs stay valid until our Receive errors out, which Close
// triggers by closing udpConn).
//
// `gen` is the openGen value at the time this goroutine was started — only
// used in log lines so that close-then-reopen cycles can be told apart.
func (b *hysteriaBind) recvLoop(gen uint64, udpConn hyclient.HyUDPConn, recvCh chan hysRecv) {
	defer b.wg.Done()
	hysDebug("recvLoop[gen=%d]: started", gen)
	for {
		data, _, err := udpConn.Receive()
		if err != nil {
			atomic.AddUint64(&b.recvErr, 1)
			hysDebug("recvLoop[gen=%d]: udpConn.Receive err=%v — exiting (recvCount=%d sendCount=%d sendErr=%d)",
				gen, err, atomic.LoadUint64(&b.recvCount),
				atomic.LoadUint64(&b.sendCount), atomic.LoadUint64(&b.sendErr))
			return
		}
		n := atomic.AddUint64(&b.recvCount, 1)
		if n <= 5 || n%1000 == 0 {
			hysDebug("recvLoop[gen=%d]: Receive #%d len=%d", gen, n, len(data))
		}
		// Copy because Hysteria's internal buffer may be reused on next Receive.
		cp := make([]byte, len(data))
		copy(cp, data)
		select {
		case recvCh <- hysRecv{data: cp}:
		default:
			// Channel full → drop. Same back-pressure model as a real UDP
			// socket overflowing its kernel rx queue, which WG handles.
		}
	}
}

// makeReceiveFuncFor returns the conn.ReceiveFunc that WG calls in a tight
// loop. recvCh + endpoint are passed by the caller (Open, which holds b.mu
// at construction time and already has these values in scope) — we deliberately
// do NOT re-acquire b.mu here. A subsequent Close()→Open() cycle installs a
// new recvCh + ReceiveFunc; this one will return net.ErrClosed once the
// captured recvCh is closed and WG will request a new ReceiveFunc set.
func makeReceiveFuncFor(recvCh chan hysRecv, endpoint *hysEndpoint) conn.ReceiveFunc {
	return func(packets [][]byte, sizes []int, eps []conn.Endpoint) (int, error) {
		// Honor BatchSize=1: read one packet per call.
		select {
		case msg, ok := <-recvCh:
			if !ok {
				return 0, net.ErrClosed
			}
			n := copy(packets[0], msg.data)
			sizes[0] = n
			eps[0] = endpoint
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
