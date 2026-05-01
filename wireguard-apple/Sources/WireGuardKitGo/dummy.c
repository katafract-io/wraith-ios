// dummy.c — WireGuardKitGo SPM target shim.
//
// The WireGuardKitGo target links against the prebuilt libwg-go.a (built from
// api-apple.go + ssbind.go via `make ARCHS=arm64 PLATFORM_NAME=iphoneos`).
// SPM requires at least one C/C++ source file in any target that exposes a
// public headers path; this file satisfies that requirement.
//
// Phase A compat stub:
// wgTurnOnStealthPassthrough is exported by api-apple.go and compiled into
// libwg-go.a by the CI "Build WireGuardKitGo" step. The prebuilt library
// checked into git may be stale (it predates the Stealth Bind changes), so we
// provide a __attribute__((weak)) fallback here. The linker uses this stub
// when the symbol is absent from libwg-go.a; when the Go-rebuilt library is
// present (as it will be after CI regenerates it), the strong Go symbol wins
// automatically because weak symbols lose to strong ones at link time.
//
// Phase A semantics: ssBind is a pure passthrough to conn.NewStdNetBind() so
// wgTurnOnStealthPassthrough(settings, fd) == wgTurnOn(settings, fd). The
// stub is therefore correct for Phase A even when it delegates to wgTurnOn.
// Phase B (actual SS framing) will ship with a fully rebuilt libwg-go.a and
// the stub can be removed.

#include "wireguard.h"

__attribute__((weak))
int wgTurnOnStealthPassthrough(const char *settings, int32_t tun_fd) {
    return wgTurnOn(settings, tun_fd);
}
