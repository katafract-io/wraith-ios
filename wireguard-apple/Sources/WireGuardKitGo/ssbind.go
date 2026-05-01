// SPDX-License-Identifier: MIT
//
// ssbind.go — Stealth-mode Bind for AmneziaWG / WireGuard.
//
// Phase A (this file, no-op passthrough): an `ssBind` that delegates every
// method to the inner `conn.StdNetBind`. Its only purpose is to prove the
// device-construction substitution at api-apple.go:wgTurnOnStealthPassthrough
// works end-to-end on a real iOS device — the Bind boundary is exercised, the
// cgo wiring round-trips, and the WireGuard handshake completes.
//
// Phase B will replace the inner UDP socket I/O with SS-2022 framing (UDP
// relay mode) so each WG datagram is wrapped in an SS-UDP frame to ssservice.
// Phase C will add the TCP+TLS+WS framing for Stealth-Strict.

package main

import (
	"github.com/amnezia-vpn/amneziawg-go/conn"
)

// ssBind wraps a conn.Bind. In Phase A all methods delegate; in Phase B the
// Send/Receive paths add SS framing.
type ssBind struct {
	inner conn.Bind
}

// newSSBindPassthrough returns an ssBind with no SS framing — just a real
// stdlib UDP socket. Used in Phase A to validate substitution.
func newSSBindPassthrough() *ssBind {
	return &ssBind{inner: conn.NewStdNetBind()}
}

// Open forwards to the inner bind. WG calls this once at startup.
func (b *ssBind) Open(port uint16) ([]conn.ReceiveFunc, uint16, error) {
	return b.inner.Open(port)
}

// Close forwards to the inner bind. WG calls this once at shutdown.
func (b *ssBind) Close() error {
	return b.inner.Close()
}

// SetMark forwards to the inner bind. iOS doesn't use socket marks but the
// Bind interface requires it. StdNetBind no-ops on Apple platforms.
func (b *ssBind) SetMark(mark uint32) error {
	return b.inner.SetMark(mark)
}

// Send forwards each WG datagram batch to the inner bind. Phase B will wrap
// each `bufs[i]` in an SS-UDP frame before forwarding to the configured
// ssservice relay endpoint instead of the original WG endpoint.
func (b *ssBind) Send(bufs [][]byte, ep conn.Endpoint) error {
	return b.inner.Send(bufs, ep)
}

// ParseEndpoint forwards to the inner bind. WG calls this when applying the
// peer's `Endpoint = host:port` from the config string. Phase B will parse a
// composite endpoint of `relayHost:relayPort/realDst:realPort` so the Bind
// knows where to actually send (relay) and what target address to embed in
// the SS frame's address header (real WG dst).
func (b *ssBind) ParseEndpoint(s string) (conn.Endpoint, error) {
	return b.inner.ParseEndpoint(s)
}

// BatchSize forwards. StdNetBind on Apple returns 1 today; we keep it simple
// in Phase A and revisit batching in Phase B once framing is in place.
func (b *ssBind) BatchSize() int {
	return b.inner.BatchSize()
}
