import SwiftUI

struct PremiumIntroView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("isPremium") private var isPremium: Bool = false
    @State private var isPurchasing = false
    
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 32) {
                    // Header Image
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "FFD700").opacity(0.15), Color(hex: "FFA500").opacity(0.15)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 120, height: 120)
                            .blur(radius: 30)
                        
                        Image(systemName: "crown.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(hex: "FFD700"), Color(hex: "FFA500")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: Color.orange.opacity(0.4), radius: 10, x: 0, y: 5)
                    }
                    .padding(.top, 40)
                    
                    // Title
                    VStack(spacing: 12) {
                        Text("解锁 NoteLab Pro")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.ink)
                        
                        Text("释放无限创造力，享受极致笔记体验")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.secondaryInk)
                            .multilineTextAlignment(.center)
                    }
                    
                    // Features Grid
                    VStack(spacing: 28) {
                        FeatureRow(icon: "book.fill", color: .blue, title: "无限笔记本", description: "创建任意数量的笔记本，不再受限。")
                        FeatureRow(icon: "sparkles", color: .purple, title: "AI 智能助手", description: "无限次使用 AI 摘要、润色和续写功能。")
                        FeatureRow(icon: "icloud.fill", color: .cyan, title: "多端云同步", description: "在 iPhone、iPad 和 Mac 间实时同步。")
                        FeatureRow(icon: "lock.fill", color: .green, title: "高级安全", description: "支持面容 ID 解锁笔记本。")
                    }
                    .padding(24)
                    .background(Theme.cardBackground)
                    .clipShape(.rect(cornerRadius: 24))
                    .shadow(color: Theme.softShadow, radius: 12, x: 0, y: 6)
                    .padding(.horizontal, 20)
                    
                    Spacer(minLength: 120) // Bottom spacing for safe area
                }
            }
            .scrollIndicators(.hidden)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 16) {
                // Subscribe Button
                Button(action: purchase) {
                    HStack {
                        if isPurchasing {
                            ProgressView()
                                .tint(.white)
                                .padding(.trailing, 8)
                        }
                        Text(isPremium ? "您已是 Pro 会员" : "立即订阅 - ¥68.00 / 年")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: isPremium ? [Color.gray] : [Color(hex: "FFD700"), Color(hex: "FFA500")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundStyle(.white)
                    .clipShape(.rect(cornerRadius: 16))
                    .shadow(color: isPremium ? .clear : Color.orange.opacity(0.4), radius: 10, x: 0, y: 5)
                }
                .disabled(isPremium || isPurchasing)
                
                // Restore Purchase
                Button("恢复购买") {
                    // Mock restore
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.secondaryInk)
                .padding(.bottom, 8)
            }
            .padding(20)
            .background(.ultraThinMaterial)
        }
        .navigationTitle("NoteLab Pro")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        #endif
    }
    
    private func purchase() {
        isPurchasing = true
        // Mock delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isPremium = true
            isPurchasing = false
            dismiss()
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.1))
                    .frame(width: 48, height: 48)
                
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundStyle(color)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                
                Text(description)
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundStyle(Theme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    PremiumIntroView()
}
