// RegionPickerView.swift
// WraithVPN
//
// Phase F — region-first server picker. User picks a region; server picks the
// best node inside that region (sticky HARD rule: never crosses to another
// region server-side). Node-level control is still available via ServerPickerView
// for power users / diagnostics.

import SwiftUI

struct RegionPickerView: View {

    @EnvironmentObject var vpn: WireGuardManager
    @EnvironmentObject var servers: ServerListManager
    @Environment(\.dismiss) private var dismiss

    @State private var regions: [RegionSummary] = []
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var connecting: String? = nil   // regionId currently being connected
    @State private var drillDownRegion: RegionSummary? = nil

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kfBackground.ignoresSafeArea()

                VStack(spacing: KFSpacing.md) {
                    if isLoading && regions.isEmpty {
                        loadingState
                    } else if let msg = errorMessage, regions.isEmpty {
                        errorState(msg)
                    } else if regions.isEmpty {
                        emptyState
                    } else {
                        regionList
                    }
                }
                .padding(.top, KFSpacing.sm)
            }
            .navigationTitle("Choose Region")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.kfAccentBlue)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    if isLoading {
                        ProgressView().tint(Color.kfAccentBlue)
                    }
                }
            }
            .toolbarBackground(Color.kfBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .preferredColorScheme(.dark)
            .navigationDestination(item: $drillDownRegion) { region in
                regionDrillDown(region: region)
            }
        }
        .task { await loadRegions() }
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: KFSpacing.md) {
            ProgressView().tint(Color.kfAccentBlue)
            Text("Loading regions…")
                .font(KFFont.caption(13))
                .foregroundStyle(Color.kfTextMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: KFSpacing.md) {
            Image(systemName: "globe")
                .font(.system(size: 36))
                .foregroundStyle(Color.kfTextMuted)
            Text("No regions available")
                .font(KFFont.body(15))
                .foregroundStyle(Color.kfTextMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ msg: String) -> some View {
        VStack(spacing: KFSpacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(Color.orange)
            Text(msg)
                .font(KFFont.body(14))
                .foregroundStyle(Color.kfTextMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, KFSpacing.lg)
            Button {
                Task { await loadRegions() }
            } label: {
                Text("Retry").font(KFFont.body(14).weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(Color.kfAccentBlue)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var regionList: some View {
        ScrollView {
            LazyVStack(spacing: KFSpacing.sm) {
                if shouldShowMeasuringIndicator {
                    Text("Measuring latency…")
                        .font(KFFont.caption(12))
                        .foregroundStyle(Color.kfTextMuted)
                        .padding(.top, KFSpacing.sm)
                }
                // Auto row at top
                autoRow
                ForEach(sortedRegions) { region in
                    regionRow(region)
                }
            }
            .padding(.horizontal, KFSpacing.md)
            .padding(.bottom, KFSpacing.lg)
        }
    }

    // MARK: - Auto row

    private var autoRow: some View {
        let isAuto = vpn.connectedServer == nil || vpn.connectedServer?.region == nil

        return HStack(spacing: KFSpacing.md) {
            Text("🌐")
                .font(.system(size: 30))
                .frame(width: 44, height: 44)
                .background(Color.kfSurface)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("Auto (Best Available)")
                    .font(KFFont.body(16).weight(.semibold))
                    .foregroundStyle(Color.kfTextPrimary)
                Text("GeoIP + latency selection")
                    .font(KFFont.caption(12))
                    .foregroundStyle(Color.kfTextMuted)
            }

            Spacer()

            if connecting == "auto" {
                ProgressView().tint(Color.kfAccentBlue)
            } else if isAuto && vpn.status == .connected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.kfAccentBlue)
                    .font(.system(size: 18))
            }
        }
        .padding(KFSpacing.md)
        .frame(maxWidth: .infinity)
        .background(Color.kfSurface.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: KFRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: KFRadius.md, style: .continuous)
                .stroke(Color.kfBorder, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            guard connecting == nil else { return }
            Task { await connectAuto() }
        }
    }

    // MARK: - Region row

    private func regionRow(_ region: RegionSummary) -> some View {
        let bestPing = bestPingMs(for: region)

        return HStack(spacing: 0) {
            // Main tap area — connect
            Button {
                Task { await connect(to: region) }
            } label: {
                HStack(spacing: KFSpacing.md) {
                    Text(continentFlag(region.continent))
                        .font(.system(size: 30))
                        .frame(width: 44, height: 44)
                        .background(Color.kfSurface)
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(region.label)
                            .font(KFFont.body(16).weight(.semibold))
                            .foregroundStyle(Color.kfTextPrimary)
                        Text(nodeCountDescription(region))
                            .font(KFFont.caption(12))
                            .foregroundStyle(Color.kfTextMuted)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        if let ping = bestPing {
                            Text("\(Int(ping)) ms")
                                .font(KFFont.mono(13))
                                .foregroundStyle(pingColor(ping))
                        } else {
                            Text("—")
                                .font(KFFont.mono(13))
                                .foregroundStyle(Color.kfTextMuted)
                        }
                        loadBadge(score: region.avgLoadScore)
                    }

                    if connecting == region.id {
                        ProgressView().tint(Color.kfAccentBlue)
                    } else if vpn.connectedServer?.region == region.id {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.kfAccentBlue)
                            .font(.system(size: 18))
                    }
                }
                .padding(KFSpacing.md)
                .padding(.trailing, KFSpacing.xs)
            }
            .buttonStyle(.plain)
            .disabled(connecting != nil)

            // Drill-down button
            Divider()
                .frame(height: 28)
                .background(Color.kfBorder)
                .padding(.vertical, KFSpacing.md)

            Button {
                drillDownRegion = region
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.kfTextMuted)
                    .padding(.horizontal, KFSpacing.sm)
                    .padding(.vertical, KFSpacing.md)
            }
            .buttonStyle(.plain)
            .disabled(connecting != nil)
        }
        .frame(maxWidth: .infinity)
        .background(Color.kfSurface.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: KFRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: KFRadius.md, style: .continuous)
                .stroke(Color.kfBorder, lineWidth: 1)
        )
    }

    // MARK: - Drill-down destination

    @ViewBuilder
    private func regionDrillDown(region: RegionSummary) -> some View {
        let regionServers = servers.servers.filter { $0.server.region == region.id }
        ZStack {
            Color.kfBackground.ignoresSafeArea()
            if regionServers.isEmpty {
                VStack(spacing: KFSpacing.md) {
                    if servers.isLoading {
                        ProgressView().tint(Color.kfAccentBlue)
                        Text("Loading servers…")
                            .font(KFFont.caption(13))
                            .foregroundStyle(Color.kfTextMuted)
                    } else {
                        Text("No servers in this region")
                            .font(KFFont.body(14))
                            .foregroundStyle(Color.kfTextMuted)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: KFSpacing.xs) {
                        ForEach(regionServers.sorted {
                            switch ($0.milliseconds, $1.milliseconds) {
                            case (let a?, let b?): return a < b
                            case (.some, nil):     return true
                            default:               return false
                            }
                        }) { item in
                            Button {
                                servers.selectServer(item.server)
                                dismiss()
                                Task { try? await vpn.connectToServer(item.server) }
                            } label: {
                                HStack(spacing: KFSpacing.md) {
                                    Text(item.server.flagEmoji)
                                        .font(.system(size: 24))
                                        .frame(width: 36)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.server.cityName)
                                            .font(KFFont.body(15).weight(.semibold))
                                            .foregroundStyle(.white)
                                        Text(item.server.nodeId)
                                            .font(KFFont.mono(10))
                                            .foregroundStyle(Color.kfTextMuted)
                                    }
                                    Spacer()
                                    if let ms = item.milliseconds {
                                        Text("\(Int(ms)) ms")
                                            .font(KFFont.mono(12))
                                            .foregroundStyle(pingColor(ms))
                                    } else {
                                        Text("—").font(KFFont.mono(12)).foregroundStyle(Color.kfTextMuted)
                                    }
                                    if servers.selectedServer?.nodeId == item.server.nodeId {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Color.kfAccentBlue)
                                    }
                                }
                                .padding(KFSpacing.md)
                                .background(Color.kfSurface)
                                .clipShape(RoundedRectangle(cornerRadius: KFRadius.md, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: KFRadius.md, style: .continuous)
                                        .stroke(Color.kfBorder, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, KFSpacing.md)
                    .padding(.vertical, KFSpacing.sm)
                }
            }
        }
        .navigationTitle(region.label)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.kfBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task {
            if servers.servers.isEmpty { await servers.refresh() }
        }
    }

    private func loadBadge(score: Int) -> some View {
        let (label, color): (String, Color) = {
            switch score {
            case 0..<200:   return ("IDLE",   .green)
            case 200..<500: return ("LIGHT",  .green)
            case 500..<700: return ("BUSY",   .yellow)
            default:        return ("HEAVY",  .orange)
            }
        }()
        return Text(label)
            .font(KFFont.caption(10, weight: .bold))
            .kerning(0.8)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }

    // MARK: - Logic

    private var shouldShowMeasuringIndicator: Bool {
        servers.servers.allSatisfy { $0.milliseconds == nil } && servers.error == nil && !servers.servers.isEmpty
    }

    private func bestPingMs(for region: RegionSummary) -> Double? {
        servers.servers
            .filter { $0.server.region == region.id && $0.milliseconds != nil }
            .min { ($0.milliseconds ?? Double.infinity) < ($1.milliseconds ?? Double.infinity) }?
            .milliseconds
    }

    private func pingColor(_ ms: Double) -> Color {
        switch ms {
        case ..<80:  return Color(hex: "#22c55e")
        case ..<180: return Color(hex: "#f59e0b")
        default:     return Color(hex: "#ef4444")
        }
    }

    private var sortedRegions: [RegionSummary] {
        regions.sorted { a, b in
            let pingA = bestPingMs(for: a) ?? Double.infinity
            let pingB = bestPingMs(for: b) ?? Double.infinity

            if pingA < Double.infinity && pingB < Double.infinity && abs(pingA - pingB) < 5 {
                return a.avgLoadScore < b.avgLoadScore
            }
            if pingA != pingB { return pingA < pingB }
            return a.label < b.label
        }
    }

    private func nodeCountDescription(_ region: RegionSummary) -> String {
        let n = region.healthyNodeCount
        return n == 1 ? "1 server online" : "\(n) servers online"
    }

    private func continentFlag(_ continent: String) -> String {
        switch continent {
        case "NA": return "🌎"
        case "SA": return "🌎"
        case "EU": return "🌍"
        case "AF": return "🌍"
        case "AS": return "🌏"
        case "OC": return "🌏"
        default:   return "🌐"
        }
    }

    private func loadRegions() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            regions = try await APIClient.shared.fetchRegions()
        } catch {
            errorMessage = "Could not load regions — \(error.localizedDescription)"
        }
    }

    private func connectAuto() async {
        connecting = "auto"
        defer { connecting = nil }
        do {
            try await vpn.connectToRegion("auto")
            dismiss()
        } catch {
            errorMessage = "Connect failed — \(error.localizedDescription)"
        }
    }

    private func connect(to region: RegionSummary) async {
        connecting = region.id
        defer { connecting = nil }
        do {
            try await vpn.connectToRegion(region.id)
            dismiss()
        } catch {
            errorMessage = "Connect failed — \(error.localizedDescription)"
        }
    }
}

#Preview {
    RegionPickerView()
        .environmentObject(WireGuardManager())
}
