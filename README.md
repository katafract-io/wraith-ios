# WraithVPN — iOS & macOS Client

Privacy-focused WireGuard VPN client from [Katafract](https://katafract.com). Targets iOS 17+ and macOS 14+ (Mac Catalyst).

Includes **Haven DNS** — DNS-level ad, tracker, and malware blocking on every WraithGate node — as a standalone free tier with optional upgrade to full VPN routing.

---

## Opening in Xcode

```
open WraithVPN.xcodeproj
```

Requires Xcode 15.4 or later.

---

## Project structure

```
WraithVPN/
├── WraithVPN.xcodeproj/             Xcode project (two targets: app + tunnel)
│
├── WraithVPN/                       Main app target
│   ├── WraithVPNApp.swift           @main entry; creates ObservableObject singletons
│   ├── Models/
│   │   └── Models.swift             API models, VPNStatus, SubscriptionInfo, DnsPreferences
│   ├── Managers/
│   │   ├── APIClient.swift          Typed async/await HTTP client (all endpoints)
│   │   ├── WireGuardManager.swift   Keypair gen, peer provisioning, NetworkExtension toggle
│   │   ├── StoreKitManager.swift    StoreKit 2 purchase + token exchange flow
│   │   ├── ServerListManager.swift  Server list fetch + concurrent TCP latency probes
│   │   └── HavenDNSManager.swift    Haven DNS enable/disable + preferences sync
│   ├── Helpers/
│   │   ├── KeychainHelper.swift     Generic Keychain wrapper
│   │   └── DesignSystem.swift       Colours, gradients, typography, spacing tokens
│   ├── Views/
│   │   ├── ContentView.swift        Root: onboarding gate → paywall gate → main app
│   │   ├── OnboardingView.swift     3-screen carousel (first launch)
│   │   ├── ConnectView.swift        Main screen: animated ring button, status, server picker
│   │   ├── ServerPickerView.swift   Server list, latency badges, load bars, search/sort
│   │   ├── HavenDNSSettingsView.swift  Protection level + blocked services config
│   │   ├── SettingsView.swift       Plan info, connection details, Haven DNS, manage sub
│   │   ├── PaywallView.swift        StoreKit 2 paywall: monthly vs annual + free tier
│   │   └── TokenActivationSheet.swift  Manual token entry for non-App Store purchases
│   ├── Assets.xcassets/
│   ├── Info.plist
│   └── WraithVPN.entitlements
│
└── WireGuardTunnel/                 Network Extension target (out-of-process tunnel)
    ├── PacketTunnelProvider.swift   NEPacketTunnelProvider — receives wgConfig, starts WireGuard
    ├── Info.plist
    └── WireGuardTunnel.entitlements
```

---

## Required Apple entitlements

| Entitlement | Main app | Tunnel ext |
|---|---|---|
| `com.apple.developer.networking.networkextension` → `packet-tunnel-provider` | ✓ | ✓ |
| `com.apple.developer.in-app-payments` (product IDs listed) | ✓ | — |
| `keychain-access-groups` → `com.katafract.wraith` & `.tunnel` | ✓ | ✓ |
| `com.apple.security.application-groups` → `group.com.katafract.wraith` | ✓ | ✓ |

### Setup

1. Register identifiers at [developer.apple.com](https://developer.apple.com/account):
   - `com.katafract.wraith` — Network Extensions, In-App Purchase, App Groups, Keychain Sharing
   - `com.katafract.wraith.tunnel` — Network Extensions, App Groups, Keychain Sharing
2. Create App Group: `group.com.katafract.wraith`
3. Set `DEVELOPMENT_TEAM` in `project.pbxproj`

---

## WireGuardKit dependency

The tunnel extension requires the official WireGuard Swift library:

1. **File → Add Package Dependencies** in Xcode
2. URL: `https://github.com/WireGuard/wireguard-apple`
3. Add **WireGuardKit** to the **WireGuardTunnel** target only
4. Uncomment `import WireGuardKit` and the adapter block in `PacketTunnelProvider.swift`

---

## In-App Purchase products

| Product ID | Type | Price |
|---|---|---|
| `com.katafract.wraith_armor_monthly` | Auto-Renewable Subscription | $4.99/mo |
| `com.katafract.wraith_armor_annual`  | Auto-Renewable Subscription | $39.99/yr |

Both belong to the same Subscription Group (upgrade/downgrade supported). Displayed in-app as **WraithVPN Monthly** and **WraithVPN Annual**.

---

## Subscription tiers

| Tier (backend `plan` value) | In-app label | Features |
|---|---|---|
| Free | Haven DNS Free | Standard DNS blocking, 90-day trial |
| `haven` | Haven DNS | DNS blocking only |
| `vpn_armor` / `veil` | WraithVPN | All WraithGate nodes, manual selection, kill switch |
| `vpn_armor_annual` / `veil_annual` | WraithVPN Annual | Same as above |
| `total` / `total_annual` / `founder` | Founder | All features, no expiry |

---

## Haven DNS

Every WraithGate node runs AdGuard Home on the WireGuard interface. Haven DNS provides:

- DNS-level blocking of ads, trackers, and malware
- Configurable protection levels: NONE, LOW, STANDARD, HIGH (Pro), FAMILY (Pro)
- Per-service blocking (social, gaming, entertainment, gambling, communication)
- Safe browsing + family filter toggles (Pro/Founder only)
- Works independently of VPN — can be enabled without an active tunnel

Configuration is synced via `GET/PUT /v1/dns/preferences` and stored per-token on the backend.

---

## WraithGate nodes

| Region | City | wg0 DNS |
|---|---|---|
| `eu-west` | Frankfurt 🇩🇪 | 10.10.1.1 |
| `eu-north` | Helsinki 🇫🇮 | 10.10.2.1 |
| `ap-southeast` | Singapore 🇸🇬 | 10.10.3.1 |
| `us-central` | Chicago 🇺🇸 | 10.10.4.1 |
| `us-east` | Virginia 🇺🇸 | — |
| `us-west` | Oregon 🇺🇸 | — |

Latency is probed via TCP to port 22 (SSH) on each node. The fastest measured node is auto-selected on launch.

---

## First-run flow

```
Launch
  └─ hasSeenOnboarding == false → OnboardingView (3 screens)
       └─ "Get Started"
            └─ hasPurchased == false → PaywallView
                 ├─ Subscribe → StoreKit 2 → /v1/token/validate/apple → token in Keychain
                 ├─ "Have a token?" → TokenActivationSheet → /v1/token/validate → token in Keychain
                 └─ "Continue with Haven DNS Free" → free tier flag set

Connect (first time)
  └─ WireGuardManager.connectToServer(_:)
       1. ensureKeypair()  — Curve25519 via CryptoKit, stored in Keychain
       2. APIClient.provisionPeer(pubkey:region:label:)  → ProvisionResponse
       3. installProfile(configText:server:)  — NETunnelProviderManager
          - includeAllNetworks = true   (routes all traffic through tunnel)
          - excludeLocalNetworks = true (LAN still reachable)
          - kill switch is always on by design
       4. startTunnel()  → NETunnelProviderSession
       5. PacketTunnelProvider (out-of-process) receives wgConfig, starts WireGuard adapter

Connect (subsequent, same server)
  └─ WireGuardManager.connect()  — startTunnel() on existing profile

Connect (server switch while connected)
  └─ WireGuardManager.connectToServer(_:)
       1. stopVPNTunnel() + 500ms teardown delay
       2. Re-provision to new node
       3. Reinstall profile + startTunnel()
```

---

## Backend API

Base URL: `https://api.katafract.com`

All authenticated endpoints require `Authorization: Bearer <token>`.

| Method | Endpoint | Auth | Description |
|---|---|---|---|
| POST | `/v1/token/validate/apple` | — | Exchange StoreKit JWS for bearer token |
| POST | `/v1/token/validate` | — | Validate a manually-entered token |
| GET | `/v1/token/info` | ✓ | Plan, expiry, peer limit |
| GET | `/v1/nodes` | ✓ | Server list with load scores and endpoints |
| GET | `/v1/nodes/nearest` | ✓ | GeoIP-nearest server |
| POST | `/v1/peers/provision` | ✓ | Create WireGuard peer, returns full wg config |
| DELETE | `/v1/peers/{peer_id}` | ✓ | Revoke a peer |
| GET | `/v1/dns/preferences` | ✓ | Haven DNS settings for this token |
| PUT | `/v1/dns/preferences` | ✓ | Update Haven DNS settings |

---

## Xcode Cloud

Builds are triggered on every push to `main`. The **Deploy** workflow archives and uploads to App Store Connect. The internal TestFlight group receives all builds automatically (`hasAccessToAllBuilds = true`).

Xcode Cloud requires three environment secrets set in the workflow (Environment → Secrets):
`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_CONTENT` — obtain from App Store Connect → Users & Access → Integrations.

---

## macOS

Mac Catalyst is enabled (`SUPPORTS_MACCATALYST = YES`). All source files compile for both platforms without changes. `UIImpactFeedbackGenerator` usage is guarded with `#if canImport(UIKit)`.

---

## Privacy

- Zero-log policy: no traffic, DNS queries, or connection timestamps stored
- No email required — authentication is token-based (App Store or manual)
- WireGuard session keys discarded after every session
- Kill switch always on (`includeAllNetworks = true`)
- Privacy policy: [katafract.com/privacy/wraith](https://katafract.com/privacy/wraith)
