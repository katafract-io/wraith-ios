import SwiftUI

@main
struct WraithVPNMacApp: App {

    @StateObject private var storeKit   = StoreKitManager()
    @StateObject private var vpnConfig  = VPNConfigManager.shared

    var body: some Scene {
        MenuBarExtra("WraithVPN", systemImage: storeKit.hasPurchased ? "shield.lefthalf.filled" : "shield") {
            MenuBarView()
                .environmentObject(storeKit)
                .environmentObject(vpnConfig)
        }
        .menuBarExtraStyle(.window)

        Window("Activate Wraith", id: "token-entry") {
            TokenEntryView()
                .environmentObject(storeKit)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 380, height: 300)
    }
}
