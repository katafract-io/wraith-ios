// ServerPickerView.swift
// KatafractVPN
//
// Full-screen server list sorted by latency. Shows city name + flag, latency
// badge, and load indicator. Technical details (IPs, node IDs) are hidden.

import SwiftUI

struct ServerPickerView: View {

    @EnvironmentObject var servers: ServerListManager
    @EnvironmentObject var vpn:     WireGuardManager
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var sortByLatency = true

    // MARK: - Filtered / sorted list

    private var displayedServers: [ServerLatency] {
        var list = servers.servers

        if !searchText.isEmpty {
            list = list.filter {
                $0.server.cityName.localizedCaseInsensitiveContains(searchText) ||
                $0.server.region.localizedCaseInsensitiveContains(searchText)
            }
        }

        if sortByLatency {
            list = list.sorted {
                switch ($0.milliseconds, $1.milliseconds) {
                case (let a?, let b?): return a < b
                case (.some, nil):     return true
                case (nil, .some):     return false
                case (nil, nil):       return false
                }
            }
        } else {
            list = list.sorted { $0.server.cityName < $1.server.cityName }
        }
        return list
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kfBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Search bar
                    searchBar

                    // Sort toggle
                    sortToggle
                        .padding(.horizontal, KFSpacing.md)
                        .padding(.vertical, KFSpacing.xs)

                    Divider()
                        .background(Color.kfBorder)

                    if servers.isLoading && servers.servers.isEmpty {
                        loadingState
                    } else if displayedServers.isEmpty {
                        emptyState
                    } else {
                        serverList
                    }
                }
            }
            .navigationTitle("Choose Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.kfAccentBlue)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    if servers.isLoading {
                        ProgressView()
                            .tint(.kfAccentBlue)
                    }
                }
            }
            .toolbarBackground(Color.kfBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .preferredColorScheme(.dark)
            .task {
                if servers.servers.isEmpty {
                    await servers.refresh()
                }
            }
        }
    }

    // MARK: - Sub-views

    private var searchBar: some View {
        HStack(spacing: KFSpacing.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.kfTextMuted)
            TextField("Search cities…", text: $searchText)
                .foregroundStyle(.kfTextPrimary)
                .tint(.kfAccentBlue)
        }
        .padding(KFSpacing.sm)
        .background(Color.kfSurface)
        .clipShape(RoundedRectangle(cornerRadius: KFRadius.md))
        .padding(KFSpacing.md)
    }

    private var sortToggle: some View {
        HStack {
            Text("Sort by")
                .font(KFFont.caption(13))
                .foregroundStyle(.kfTextMuted)
            Spacer()
            Picker("Sort", selection: $sortByLatency) {
                Text("Latency").tag(true)
                Text("Name").tag(false)
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
        }
    }

    private var serverList: some View {
        ScrollView {
            LazyVStack(spacing: KFSpacing.xs) {
                ForEach(displayedServers) { item in
                    ServerRowView(
                        item: item,
                        isSelected: servers.selectedServer?.nodeId == item.server.nodeId
                    )
                    .onTapGesture {
                        selectServer(item.server)
                    }
                }
            }
            .padding(KFSpacing.md)
        }
    }

    private var loadingState: some View {
        VStack(spacing: KFSpacing.lg) {
            Spacer()
            ProgressView()
                .tint(.kfAccentBlue)
                .scaleEffect(1.4)
            Text("Loading servers…")
                .font(KFFont.body())
                .foregroundStyle(.kfTextMuted)
            Spacer()
        }
    }

    private var emptyState: some View {
        VStack(spacing: KFSpacing.md) {
            Spacer()
            Image(systemName: "server.rack")
                .font(.system(size: 48))
                .foregroundStyle(.kfTextMuted)
            Text("No servers found")
                .font(KFFont.heading())
                .foregroundStyle(.kfTextSecondary)
            Spacer()
        }
    }

    // MARK: - Actions

    private func selectServer(_ server: VPNServer) {
        servers.selectServer(server)
        // Haptic feedback
        let gen = UIImpactFeedbackGenerator(style: .medium)
        gen.impactOccurred()
        dismiss()
    }
}

// MARK: - Server row

private struct ServerRowView: View {
    let item: ServerLatency
    let isSelected: Bool

    var body: some View {
        HStack(spacing: KFSpacing.md) {
            // Flag
            Text(item.server.flagEmoji)
                .font(.system(size: 28))

            // City + region
            VStack(alignment: .leading, spacing: 2) {
                Text(item.server.cityName)
                    .font(KFFont.heading(16))
                    .foregroundStyle(.kfTextPrimary)
                Text(regionLabel)
                    .font(KFFont.caption(12))
                    .foregroundStyle(.kfTextMuted)
            }

            Spacer()

            // Load indicator
            LoadBar(score: item.server.loadScore)

            // Latency badge
            latencyBadge
        }
        .padding(KFSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: KFRadius.md, style: .continuous)
                .fill(isSelected ? Color.kfAccentBlue.opacity(0.12) : Color.kfSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: KFRadius.md, style: .continuous)
                .strokeBorder(
                    isSelected ? Color.kfAccentBlue.opacity(0.5) : Color.kfBorder,
                    lineWidth: 1
                )
        )
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }

    private var latencyBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(item.latencyTier.swiftUIColor)
                .frame(width: 7, height: 7)
            Text(item.displayLatency)
                .font(KFFont.mono(12))
                .foregroundStyle(item.latencyTier.swiftUIColor)
        }
        .padding(.horizontal, KFSpacing.xs)
        .padding(.vertical, 4)
        .background(item.latencyTier.swiftUIColor.opacity(0.12))
        .clipShape(Capsule())
    }

    private var regionLabel: String {
        item.server.region
    }
}

// MARK: - Load bar

private struct LoadBar: View {
    let score: Double   // 0.0 – 1.0

    private var color: Color {
        switch score {
        case ..<0.5: return .kfLatencyExcellent
        case ..<0.75: return .kfLatencyFair
        default:      return .kfLatencyPoor
        }
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("Load")
                .font(KFFont.caption(10))
                .foregroundStyle(.kfTextMuted)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.kfBorder)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(score))
                }
            }
            .frame(width: 44, height: 4)
        }
    }
}

// MARK: - Preview

#Preview {
    ServerPickerView()
        .environmentObject(ServerListManager())
        .environmentObject(WireGuardManager())
}
