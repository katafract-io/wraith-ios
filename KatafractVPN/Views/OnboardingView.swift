// OnboardingView.swift
// KatafractVPN
//
// 3-screen onboarding carousel shown on first launch.
// Exits by calling onComplete(), which the root view uses to
// dismiss onboarding and persist the seen flag.

import SwiftUI

// MARK: - Data

private struct OnboardingPage: Identifiable {
    let id: Int
    let systemImage: String
    let title: String
    let body: String
    let accentColor: Color
}

private let pages: [OnboardingPage] = [
    OnboardingPage(
        id: 0,
        systemImage: "lock.shield.fill",
        title: "Your Privacy,\nFully Armored",
        body: "Katafract wraps every byte you send in military-grade WireGuard encryption. Your ISP, employer, and prying eyes see nothing.",
        accentColor: .kfAccentBlue
    ),
    OnboardingPage(
        id: 1,
        systemImage: "bolt.shield.fill",
        title: "Blindingly\nFast VPN",
        body: "WireGuard is the fastest VPN protocol on the planet. Connect to any of our global servers in under a second.",
        accentColor: .kfAccentMid
    ),
    OnboardingPage(
        id: 2,
        systemImage: "eye.slash.fill",
        title: "Zero Logs.\nZero Compromise.",
        body: "We never store connection logs, IP addresses, or browsing history. Your activity is yours alone.",
        accentColor: .kfAccentPurple
    ),
]

// MARK: - View

struct OnboardingView: View {
    var onComplete: () -> Void

    @State private var currentPage: Int = 0
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack {
            Color.kfBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Page content
                TabView(selection: $currentPage) {
                    ForEach(pages) { page in
                        OnboardingPageView(page: page)
                            .tag(page.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: currentPage)

                // Controls
                VStack(spacing: KFSpacing.lg) {
                    // Dot indicators
                    HStack(spacing: KFSpacing.xs) {
                        ForEach(pages) { page in
                            Capsule()
                                .fill(currentPage == page.id
                                      ? Color.white
                                      : Color.white.opacity(0.25))
                                .frame(width: currentPage == page.id ? 20 : 8, height: 8)
                                .animation(.spring(response: 0.35), value: currentPage)
                        }
                    }

                    // CTA button
                    Button(action: advance) {
                        Text(currentPage == pages.count - 1 ? "Get Started" : "Continue")
                            .font(KFFont.heading(18))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, KFSpacing.md)
                            .background(LinearGradient.kfAccent)
                            .clipShape(Capsule())
                    }
                    .padding(.horizontal, KFSpacing.xl)

                    // Skip link (only on non-last pages)
                    if currentPage < pages.count - 1 {
                        Button("Skip") { onComplete() }
                            .font(KFFont.body(14))
                            .foregroundStyle(.kfTextMuted)
                    } else {
                        Color.clear.frame(height: 20)
                    }
                }
                .padding(.bottom, KFSpacing.xxl)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func advance() {
        if currentPage < pages.count - 1 {
            withAnimation(.easeInOut(duration: 0.3)) {
                currentPage += 1
            }
        } else {
            onComplete()
        }
    }
}

// MARK: - Single page

private struct OnboardingPageView: View {
    let page: OnboardingPage

    @State private var appeared = false

    var body: some View {
        VStack(spacing: KFSpacing.xl) {
            Spacer()

            // Icon with glowing background
            ZStack {
                Circle()
                    .fill(page.accentColor.opacity(0.15))
                    .frame(width: 160, height: 160)
                    .blur(radius: 30)

                Circle()
                    .fill(page.accentColor.opacity(0.08))
                    .frame(width: 120, height: 120)

                Image(systemName: page.systemImage)
                    .font(.system(size: 56, weight: .medium))
                    .foregroundStyle(page.accentColor)
            }
            .scaleEffect(appeared ? 1 : 0.7)
            .opacity(appeared ? 1 : 0)

            // Title
            Text(page.title)
                .font(KFFont.display(36))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 20)

            // Body
            Text(page.body)
                .font(KFFont.body(16))
                .foregroundStyle(.kfTextSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, KFSpacing.xl)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 20)

            Spacer()
            Spacer()
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) {
                appeared = true
            }
        }
        .onDisappear { appeared = false }
    }
}

// MARK: - Preview

#Preview {
    OnboardingView { }
}
