import SwiftUI

/// Katafract brand palette — sapphire + champagne gold.
///
/// Used across Vaultyx, DocArmor, Wraith, and future Enclave apps so every
/// surface feels like the same family. Hex values are locked; if marketing
/// needs to shift the brand, change here and every app updates.
public extension Color {

    // MARK: - Primary palette

    /// Deep cobalt background — matches icon-family navy. #0F2652
    static let kataNavy = Color(red: 0.059, green: 0.149, blue: 0.322)

    /// Near-black accent for gradient bottoms. #020610
    static let kataMidnight = Color(red: 0.008, green: 0.024, blue: 0.063)

    /// Sapphire-blue shield face / CTA accent. #1F5FAE
    static let kataSapphire = Color(red: 0.122, green: 0.373, blue: 0.682)

    /// Pale sky-blue highlight (shield rim, subtle UI chrome). #B8DFFF
    static let kataIce = Color(red: 0.722, green: 0.875, blue: 1.000)

    // MARK: - Accent (premium / Sovereign)

    /// Warm champagne gold for Sovereign accents. #C69838
    static let kataGold = Color(red: 0.776, green: 0.596, blue: 0.220)

    /// Bright champagne highlight. #FFE89A
    static let kataChampagne = Color(red: 1.000, green: 0.910, blue: 0.604)

    /// Deep bronze shadow. #6E4E15
    static let kataBronze = Color(red: 0.431, green: 0.306, blue: 0.082)

    // MARK: - Semantic

    /// Background for deep-mode surfaces (onboarding, paywall, recovery-phrase).
    static let kataSurface = Color.kataNavy

    /// Action/primary button tint.
    static let kataAction = Color.kataSapphire

    /// Premium CTA tint (Sovereign, Pro paths).
    static let kataPremium = Color.kataGold

    // MARK: - Gradients

    /// Background gradient — use as `.background(LinearGradient(...))` or
    /// `.background(Color.kataBackground)` via the static helpers below.
    static let kataBackgroundGradient = LinearGradient(
        colors: [.kataNavy, .kataMidnight],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Gold-to-orange gradient for premium CTAs (matches DALL-E Sovereign shield rim).
    static let kataPremiumGradient = LinearGradient(
        colors: [Color.kataChampagne.opacity(0.95), Color(red: 0.9, green: 0.56, blue: 0.14).opacity(0.9)],
        startPoint: .leading,
        endPoint: .trailing
    )
}
