//
//  SubscriptionTypes.swift
//  NoteLab
//
//  订阅系统核心类型定义
//

import Foundation

// MARK: - Subscription Tier

/// 订阅等级枚举
enum SubscriptionTier: Int, Comparable, Codable, CaseIterable {
    case free = 0
    case standard = 1
    case pro = 2

    static func < (lhs: SubscriptionTier, rhs: SubscriptionTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var displayName: String {
        switch self {
        case .free: return "免费版"
        case .standard: return "标准版"
        case .pro: return "专业版"
        }
    }
    
    var shortName: String {
        switch self {
        case .free: return "Free"
        case .standard: return "Standard"
        case .pro: return "Pro"
        }
    }
}

// MARK: - Product IDs

/// 产品 ID 常量
enum SubscriptionProductID {
    static let proMonthly = "com.notelab.pro.monthly"
    static let proYearly = "com.notelab.pro.yearly"
    static let standardMonthly = "com.notelab.standard.monthly"
    static let standardYearly = "com.notelab.standard.yearly"
    
    static let allProductIds: Set<String> = [
        proMonthly,
        proYearly,
        standardMonthly,
        standardYearly
    ]
    
    static func tier(for productId: String) -> SubscriptionTier {
        switch productId {
        case proMonthly, proYearly:
            return .pro
        case standardMonthly, standardYearly:
            return .standard
        default:
            return .free
        }
    }

    static func activeTier(
        for productId: String,
        expiration: Date?,
        revocationDate: Date?,
        now: Date = Date()
    ) -> SubscriptionTier {
        guard revocationDate == nil else {
            return .free
        }

        if let expiration, expiration < now {
            return .free
        }

        return tier(for: productId)
    }
    
    static func isYearly(_ productId: String) -> Bool {
        productId.contains("yearly")
    }
}

// MARK: - Usage Limit

/// 用量限制类型
enum UsageLimit: Equatable {
    case unlimited
    case limited(Int)
    case disabled
    
    var value: Int {
        switch self {
        case .unlimited: return Int.max
        case .limited(let v): return v
        case .disabled: return 0
        }
    }
    
    var isAvailable: Bool {
        switch self {
        case .disabled: return false
        default: return true
        }
    }
    
    var displayText: String {
        switch self {
        case .unlimited: return "无限"
        case .limited(let v): return "\(v)次/月"
        case .disabled: return "不可用"
        }
    }
}

// MARK: - AI Feature

/// AI 功能枚举
enum AIFeature: String, CaseIterable, Codable {
    case organize = "ai.organize"
    case extractTasks = "ai.extractTasks"
    case rewrite = "ai.rewrite"
    case highlight = "ai.highlight"
    case recentFocus = "ai.recentFocus"
    case semanticConnections = "ai.semanticConnections"
    case plan = "ai.plan"
    
    var displayName: String {
        switch self {
        case .organize: return "笔记整理"
        case .extractTasks: return "任务提取"
        case .rewrite: return "笔记重写"
        case .highlight: return "智能高亮"
        case .recentFocus: return "最近重点"
        case .semanticConnections: return "语义关联"
        case .plan: return "AI 计划"
        }
    }

    var creditCost: Int {
        switch self {
        case .highlight:
            return 2
        case .extractTasks:
            return 3
        case .organize, .plan:
            return 6
        case .rewrite:
            return 8
        case .semanticConnections:
            return 10
        case .recentFocus:
            return 12
        }
    }

    func isAvailable(for tier: SubscriptionTier) -> Bool {
        switch (self, tier) {
        case (.organize, _), (.extractTasks, _):
            return true
        case (.rewrite, .free), (.highlight, .free), (.recentFocus, .free), (.semanticConnections, .free), (.plan, .free):
            return false
        case (.semanticConnections, .standard):
            return false
        default:
            return true
        }
    }

    /// 根据订阅等级返回按点数折算后的可用次数
    func limit(for tier: SubscriptionTier) -> UsageLimit {
        guard isAvailable(for: tier) else { return .disabled }
        return .limited(SubscriptionTier.monthlyAICredits(for: tier) / creditCost)
    }
}

extension SubscriptionTier {
    static func monthlyAICredits(for tier: SubscriptionTier) -> Int {
        switch tier {
        case .free: return 12
        case .standard: return 180
        case .pro: return 900
        }
    }

    var monthlyAICredits: Int {
        Self.monthlyAICredits(for: self)
    }
}

// MARK: - Feature Flags

/// 功能开关，根据订阅等级确定可用功能
struct FeatureFlags {
    let tier: SubscriptionTier
    
    init(tier: SubscriptionTier) {
        self.tier = tier
    }
    
    /// 最大笔记本数量
    var maxNotebooks: Int {
        switch tier {
        case .free: return 3
        case .standard, .pro: return Int.max
        }
    }
    
    /// 是否可以使用云同步
    var canSync: Bool {
        true
    }
    
    /// 附件云存储限制 (bytes)
    var attachmentStorageLimit: Int64 {
        switch tier {
        case .free: return 0 // 仅本地
        case .standard: return 500 * 1024 * 1024 // 500MB
        case .pro: return 5 * 1024 * 1024 * 1024 // 5GB
        }
    }
    
    /// 附件存储限制显示文本
    var attachmentStorageLimitText: String {
        switch tier {
        case .free: return "仅本地"
        case .standard: return "500MB"
        case .pro: return "5GB"
        }
    }
    
    /// 是否可以使用 Face ID 锁定
    var canUseFaceIDLock: Bool {
        tier >= .pro
    }
    
    /// PDF 导出是否有水印
    var pdfExportHasWatermark: Bool {
        tier < .standard
    }
    
    /// 是否可以使用语义关联功能
    var canUseSemanticConnections: Bool {
        tier >= .pro
    }
    
    /// 是否可以使用多设备同步
    var canUseMultiDevice: Bool {
        tier >= .standard
    }
}

// MARK: - Subscription Error

/// 订阅相关错误
enum SubscriptionError: LocalizedError {
    case verificationFailed
    case purchasePending
    case purchaseCancelled
    case productNotFound
    case quotaExceeded(feature: AIFeature, remaining: Int)
    case featureNotAvailable(feature: AIFeature)
    case notebookLimitReached(limit: Int)
    case syncNotAvailable
    case unknown
    
    var errorDescription: String? {
        switch self {
        case .verificationFailed:
            return "购买验证失败，请重试"
        case .purchasePending:
            return "购买正在处理中，请稍后查看"
        case .purchaseCancelled:
            return "购买已取消"
        case .productNotFound:
            return "未找到订阅产品"
        case .quotaExceeded(let feature, let remaining):
            return "\(feature.displayName)本月点数不足，剩余 \(remaining) 点"
        case .featureNotAvailable(let feature):
            return "\(feature.displayName)为付费功能，请升级订阅"
        case .notebookLimitReached(let limit):
            return "已达到笔记本数量上限(\(limit)个)，请升级订阅"
        case .syncNotAvailable:
            return "云同步为付费功能，请升级订阅"
        case .unknown:
            return "发生未知错误"
        }
    }
}

// MARK: - Paywall Trigger

/// 付费墙触发来源
enum PaywallTrigger: String {
    case notebookLimit = "notebook_limit"
    case syncAttempt = "sync_attempt"
    case aiQuotaExceeded = "ai_quota_exceeded"
    case aiFeatureDisabled = "ai_feature_disabled"
    case faceIDLock = "face_id_lock"
    case settings = "settings"
    case manual = "manual"
    
    var analyticsName: String {
        rawValue
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// 显示付费墙通知
    static let showPaywall = Notification.Name("showPaywall")
    /// 订阅状态变更通知
    static let subscriptionStatusChanged = Notification.Name("subscriptionStatusChanged")
    /// CloudKit 静默推送触发同步
    static let cloudKitRemoteNotification = Notification.Name("cloudKitRemoteNotification")
}
