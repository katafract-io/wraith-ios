/* SPDX-License-Identifier: MIT
 *
 * Copyright (C) 2018-2023 WireGuard LLC. All Rights Reserved.
 * AmneziaWG modifications: Copyright (C) 2023 Amnezia VPN Contributors.
 */

#ifndef WIREGUARD_H
#define WIREGUARD_H

#include <sys/types.h>
#include <stdint.h>
#include <stdbool.h>

typedef void(*logger_fn_t)(void *context, int level, const char *msg);
extern void wgSetLogger(void *context, logger_fn_t logger_fn);
extern int wgTurnOn(const char *settings, int32_t tun_fd);
/* Stealth-mode passthrough (Phase A): substitution-point validation —
 * boots WG with the custom ssBind that today just delegates to StdNetBind.
 * Phase B replaces the inner I/O with SS-2022 UDP-relay framing (see below). */
extern int wgTurnOnStealthPassthrough(const char *settings, int32_t tun_fd);
/* Stealth-mode UDP relay (Phase B): real SS-2022 framing.
 * combined_psk = "SERVER_PSK:USER_PSK" (both base64-encoded 32-byte keys,
 * matching the shadowsocks_fallback.password from the provision API response).
 * relay_host/relay_port — ssservice endpoint (e.g. "64.176.215.96" / 8443).
 * target_ip/target_port — WireGuard node endpoint (e.g. "64.176.215.96" / 51820).
 */
extern int wgTurnOnStealthUDP(const char *settings, int32_t tun_fd,
                              const char *combined_psk,
                              const char *relay_host, int32_t relay_port,
                              const char *target_ip, int32_t target_port);
extern void wgTurnOff(int handle);
extern int64_t wgSetConfig(int handle, const char *settings);
extern char *wgGetConfig(int handle);
extern void wgBumpSockets(int handle);
extern void wgDisableSomeRoamingForBrokenMobileSemantics(int handle);
extern const char *wgVersion();

typedef void (*libxray_sockcallback)(uintptr_t fd, void* ctx);
extern char *LibXrayCutGeoData(const char *datDir, const char *dstDir, const char *cutCodePath);
extern char *LibXrayLoadGeoData(const char *datDir, const char *name, const char *geoType);
extern char *LibXrayPing(const char *datDir, const char *configPath, int timeout, const char *url, const char *proxy);
extern char *LibXrayQueryStats(const char *server, const char *dir);
extern char *LibXrayCustomUUID(const char *text);
extern char *LibXrayTestXray(const char *datDir, const char *configPath);
extern char *LibXrayRunXray(const char *datDir, const char *configPath, int64_t maxMemory);
extern char *LibXrayStopXray();
extern char *LibXrayXrayVersion();
extern char* LibXraySetSockCallback(libxray_sockcallback cb, void* ctx);

#endif
