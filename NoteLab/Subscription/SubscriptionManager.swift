//
//  SubscriptionManager.swift
//  NoteLab
//
//  订阅管理器 - 基于 StoreKit 2 的订阅状态管理
//

import Foundation
import StoreKit
import Combine
import os

/// 订阅管理器单例
@MainActor
final class SubscriptionManager: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = SubscriptionManager()
    
    // MARK: - Published State
    
    /// 当前订阅等级
    @Published private(set) var currentTier: SubscriptionTier = .free
    
    /// 是否正在加载
    @Published private(set) var isLoading: Bool = false
    
    /// 可用的订阅产品
    @Published private(set) var products: [Product] = []
    
    /// 购买错误信息
    @Published var purchaseError: String?

    /// 产品加载错误信息
    @Published private(set) var productLoadError: String?
    
    /// 订阅过期时间
    @Published private(set) var expirationDate: Date?
    
    /// 当前产品 ID
    @Published private(set) var currentProductId: String?
    
    // MARK: - Dependencies
    
    private let entitlementCache = EntitlementCache.shared
    let usageTracker = UsageTracker.shared
    private let logger = Logger(subsystem: "NoteLab", category: "Subscription")
    
    // MARK: - Private State
    
    private var updateListenerTask: Task<Void, Never>?

    #if DEBUG
    private var debugTierOverride: SubscriptionTier?
    #endif
    
    // MARK: - Computed Properties
    
    /// 当前功能开关
    var featureFlags: FeatureFlags {
        FeatureFlags(tier: currentTier)
    }
    
    /// 是否为付费用户
    var isPremium: Bool {
        currentTier > .free
    }
    
    /// 是否为专业版用户
    var isPro: Bool {
        currentTier >= .pro
    }
    
    // MARK: - Initialization
    
    private init() {
        // 从缓存恢复状态
        self.currentTier = entitlementCache.cachedTier
        self.expirationDate = entitlementCache.cachedExpiration

        // 启动交易监听
        updateListenerTask = listenForTransactionUpdates()
        
        // 异步加载产品和验证权益
        Task {
            await loadProducts()
            await refreshEntitlementState()
        }
    }
    
    deinit {
        updateListenerTask?.cancel()
    }
    
    // MARK: - Transaction Listener
    
    private func listenForTransactionUpdates() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                await self?.handleTransactionUpdate(result)
            }
        }
    }
    
    private func handleTransactionUpdate(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else {
            logger.warning("Received unverified transaction update")
            return
        }
        
        logger.info("Transaction update: \(transaction.productID)")

        let applied = applyEntitlement(from: transaction)

        // 完成交易
        await transaction.finish()

        if !applied {
            await refreshEntitlementState(allowCachedFallback: false)
        }
        
        // 发送通知
        NotificationCenter.default.post(name: .subscriptionStatusChanged, object: nil)
    }
    
    // MARK: - Load Products
    
    /// 加载订阅产品
    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            productLoadError = nil
            let storeProducts = try await Product.products(for: SubscriptionProductID.allProductIds)
            
            // 按价格排序（年度在前）
            products = storeProducts.sorted { p1, p2 in
                // Pro 在前
                let tier1 = SubscriptionProductID.tier(for: p1.id)
                let tier2 = SubscriptionProductID.tier(for: p2.id)
                if tier1 != tier2 {
                    return tier1 > tier2
                }
                // 同等级内，年度在前
                let isYearly1 = SubscriptionProductID.isYearly(p1.id)
                let isYearly2 = SubscriptionProductID.isYearly(p2.id)
                if isYearly1 != isYearly2 {
                    return isYearly1
                }
                return p1.price > p2.price
            }
            
            if products.isEmpty {
                productLoadError = "未加载到订阅产品。请确认 App Store Connect 产品 ID，或使用 NoteLab Local StoreKit scheme 进行本地沙盒测试。"
            }

            logger.info("Loaded \(storeProducts.count) products")
        } catch {
            productLoadError = error.localizedDescription
            logger.error("Failed to load products: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Refresh Entitlement
    
    /// 刷新权益状态
    func refreshEntitlementState(allowCachedFallback: Bool = true) async {
        var highestTier: SubscriptionTier = .free
        var latestExpiration: Date?
        var activeProductId: String?

        // 遍历当前权益
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else {
                continue
            }

            // 根据产品 ID 确定等级
            let tier = SubscriptionProductID.activeTier(
                for: transaction.productID,
                expiration: transaction.expirationDate,
                revocationDate: transaction.revocationDate
            )
            if tier > highestTier {
                highestTier = tier
                latestExpiration = transaction.expirationDate
                activeProductId = transaction.productID
            }
        }

        if highestTier == .free, allowCachedFallback {
            let cachedTier = entitlementCache.cachedTier
            if cachedTier > .free {
                highestTier = cachedTier
                latestExpiration = entitlementCache.cachedExpiration
                activeProductId = currentProductId
                logger.info("Entitlement refresh kept cached paid tier while StoreKit catches up")
            }
        }

        #if DEBUG
        // Check AFTER the async iteration — debugSetTier may have run
        // on MainActor while we were suspended in the for-await loop.
        if debugTierOverride != nil {
            logger.info("Entitlement refresh skipped — debug tier override active")
            return
        }
        #endif

        // 更新状态
        self.currentTier = highestTier
        self.expirationDate = latestExpiration
        self.currentProductId = activeProductId
        
        // 缓存到 Keychain
        entitlementCache.cacheTier(highestTier, expiration: latestExpiration)
        
        logger.info("Entitlement refreshed: tier=\(highestTier.displayName), expires=\(latestExpiration?.description ?? "nil")")
    }

    @discardableResult
    private func applyEntitlement(from transaction: Transaction) -> Bool {
        let tier = SubscriptionProductID.activeTier(
            for: transaction.productID,
            expiration: transaction.expirationDate,
            revocationDate: transaction.revocationDate
        )

        guard tier > .free else {
            return false
        }

        if tier >= currentTier {
            currentTier = tier
            expirationDate = transaction.expirationDate
            currentProductId = transaction.productID
            entitlementCache.cacheTier(tier, expiration: transaction.expirationDate)
        }

        logger.info("Entitlement applied from verified transaction: tier=\(tier.displayName), product=\(transaction.productID)")
        return true
    }
    
    // MARK: - Purchase
    
    /// 购买产品
    @discardableResult
    func purchase(_ product: Product) async throws -> Transaction? {
        isLoading = true
        purchaseError = nil
        
        defer { isLoading = false }
        
        do {
            let result = try await product.purchase()
            
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    throw SubscriptionError.verificationFailed
                }
                
                logger.info("Purchase successful: \(product.id)")

                let applied = applyEntitlement(from: transaction)
                
                // 完成交易
                await transaction.finish()

                if !applied {
                    await refreshEntitlementState(allowCachedFallback: false)
                }
                
                // 发送通知
                NotificationCenter.default.post(name: .subscriptionStatusChanged, object: nil)
                
                return transaction
                
            case .userCancelled:
                logger.info("Purchase cancelled by user")
                return nil
                
            case .pending:
                logger.info("Purchase pending (Ask to Buy)")
                throw SubscriptionError.purchasePending
                
            @unknown default:
                throw SubscriptionError.unknown
            }
        } catch let error as SubscriptionError {
            purchaseError = error.localizedDescription
            throw error
        } catch {
            purchaseError = error.localizedDescription
            logger.error("Purchase failed: \(error.localizedDescription)")
            throw error
        }
    }
    
    // MARK: - Restore Purchases
    
    /// 恢复购买
    func restorePurchases() async {
        isLoading = true
        purchaseError = nil
        
        defer { isLoading = false }
        
        logger.info("Restoring purchases...")
        
        // 同步所有未完成的交易
        do {
            try await AppStore.sync()
            await refreshEntitlementState()
            NotificationCenter.default.post(name: .subscriptionStatusChanged, object: nil)
            logger.info("Purchases restored successfully")
        } catch {
            logger.error("Failed to sync with App Store: \(error.localizedDescription)")
            purchaseError = "恢复购买失败: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Feature Access Checks
    
    /// 检查是否可以使用 AI 功能
    func canUseAIFeature(_ feature: AIFeature) -> Bool {
        return usageTracker.canUse(feature, tier: currentTier)
    }
    
    /// 记录 AI 功能使用
    func recordAIUsage(_ feature: AIFeature) {
        usageTracker.recordUsage(feature)
    }
    
    /// 检查是否可以创建笔记本
    func canCreateNotebook(currentCount: Int) -> Bool {
        return currentCount < featureFlags.maxNotebooks
    }
    
    /// 检查是否可以使用云同步
    func canUseSync() -> Bool {
        return featureFlags.canSync
    }
    
    // MARK: - Subscription Info
    
    /// 获取产品（按等级和周期）
    func product(tier: SubscriptionTier, yearly: Bool) -> Product? {
        let targetId: String
        switch (tier, yearly) {
        case (.pro, true): targetId = SubscriptionProductID.proYearly
        case (.pro, false): targetId = SubscriptionProductID.proMonthly
        case (.standard, true): targetId = SubscriptionProductID.standardYearly
        case (.standard, false): targetId = SubscriptionProductID.standardMonthly
        default: return nil
        }
        return products.first { $0.id == targetId }
    }
    
    /// 获取专业版产品
    var proProducts: [Product] {
        products.filter { SubscriptionProductID.tier(for: $0.id) == .pro }
    }
    
    /// 获取标准版产品
    var standardProducts: [Product] {
        products.filter { SubscriptionProductID.tier(for: $0.id) == .standard }
    }
    
    /// 计算年度订阅节省的百分比
    func yearlySavingsPercentage(for tier: SubscriptionTier) -> Int {
        guard let yearly = product(tier: tier, yearly: true),
              let monthly = product(tier: tier, yearly: false) else {
            return 0
        }
        
        let yearlyPrice = yearly.price
        let monthlyAnnual = monthly.price * 12
        
        if monthlyAnnual > 0 {
            let savings = (monthlyAnnual - yearlyPrice) / monthlyAnnual * 100
            return NSDecimalNumber(decimal: savings).intValue
        }
        return 0
    }
    
    // MARK: - Debug

    #if DEBUG
    /// 设置订阅等级（仅用于测试）
    func debugSetTier(_ tier: SubscriptionTier) {
        applyDebugTierOverride(tier)
    }

    private func applyDebugTierOverride(_ tier: SubscriptionTier) {
        debugTierOverride = tier
        self.currentTier = tier
        let expiration = Date().addingTimeInterval(86400 * 30)
        self.expirationDate = expiration
        self.currentProductId = tier == .pro ? SubscriptionProductID.proYearly : nil
        entitlementCache.cacheTier(tier, expiration: expiration)
    }
    #endif
}
