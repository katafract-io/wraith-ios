import SwiftUI

/// Package-level re-exports + brand constants.
public enum KatafractStyle {
    /// Current palette version. Bump when colors change so apps can audit.
    public static let paletteVersion = 1

    /// Canonical marketing URL — shared across apps for "About" sections.
    public static let marketingURL = URL(string: "https://katafract.com")!
    public static let supportURL = URL(string: "https://katafract.com/support")!
    public static let privacyURL = URL(string: "https://katafract.com/privacy.html")!

    /// Vaultyx App Store deep link — used by sibling apps that surface
    /// the Sovereign upsell.
    public static let vaultyxAppStoreURL = URL(string: "https://apps.apple.com/app/id6762418528")!
}
