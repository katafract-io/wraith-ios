import Foundation
import AppKit

@MainActor
final class VPNConfigManager: ObservableObject {

    static let shared = VPNConfigManager()

    @Published var config: String?      // full wg-quick INI text
    @Published var peerId: String?
    @Published var nodeId: String?
    @Published var assignedIP: String?

    private init() { reload() }

    func reload() {
        config     = KeychainHelper.shared.readOptional(for: .wgConfig)
        peerId     = KeychainHelper.shared.readOptional(for: .wgPeerId)
        nodeId     = KeychainHelper.shared.readOptional(for: .wgNodeId)
        assignedIP = KeychainHelper.shared.readOptional(for: .wgAssignedIP)
    }

    func store(response: ProvisionResponse) throws {
        try KeychainHelper.shared.save(response.config,       for: .wgConfig)
        try KeychainHelper.shared.save(response.peerId,       for: .wgPeerId)
        try KeychainHelper.shared.save(response.nodeId,       for: .wgNodeId)
        try KeychainHelper.shared.save(response.assignedIpv4, for: .wgAssignedIP)
        reload()
    }

    func clear() {
        KeychainHelper.shared.delete(for: .wgConfig)
        KeychainHelper.shared.delete(for: .wgPeerId)
        KeychainHelper.shared.delete(for: .wgNodeId)
        KeychainHelper.shared.delete(for: .wgAssignedIP)
        reload()
    }

    /// Saves the config to a temp file and opens it in WireGuard.
    func exportConfig(label: String = "wraith") {
        guard let config else { return }
        let name = "\(label)-wraith.conf"
        let url  = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? config.write(to: url, atomically: true, encoding: .utf8)
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        if let wg = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.wireguard.macos") {
            NSWorkspace.shared.open([url], withApplicationAt: wg, configuration: cfg)
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    /// Writes config to Downloads folder and reveals it in Finder.
    func downloadConfig(label: String = "wraith") {
        guard let config else { return }
        let name      = "\(label)-wraith.conf"
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let url       = downloads.appendingPathComponent(name)
        do {
            try config.write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            NSWorkspace.shared.open(downloads)
        }
    }
}
