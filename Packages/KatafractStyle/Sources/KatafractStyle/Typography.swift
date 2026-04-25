import SwiftUI

/// Katafract typography tokens.
///
/// Default font stack is SF Pro (system). Branded serif accents use
/// `New York` (bundled by Apple) as a fallback for Cormorant Garamond —
/// no custom font files shipped in v1 of this package to keep each app
/// binary small. If marketing wants Cormorant Garamond, apps can bundle
/// the OFL font and add `.cormorant(...)` tokens later.
public extension Font {

    // MARK: - Display (hero / paywall headlines)

    /// Large hero font — matches katafract.com Cormorant Garamond headers
    /// via SF Serif (New York) with heavy weight. 40pt default.
    static func kataDisplay(_ size: CGFloat = 40, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    /// Mid-tier headline. 24pt default.
    static func kataHeadline(_ size: CGFloat = 24, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    // MARK: - Body

    /// Body copy — system sans serif. 16pt default.
    static func kataBody(_ size: CGFloat = 16, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    /// Small caption for disclosures, footers, metadata. 12pt default.
    static func kataCaption(_ size: CGFloat = 12, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    // MARK: - Mono (version strings, keys, recovery phrase words)

    /// Monospace for technical content (recovery phrase, keys, diagnostic dumps).
    static func kataMono(_ size: CGFloat = 14, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
