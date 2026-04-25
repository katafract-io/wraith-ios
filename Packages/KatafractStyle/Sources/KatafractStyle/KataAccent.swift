import SwiftUI

/// Convenience namespace for Katafract brand accent colors.
///
/// Put one at the top of your scene so every downstream control inherits it:
/// ```swift
/// WindowGroup { RootView() }
///     .tint(KataAccent.gold)
/// ```
public enum KataAccent {
    /// Warm champagne gold — Sovereign / premium actions.
    public static let gold = Color.kataGold

    /// Cobalt sapphire — standard CTAs and interactive chrome.
    public static let sapphire = Color.kataSapphire
}
