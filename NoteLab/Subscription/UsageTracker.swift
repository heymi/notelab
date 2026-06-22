//
//  UsageTracker.swift
//  NoteLab
//
//  AI 功能点数追踪器，支持月度自动重置
//

import Foundation
import Combine

/// AI 功能点数追踪器
final class UsageTracker: ObservableObject {
    
    // MARK: - Storage Keys
    
    private let defaults = UserDefaults.standard
    private let lastResetDateKey = "usage.lastResetDate"
    private let usagePrefix = "usage.credits."
    
    // MARK: - Published State
    
    @Published private(set) var usageCounts: [AIFeature: Int] = [:]
    
    // MARK: - Singleton
    
    static let shared = UsageTracker()
    
    private init() {
        loadUsageCounts()
        checkAndResetIfNeeded()
    }
    
    // MARK: - Public API
    
    /// 检查是否可以使用某个功能
    func canUse(_ feature: AIFeature, tier: SubscriptionTier) -> Bool {
        feature.isAvailable(for: tier) && remainingCredits(tier: tier) >= feature.creditCost
    }
    
    /// 记录一次功能使用
    func recordUsage(_ feature: AIFeature) {
        let current = usageCounts[feature] ?? 0
        let next = current + feature.creditCost
        usageCounts[feature] = next
        saveUsageCount(feature: feature, count: next)
    }
    
    /// 获取剩余可用次数（由点数折算）
    func remainingUsage(_ feature: AIFeature, tier: SubscriptionTier) -> UsageLimit {
        guard feature.isAvailable(for: tier) else { return .disabled }
        return .limited(remainingCredits(tier: tier) / feature.creditCost)
    }
    
    /// 获取功能已消耗点数
    func usedCount(_ feature: AIFeature) -> Int {
        return usageCounts[feature] ?? 0
    }

    func monthlyAllowance(tier: SubscriptionTier) -> Int {
        tier.monthlyAICredits
    }

    func usedCredits() -> Int {
        usageCounts.values.reduce(0, +)
    }

    func remainingCredits(tier: SubscriptionTier) -> Int {
        Swift.max(0, monthlyAllowance(tier: tier) - usedCredits())
    }
    
    /// 获取用量百分比 (0.0 - 1.0)
    func usagePercentage(_ feature: AIFeature, tier: SubscriptionTier) -> Double {
        guard feature.isAvailable(for: tier) else { return 1.0 }
        let max = monthlyAllowance(tier: tier)
        guard max > 0 else { return 1.0 }
        return min(1.0, Double(usedCredits()) / Double(max))
    }
    
    /// 获取下次重置日期
    var nextResetDate: Date {
        let calendar = Calendar.current
        let now = Date()
        
        // 下个月1日
        var components = calendar.dateComponents([.year, .month], from: now)
        components.month! += 1
        components.day = 1
        components.hour = 0
        components.minute = 0
        components.second = 0
        
        return calendar.date(from: components) ?? now
    }
    
    /// 距离下次重置的天数
    var daysUntilReset: Int {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: Date(), to: nextResetDate).day ?? 0
        return max(0, days)
    }
    
    // MARK: - Monthly Reset
    
    private func checkAndResetIfNeeded() {
        let calendar = Calendar.current
        let now = Date()
        
        if let lastReset = defaults.object(forKey: lastResetDateKey) as? Date {
            let lastMonth = calendar.component(.month, from: lastReset)
            let lastYear = calendar.component(.year, from: lastReset)
            let currentMonth = calendar.component(.month, from: now)
            let currentYear = calendar.component(.year, from: now)
            
            // 如果月份或年份不同，重置配额
            if lastMonth != currentMonth || lastYear != currentYear {
                resetAllUsage()
            }
        } else {
            // 首次运行，设置重置日期
            defaults.set(now, forKey: lastResetDateKey)
        }
    }
    
    private func resetAllUsage() {
        // 清除所有计数
        for feature in AIFeature.allCases {
            let key = usagePrefix + feature.rawValue
            defaults.removeObject(forKey: key)
        }
        
        // 更新重置日期
        defaults.set(Date(), forKey: lastResetDateKey)
        
        // 更新内存中的计数
        usageCounts = [:]
        
        print("UsageTracker: Monthly usage reset completed")
    }
    
    // MARK: - Persistence
    
    private func loadUsageCounts() {
        var counts: [AIFeature: Int] = [:]
        
        for feature in AIFeature.allCases {
            let key = usagePrefix + feature.rawValue
            let count = defaults.integer(forKey: key)
            if count > 0 {
                counts[feature] = count
            }
        }
        
        usageCounts = counts
    }
    
    private func saveUsageCount(feature: AIFeature, count: Int) {
        let key = usagePrefix + feature.rawValue
        defaults.set(count, forKey: key)
    }
    
    // MARK: - Debug
    
    #if DEBUG
    /// 重置所有用量（仅用于测试）
    func debugResetAllUsage() {
        resetAllUsage()
    }
    
    /// 设置用量（仅用于测试）
    func debugSetUsage(_ feature: AIFeature, count: Int) {
        usageCounts[feature] = count
        saveUsageCount(feature: feature, count: count)
    }
    #endif
}
