//
//  PaywallView.swift
//  NoteLab
//
//  付费墙视图 - 展示订阅选项和功能对比
//

import SwiftUI
import StoreKit

struct PaywallView: View {
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedTier: SubscriptionTier = .pro
    @State private var isYearly: Bool = true
    @State private var isPurchasing: Bool = false
    @State private var showError: Bool = false
    
    let trigger: PaywallTrigger
    
    init(trigger: PaywallTrigger = .manual) {
        self.trigger = trigger
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    headerSection
                    
                    // 功能对比
                    featureComparisonSection
                    
                    // 订阅选项
                    subscriptionOptionsSection
                    
                    // 购买按钮
                    purchaseButton
                    
                    // 恢复购买 & 条款
                    footerSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(Theme.background)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                    .foregroundStyle(Theme.secondaryInk)
                }
            }
            #else
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                    .foregroundStyle(Theme.secondaryInk)
                }
            }
            #endif
        }
        .alert("购买失败", isPresented: $showError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(subscriptionManager.purchaseError ?? "发生未知错误")
        }
        .onChange(of: subscriptionManager.purchaseError) { _, newValue in
            showError = newValue != nil
        }
        .task {
            if subscriptionManager.products.isEmpty {
                await subscriptionManager.loadProducts()
            }
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            // Crown icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "FFD700"), Color(hex: "FFA500")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                
                Image(systemName: "crown.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.white)
            }
            .shadow(color: Color(hex: "FFD700").opacity(0.4), radius: 12, y: 4)
            
            VStack(spacing: 8) {
                Text("升级到 NoteLab Pro")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                
                Text("释放无限创造力，享受极致笔记体验")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.secondaryInk)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 20)
    }
    
    // MARK: - Feature Comparison
    
    private var featureComparisonSection: some View {
        VStack(spacing: 12) {
            PaywallFeatureRow(
                icon: "folder.fill",
                title: "无限笔记本",
                freeValue: "3 个",
                standardValue: "无限",
                proValue: "无限",
                iconColor: .blue
            )
            
            PaywallFeatureRow(
                icon: "icloud.fill",
                title: "多端云同步",
                freeValue: "—",
                standardValue: "✓",
                proValue: "✓",
                iconColor: .cyan
            )
            
            PaywallFeatureRow(
                icon: "wand.and.stars",
                title: "AI 笔记整理",
                freeValue: "3次/月",
                standardValue: "15次/月",
                proValue: "无限",
                iconColor: .purple
            )
            
            PaywallFeatureRow(
                icon: "doc.text.magnifyingglass",
                title: "AI 任务提取",
                freeValue: "3次/月",
                standardValue: "15次/月",
                proValue: "无限",
                iconColor: .orange
            )
            
            PaywallFeatureRow(
                icon: "pencil.and.outline",
                title: "AI 笔记重写",
                freeValue: "—",
                standardValue: "10次/月",
                proValue: "无限",
                iconColor: .pink
            )
            
            PaywallFeatureRow(
                icon: "link",
                title: "语义关联发现",
                freeValue: "—",
                standardValue: "—",
                proValue: "✓",
                iconColor: .green
            )
            
            PaywallFeatureRow(
                icon: "faceid",
                title: "Face ID 锁定",
                freeValue: "—",
                standardValue: "—",
                proValue: "✓",
                iconColor: .indigo
            )
        }
        .padding(16)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Subscription Options
    
    private var subscriptionOptionsSection: some View {
        VStack(spacing: 16) {
            // Tier selection
            HStack(spacing: 12) {
                TierButton(
                    tier: .standard,
                    isSelected: selectedTier == .standard,
                    action: { selectedTier = .standard }
                )
                
                TierButton(
                    tier: .pro,
                    isSelected: selectedTier == .pro,
                    action: { selectedTier = .pro }
                )
            }
            
            // Period toggle
            Picker("订阅周期", selection: $isYearly) {
                Text("年度").tag(true)
                Text("月度").tag(false)
            }
            .pickerStyle(.segmented)
            
            // Price display
            if let product = selectedProduct {
                VStack(spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(product.displayPrice)
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.ink)
                        
                        Text("/ \(isYearly ? "年" : "月")")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Theme.secondaryInk)
                    }
                    
                    if isYearly {
                        let savings = subscriptionManager.yearlySavingsPercentage(for: selectedTier)
                        if savings > 0 {
                            Text("相比月付节省 \(savings)%")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color(hex: "FFD700"))
                        }
                    }
                    
                    // Introductory offer
                    if let subscription = product.subscription,
                       let introOffer = subscription.introductoryOffer {
                        Text(introOfferText(introOffer))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.green)
                    }

                    Text(subscriptionTermsText(for: product))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryInk)
                        .multilineTextAlignment(.center)
                }
            } else {
                productUnavailableView
            }
        }
    }
    
    // MARK: - Purchase Button
    
    private var purchaseButton: some View {
        Button {
            Task {
                await purchase()
            }
        } label: {
            HStack(spacing: 8) {
                if isPurchasing || subscriptionManager.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Text(purchaseButtonTitle)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                LinearGradient(
                    colors: subscriptionManager.isPremium
                        ? [Color.gray, Color.gray]
                        : [Color(hex: "FFD700"), Color(hex: "FFA500")],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: Color(hex: "FFD700").opacity(0.3), radius: 8, y: 4)
        }
        .disabled(isPurchasing || subscriptionManager.isLoading || subscriptionManager.isPremium || selectedProduct == nil)
    }
    
    // MARK: - Footer Section
    
    private var footerSection: some View {
        VStack(spacing: 16) {
            Button {
                Task {
                    await subscriptionManager.restorePurchases()
                }
            } label: {
                Text("恢复购买")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.secondaryInk)
            }
            
            VStack(spacing: 8) {
                Text("确认购买后将向 Apple ID 扣款。订阅会自动续订，除非在当前周期结束前至少 24 小时关闭自动续订。续订将在周期结束前 24 小时内扣款。")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                
                HStack(spacing: 16) {
                    Link("隐私政策", destination: URL(string: "https://notelab.app/privacy")!)
                    Link("服务条款", destination: URL(string: "https://notelab.app/terms")!)
                }
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryInk)
            }
            .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }
    
    // MARK: - Actions
    
    private func purchase() async {
        guard let product = selectedProduct else {
            subscriptionManager.purchaseError = SubscriptionError.productNotFound.localizedDescription
            return
        }
        
        isPurchasing = true
        defer { isPurchasing = false }
        
        do {
            if let _ = try await subscriptionManager.purchase(product) {
                // 购买成功，关闭付费墙
                dismiss()
            }
        } catch {
            // 错误已经在 subscriptionManager 中处理
        }
    }
    
    // MARK: - Helpers

    private var selectedProduct: Product? {
        subscriptionManager.product(tier: selectedTier, yearly: isYearly)
    }

    private var purchaseButtonTitle: String {
        if subscriptionManager.isPremium { return "已订阅" }
        if selectedProduct == nil { return "订阅产品不可用" }
        return "立即订阅"
    }

    private var productUnavailableView: some View {
        VStack(spacing: 10) {
            Text(subscriptionManager.productLoadError ?? "正在加载订阅产品")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button("重新加载") {
                Task {
                    await subscriptionManager.loadProducts()
                }
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.ink)
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func subscriptionTermsText(for product: Product) -> String {
        let period = isYearly ? "每年" : "每月"
        return "\(product.displayName)：\(product.displayPrice) \(period)，自动续订。"
    }
    
    private func introOfferText(_ offer: Product.SubscriptionOffer) -> String {
        switch offer.paymentMode {
        case .freeTrial:
            let days: Int
            switch offer.period.unit {
            case .day:
                days = offer.period.value
            case .week:
                days = offer.period.value * 7
            case .month:
                days = offer.period.value * 30
            case .year:
                days = offer.period.value * 365
            @unknown default:
                days = offer.period.value
            }
            return "首次订阅免费试用 \(days) 天"
        case .payUpFront:
            return "首期优惠 \(offer.displayPrice)"
        case .payAsYouGo:
            return "优惠期 \(offer.displayPrice)"
        default:
            return ""
        }
    }
}

// MARK: - Tier Button

private struct TierButton: View {
    let tier: SubscriptionTier
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(tier.displayName)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                
                Text(tier == .pro ? "全部功能" : "基础功能")
                    .font(.system(size: 12, weight: .medium))
                    .opacity(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                isSelected
                ? LinearGradient(
                    colors: [Color(hex: "FFD700"), Color(hex: "FFA500")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                : LinearGradient(
                    colors: [Theme.cardBackground, Theme.cardBackground],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .foregroundStyle(isSelected ? .white : Theme.ink)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.clear : Theme.secondaryInk.opacity(0.2), lineWidth: 1)
            )
        }
    }
}

// MARK: - Feature Row

struct PaywallFeatureRow: View {
    let icon: String
    let title: String
    let freeValue: String
    let standardValue: String
    let proValue: String
    let iconColor: Color
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 24)
            
            // Title
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.ink)
            
            Spacer()
            
            // Values
            HStack(spacing: 0) {
                Text(freeValue)
                    .frame(width: 50, alignment: .center)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.secondaryInk)
                
                Text(standardValue)
                    .frame(width: 50, alignment: .center)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(standardValue == "—" ? Theme.secondaryInk : Theme.ink)
                
                Text(proValue)
                    .frame(width: 50, alignment: .center)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(proValue == "—" ? Theme.secondaryInk : Color(hex: "FFD700"))
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Preview

#Preview {
    PaywallView(trigger: .manual)
}
