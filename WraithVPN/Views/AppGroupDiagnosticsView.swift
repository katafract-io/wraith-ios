// AppGroupDiagnosticsView.swift
// WraithVPN
//
// Runtime App Group entitlement check. Surfaces connection state and
// shared UserDefaults values — catches provisioning profile mismatches
// that source-level audits can't detect.

import SwiftUI

struct AppGroupDiagnosticsView: View {
    private let groupID = "group.com.katafract.enclave"
    private let wraithGroupID = "group.com.katafract.wraith"

    private var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)
    }
    private var suite: UserDefaults? { UserDefaults(suiteName: groupID) }
    private var plan: String? { suite?.string(forKey: "enclave.sigil.plan") }
    private var hasToken: Bool { suite?.string(forKey: "enclave.sigil.token") != nil }

    private var wraithSuite: UserDefaults? { UserDefaults(suiteName: wraithGroupID) }
    @State private var phaseAStealthPassthrough: Bool = UserDefaults(suiteName: "group.com.katafract.wraith")?.bool(forKey: "phaseAStealthPassthrough") ?? false

    var body: some View {
        Form {
            Section("Shared App Group") {
                LabeledContent("Group ID") { Text(groupID).font(.caption.monospaced()) }
                LabeledContent("Entitlement") {
                    Text(containerURL == nil ? "NOT CONNECTED" : "Connected")
                        .foregroundStyle(containerURL == nil ? .red : .green)
                        .font(.caption.weight(.semibold))
                }
                if let url = containerURL {
                    LabeledContent("Container") {
                        Text(url.lastPathComponent).font(.caption.monospaced()).lineLimit(1)
                    }
                }
            }

            Section("Sovereign State (from shared UserDefaults)") {
                LabeledContent("Plan") {
                    Text(plan ?? "—").font(.caption.monospaced())
                }
                LabeledContent("Token") {
                    Text(hasToken ? "Present" : "None")
                        .foregroundStyle(hasToken ? .green : .secondary)
                        .font(.caption.weight(.semibold))
                }
            }

            Section {
                Text("If Entitlement shows 'NOT CONNECTED', the app binary was signed without the App Group. The provisioning profile needs to be regenerated in Apple Developer Portal and the app re-archived — re-checking the capability alone won't fix it.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Stealth (Phase A — debug)") {
                Toggle("Use custom Bind on next connect", isOn: $phaseAStealthPassthrough)
                    .onChange(of: phaseAStealthPassthrough) { _, newValue in
                        wraithSuite?.set(newValue, forKey: "phaseAStealthPassthrough")
                    }
                Text("Phase A substitutes the WireGuard backend's UDP socket layer with the Stealth-mode `ssBind`. Today the Bind delegates to the standard layer (no SS framing yet) — this toggle only proves the substitution point works on a real device. Disconnect and reconnect after toggling.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("App Group Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        AppGroupDiagnosticsView()
    }
}
