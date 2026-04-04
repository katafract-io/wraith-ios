// PacketTunnelProvider.swift
// WireGuardTunnel
//
// NetworkExtension packet tunnel provider that boots the WireGuard backend
// using a wg-quick style configuration string supplied by the main app.

import NetworkExtension
import WireGuardKit
import os.log

private let log = Logger(subsystem: "com.katafract.wraith.tunnel", category: "PacketTunnelProvider")

final class PacketTunnelProvider: NEPacketTunnelProvider {

    private lazy var adapter: WireGuardAdapter = {
        WireGuardAdapter(with: self) { logLevel, message in
            log.log(level: logLevel.osLogType, "\(message, privacy: .public)")
        }
    }()

    override func startTunnel(
        options: [String: NSObject]?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        log.info("startTunnel called")

        guard let proto = protocolConfiguration as? NETunnelProviderProtocol,
              let providerConfig = proto.providerConfiguration,
              let wgConfig = providerConfig["wgConfig"] as? String else {
            let error = TunnelError.missingConfiguration
            log.error("Missing WireGuard config")
            completionHandler(error)
            return
        }

        let tunnelConfiguration: TunnelConfiguration
        do {
            tunnelConfiguration = try TunnelConfiguration(fromWgQuickConfig: wgConfig, called: "wraith")
        } catch {
            log.error("Failed to parse WireGuard config: \(error.localizedDescription, privacy: .public)")
            completionHandler(TunnelError.invalidConfiguration)
            return
        }

        adapter.start(tunnelConfiguration: tunnelConfiguration) { [weak self] adapterError in
            guard let self else {
                completionHandler(TunnelError.adapterDeallocated)
                return
            }

            guard let adapterError else {
                let interfaceName = self.adapter.interfaceName ?? "unknown"
                log.info("WireGuard tunnel started on interface \(interfaceName, privacy: .public)")
                completionHandler(nil)
                return
            }

            log.error("WireGuard adapter start failed: \(String(describing: adapterError), privacy: .public)")
            completionHandler(adapterError.asTunnelError)
        }
    }

    override func stopTunnel(
        with reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        log.info("stopTunnel called, reason=\(reason.rawValue)")

        adapter.stop { adapterError in
            if let adapterError {
                log.error("Failed to stop WireGuard adapter: \(String(describing: adapterError), privacy: .public)")
            }
            completionHandler()
        }
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        guard let completionHandler else { return }

        if messageData.count == 1, messageData[0] == 0 {
            adapter.getRuntimeConfiguration { config in
                completionHandler(config?.data(using: .utf8))
            }
        } else {
            completionHandler(nil)
        }
    }
}

enum TunnelError: LocalizedError {
    case missingConfiguration
    case invalidConfiguration
    case dnsResolutionFailure
    case couldNotSetNetworkSettings
    case couldNotStartBackend
    case couldNotDetermineFileDescriptor
    case adapterDeallocated

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "WireGuard configuration missing from provider configuration dictionary."
        case .invalidConfiguration:
            return "The saved WireGuard configuration could not be parsed."
        case .dnsResolutionFailure:
            return "DNS resolution failed for the WireGuard endpoint."
        case .couldNotSetNetworkSettings:
            return "The tunnel network settings could not be applied."
        case .couldNotStartBackend:
            return "The WireGuard backend failed to start."
        case .couldNotDetermineFileDescriptor:
            return "WireGuard could not determine the tunnel file descriptor."
        case .adapterDeallocated:
            return "The WireGuard adapter was released before startup completed."
        }
    }
}

private extension WireGuardAdapterError {
    var asTunnelError: TunnelError {
        switch self {
        case .cannotLocateTunnelFileDescriptor:
            return .couldNotDetermineFileDescriptor
        case .dnsResolution:
            return .dnsResolutionFailure
        case .setNetworkSettings:
            return .couldNotSetNetworkSettings
        case .startWireGuardBackend:
            return .couldNotStartBackend
        case .invalidState:
            return .invalidConfiguration
        }
    }
}

private extension WireGuardLogLevel {
    var osLogType: OSLogType {
        switch self {
        case .verbose:
            return .debug
        case .error:
            return .error
        }
    }
}
