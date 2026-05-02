// SPDX-License-Identifier: MIT
//
// ssbind.go — Stealth-mode Bind for WireGuard on iOS/macOS.
//
// newSSBindPassthrough returns a passthrough conn.Bind backed by the
// standard stdlib UDP stack. It is used by wgTurnOnStealthPassthrough to
// validate the Bind-substitution boundary without adding any SS framing.

package main

import (
	"github.com/amnezia-vpn/amneziawg-go/conn"
)

// newSSBindPassthrough returns the standard network bind unchanged.
// This is Phase A of the Stealth transport: proves the device-construction
// substitution point works end-to-end on a real device before Phase B
// layers SS-2022 UDP framing on top.
func newSSBindPassthrough() conn.Bind {
	return conn.NewStdNetBind()
}
