//
//  UsageTracker.swift
//  NoteLab
//
//  AI 功能用量追踪器，支持月度自动重置
//

import Foundation
import Combine

/// AI 功能用量追踪器
final class UsageTracker: ObservableObject {
    
    // MARK: - Storage Keys
    
    private let defaults = UserDefaults.standard
    private let lastResetDateKey = "usage.lastResetDate"
    private let usagePrefix = "usage.count."
    
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
        let limit = feature.limit(for: tier)
        
        switch limit {
        case .unlimited:
            return true
        case .disabled:
            return false
        case .limited(let max):
            let currentUsage = usageCounts[feature] ?? 0
            return currentUsage < max
        }
    }
    
    /// 记录一次功能使用
    func recordUsage(_ feature: AIFeature) {
        let current = usageCounts[feature] ?? 0
        usageCounts[feature] = current + 1
        saveUsageCount(feature: feature, count: current + 1)
    }
    
    /// 获取剩余使用次数
    func remainingUsage(_ feature: AIFeature, tier: SubscriptionTier) -> UsageLimit {
        let limit = feature.limit(for: tier)
        
        switch limit {
        case .unlimited:
            return .unlimited
        case .disabled:
            return .disabled
        case .limited(let max):
            let used = usageCounts[feature] ?? 0
            let remaining = Swift.max(0, max - used)
            return .limited(remaining)
        }
    }
    
    /// 获取已使用次数
    func usedCount(_ feature: AIFeature) -> Int {
        return usageCounts[feature] ?? 0
    }
    
    /// 获取用量百分比 (0.0 - 1.0)
    func usagePercentage(_ feature: AIFeature, tier: SubscriptionTier) -> Double {
        let limit = feature.limit(for: tier)
        
        switch limit {
        case .unlimited:
            return 0.0
        case .disabled:
            return 1.0
        case .limited(let max):
            let used = usageCounts[feature] ?? 0
            return min(1.0, Double(used) / Double(max))
        }
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
