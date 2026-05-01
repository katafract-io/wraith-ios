import SwiftUI
import KatafractStyle

struct TransportFallbackBadge: View {
    @State private var showDetails = false
    
    var body: some View {
        VStack(spacing: KFSpacing.sm) {
            Button(action: { showDetails.toggle() }) {
                HStack(spacing: 4) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 10, weight: .semibold))
                    Text("DPI-resistant transport active")
                        .font(.kataMono(12))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.kataGold.opacity(0.15))
                .foregroundStyle(Color.kataGold)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.kataGold.opacity(0.35), lineWidth: 0.5))
            }
            
            if showDetails {
                VStack(alignment: .leading, spacing: KFSpacing.sm) {
                    Text("Shadowsocks over TLS")
                        .font(KFFont.body(13))
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                    
                    Text("Direct WireGuard was blocked by the network. Wraith automatically switched to Shadowsocks over TLS to keep your tunnel up. No setup needed.")
                        .font(KFFont.caption(12))
                        .foregroundStyle(Color.kfTextSecondary)
                        .lineSpacing(1.2)
                }
                .padding(KFSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.kfSurface.opacity(0.92))
                .clipShape(RoundedRectangle(cornerRadius: KFRadius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: KFRadius.md, style: .continuous)
                        .stroke(Color.kataGold.opacity(0.25), lineWidth: 1)
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showDetails)
    }
}

#Preview {
    VStack(spacing: KFSpacing.lg) {
        TransportFallbackBadge()
            .padding(KFSpacing.lg)
        
        Spacer()
    }
    .background(Color.kfBackground)
}
