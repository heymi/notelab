//
//  QuotaStatusView.swift
//  NoteLab
//
//  AI 配额状态提示视图
//

import SwiftUI

/// AI 配额状态视图 - 用于显示当前功能的配额使用情况
struct QuotaStatusView: View {
    let feature: AIFeature
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    
    private var usageTracker: UsageTracker {
        subscriptionManager.usageTracker
    }
    
    private var tier: SubscriptionTier {
        subscriptionManager.currentTier
    }
    
    var body: some View {
        let limit = feature.limit(for: tier)
        
        switch limit {
        case .unlimited:
            // Pro 用户，不显示限制
            EmptyView()
            
        case .disabled:
            // 功能不可用
            disabledView
            
        case .limited(let max):
            // 显示配额使用情况
            limitedView(max: max)
        }
    }
    
    private var disabledView: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 12, weight: .semibold))
            
            Text("\(feature.displayName)为付费功能")
                .font(.system(size: 13, weight: .medium))
            
            Spacer()
            
            Text("升级解锁")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color(hex: "FFD700"))
        }
        .foregroundStyle(Theme.secondaryInk)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.groupedBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
    
    private func limitedView(max: Int) -> some View {
        let used = usageTracker.usedCount(feature)
        let remaining = Swift.max(0, max - used)
        let percentage = usageTracker.usagePercentage(feature, tier: tier)
        
        return HStack(spacing: 12) {
            // 进度环
            ZStack {
                Circle()
                    .stroke(Theme.groupedBackground, lineWidth: 3)
                
                Circle()
                    .trim(from: 0, to: CGFloat(1 - percentage))
                    .stroke(
                        percentage > 0.8 ? Color.orange : Color.green,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 28, height: 28)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("\(feature.displayName)配额")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.ink)
                
                Text("本月剩余 \(remaining) 次")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(remaining == 0 ? .orange : Theme.secondaryInk)
            }
            
            Spacer()
            
            if remaining == 0 {
                Text("升级获取更多")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(hex: "FFD700"))
            } else {
                Text("\(remaining)/\(max)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(percentage > 0.8 ? .orange : .green)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.groupedBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// 配额耗尽提示视图
struct QuotaExhaustedView: View {
    let feature: AIFeature
    let onUpgrade: () -> Void
    
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            
            Text("\(feature.displayName)配额已用完")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.ink)
            
            Text("本月配额已耗尽，升级订阅获取更多次数或等待下月重置")
                .font(.system(size: 14))
                .foregroundStyle(Theme.secondaryInk)
                .multilineTextAlignment(.center)
            
            VStack(spacing: 8) {
                Text("距离配额重置还有")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryInk)
                
                Text("\(subscriptionManager.usageTracker.daysUntilReset) 天")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
            }
            .padding(.vertical, 8)
            
            Button {
                onUpgrade()
            } label: {
                Text("升级订阅")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: "FFD700"), Color(hex: "FFA500")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(24)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.1), radius: 20, y: 10)
        .padding(.horizontal, 32)
    }
}

/// 功能不可用提示视图
struct FeatureLockedView: View {
    let feature: AIFeature
    let onUpgrade: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Theme.groupedBackground)
                    .frame(width: 80, height: 80)
                
                Image(systemName: "lock.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(Theme.secondaryInk)
            }
            
            Text("\(feature.displayName)")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.ink)
            
            Text("此功能需要升级到更高版本才能使用")
                .font(.system(size: 14))
                .foregroundStyle(Theme.secondaryInk)
                .multilineTextAlignment(.center)
            
            // 功能说明
            featureDescription
            
            Button {
                onUpgrade()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 14))
                    Text("升级解锁")
                        .font(.system(size: 16, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    LinearGradient(
                        colors: [Color(hex: "FFD700"), Color(hex: "FFA500")],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(24)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.1), radius: 20, y: 10)
        .padding(.horizontal, 32)
    }
    
    @ViewBuilder
    private var featureDescription: some View {
        switch feature {
        case .rewrite:
            Text("AI 笔记重写可以帮助你优化、精炼或扩展笔记内容")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryInk)
                .multilineTextAlignment(.center)
        case .highlight:
            Text("AI 智能高亮可以自动识别并标记笔记中的关键内容")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryInk)
                .multilineTextAlignment(.center)
        case .recentFocus:
            Text("最近重点报告基于你的笔记生成智能分析和建议")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryInk)
                .multilineTextAlignment(.center)
        case .semanticConnections:
            Text("语义关联发现可以找出笔记之间隐藏的联系和主题")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryInk)
                .multilineTextAlignment(.center)
        default:
            EmptyView()
        }
    }
}

// MARK: - Preview

#Preview("Quota Status") {
    VStack(spacing: 16) {
        QuotaStatusView(feature: .organize)
        QuotaStatusView(feature: .rewrite)
    }
    .padding()
}

#Preview("Quota Exhausted") {
    QuotaExhaustedView(feature: .organize) {}
}

#Preview("Feature Locked") {
    FeatureLockedView(feature: .semanticConnections) {}
}
