/* SPDX-License-Identifier: MIT
 *
 * stealth-stubs.c — Weak fallback implementations for Phase A/B stealth-mode
 * entry points declared in wireguard.h.
 *
 * These are declared __attribute__((weak)) so that the linker prefers the
 * real Go implementations exported from libwg-go.a (rebuilt by
 * ci_pre_xcodebuild.sh / ship.yml on every CI run).  They are only used
 * when libwg-go.a is stale and does not yet contain wgTurnOnStealthPassthrough
 * or wgTurnOnStealthUDP — for example during the first CI run after these
 * symbols were added but before the runner has rebuilt the static archive.
 *
 * Behaviour: fall back to the standard wgTurnOn path so the tunnel still
 * links and starts (without Stealth framing), rather than failing at link time.
 */

#include "wireguard.h"

__attribute__((weak))
int wgTurnOnStealthPassthrough(const char *settings, int32_t tun_fd) {
    /* Phase A fallback: delegate to standard WireGuard backend.
     * Overridden at link time by the real Go implementation once libwg-go.a
     * is rebuilt with the ssBind passthrough export (wgTurnOnStealthPassthrough
     * in api-apple.go). */
    return wgTurnOn(settings, tun_fd);
}

__attribute__((weak))
int wgTurnOnStealthUDP(const char *settings, int32_t tun_fd,
                       const char *combined_psk,
                       const char *relay_host, int32_t relay_port,
                       const char *target_ip, int32_t target_port) {
    /* Phase B fallback: SS-2022 UDP relay framing is not available in the
     * current libwg-go.a.  Fall back to standard WireGuard so the device
     * still links and can connect (without obfuscation).
     * Overridden at link time once libwg-go.a is rebuilt from api-apple.go. */
    (void)combined_psk;
    (void)relay_host;
    (void)relay_port;
    (void)target_ip;
    (void)target_port;
    return wgTurnOn(settings, tun_fd);
}
