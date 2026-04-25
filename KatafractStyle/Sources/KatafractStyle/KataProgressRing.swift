import SwiftUI

// MARK: - KataProgressRing

/// A branded circular progress indicator for the Katafract lane.
///
/// Drop-in replacement for stock `ProgressView`. Uses a `kataGold` hairline
/// arc so every loading state feels like the same premium family.
///
/// - Determinate: pass a `progress` value in `0.0...1.0`.
/// - Indeterminate: pass `nil` (or omit) — the arc spins continuously.
///
/// Example:
/// ```swift
/// // Indeterminate, 28pt default
/// KataProgressRing()
///
/// // Determinate, lock glyph
/// KataProgressRing(progress: uploadProgress, systemImage: "lock.fill")
///
/// // Large indeterminate
/// KataProgressRing(size: 44)
/// ```
public struct KataProgressRing: View {

    // MARK: - Init

    private let progress: Double?
    private let size: CGFloat
    private let systemImage: String?

    /// Creates a progress ring.
    /// - Parameters:
    ///   - progress: A value in `0.0...1.0`, or `nil` for indeterminate mode.
    ///   - size:     Diameter of the ring in points. Default 28.
    ///   - systemImage: Optional SF Symbol drawn at 45 % of `size` in the centre.
    public init(progress: Double? = nil, size: CGFloat = 28, systemImage: String? = nil) {
        self.progress = progress
        self.size = size
        self.systemImage = systemImage
    }

    // MARK: - State

    @State private var rotation: Double = 0

    // MARK: - Body

    public var body: some View {
        ZStack {
            // Backing track
            Circle()
                .stroke(Color.kataGold.opacity(0.12), lineWidth: 0.5)
                .frame(width: size, height: size)

            if let p = progress {
                // Determinate arc
                Circle()
                    .trim(from: 0, to: p)
                    .stroke(Color.kataGold.opacity(0.6), style: StrokeStyle(lineWidth: 0.5, lineCap: .round))
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(-90))
            } else {
                // Indeterminate arc
                Circle()
                    .trim(from: 0, to: 0.25)
                    .stroke(Color.kataGold.opacity(0.6), style: StrokeStyle(lineWidth: 0.5, lineCap: .round))
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(rotation))
                    .onAppear {
                        withAnimation(
                            .linear(duration: 1.2)
                            .repeatForever(autoreverses: false)
                        ) {
                            rotation = 360
                        }
                    }
            }

            // Optional centre glyph
            if let name = systemImage {
                if progress == nil {
                    Image(systemName: name)
                        .font(.system(size: size * 0.45))
                        .foregroundStyle(Color.kataGold)
                        .symbolEffect(.pulse)
                } else {
                    Image(systemName: name)
                        .font(.system(size: size * 0.45))
                        .foregroundStyle(Color.kataGold)
                }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("KataProgressRing") {
    VStack(spacing: 32) {
        // Determinate at 33 %
        VStack(spacing: 8) {
            KataProgressRing(progress: 0.33, size: 28)
            Text("Determinate 33 %")
                .font(.caption)
                .foregroundStyle(Color.kataGold)
        }

        // Indeterminate
        VStack(spacing: 8) {
            KataProgressRing(size: 28)
            Text("Indeterminate")
                .font(.caption)
                .foregroundStyle(Color.kataGold)
        }

        // With glyph
        VStack(spacing: 8) {
            KataProgressRing(progress: 0.33, size: 44, systemImage: "lock.fill")
            Text("With lock.fill glyph")
                .font(.caption)
                .foregroundStyle(Color.kataGold)
        }

        // Indeterminate + glyph (pulse)
        VStack(spacing: 8) {
            KataProgressRing(size: 44, systemImage: "lock.fill")
            Text("Indeterminate + glyph")
                .font(.caption)
                .foregroundStyle(Color.kataGold)
        }
    }
    .padding(40)
    .background(Color.kataNavy)
}
#endif
