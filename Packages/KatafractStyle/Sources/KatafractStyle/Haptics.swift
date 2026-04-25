import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Semantic haptic vocabulary shared across Katafract apps.
///
/// The app never calls `UIImpactFeedbackGenerator` directly — it picks a
/// semantic event (e.g. `.unlocked`, `.denied`) and the palette chooses
/// the right generator + intensity. Keeps haptic design consistent so a
/// user jumping between Vaultyx and DocArmor feels the same "hand."
public enum KataHaptic {
    /// Vault unlocked, biometric passed, recovery accepted, sub activated.
    case unlocked
    /// Action committed — save, submit, upload complete.
    case saved
    /// Panel revealed — Present Mode engaged, paywall opened, modal presented.
    case revealed
    /// User error — wrong passphrase, quota exceeded, denied permission.
    case denied
    /// Subtle tap — tab switch, toggle flipped, selection moved.
    case tap
    /// Destructive confirmation — delete confirmed, logout, wipe vault.
    case destructive

    /// Fire the haptic once, synchronously, on the main thread.
    ///
    /// No-ops silently on platforms without UIKit (macOS main app, CLI tools).
    @MainActor
    public func fire() {
        #if canImport(UIKit)
        switch self {
        case .unlocked:
            let g = UINotificationFeedbackGenerator()
            g.prepare()
            g.notificationOccurred(.success)
        case .saved:
            let g = UIImpactFeedbackGenerator(style: .medium)
            g.prepare()
            g.impactOccurred()
        case .revealed:
            let g = UIImpactFeedbackGenerator(style: .rigid)
            g.prepare()
            g.impactOccurred()
        case .denied:
            let g = UINotificationFeedbackGenerator()
            g.prepare()
            g.notificationOccurred(.error)
        case .tap:
            let g = UIImpactFeedbackGenerator(style: .light)
            g.prepare()
            g.impactOccurred()
        case .destructive:
            let g = UINotificationFeedbackGenerator()
            g.prepare()
            g.notificationOccurred(.warning)
        }
        #endif
    }
}
