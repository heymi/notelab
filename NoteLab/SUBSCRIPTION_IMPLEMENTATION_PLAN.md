# NoteLab 订阅系统完整技术方案

## 一、架构概览

```
┌─────────────────────────────────────────────────────────────────┐
│                        UI Layer                                  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │
│  │ PaywallView │  │ SettingsView│  │ Feature-gated Views     │  │
│  └──────┬──────┘  └──────┬──────┘  └───────────┬─────────────┘  │
└─────────┼────────────────┼─────────────────────┼────────────────┘
          │                │                     │
          ▼                ▼                     ▼
┌─────────────────────────────────────────────────────────────────┐
│                   SubscriptionManager                            │
│  ┌─────────────────┐  ┌──────────────┐  ┌──────────────────┐   │
│  │ entitlementState│  │ usageTracker │  │ featureFlags     │   │
│  │ (Published)     │  │ (AI quotas)  │  │ (tier-based)     │   │
│  └────────┬────────┘  └──────┬───────┘  └────────┬─────────┘   │
└───────────┼──────────────────┼───────────────────┼──────────────┘
            │                  │                   │
            ▼                  ▼                   ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Data Layer                                  │
│  ┌─────────────────┐  ┌──────────────┐  ┌──────────────────┐   │
│  │ StoreKit 2      │  │ UserDefaults │  │ Keychain         │   │
│  │ (Transactions)  │  │ (Usage Cache)│  │ (Entitlement)    │   │
│  └─────────────────┘  └──────────────┘  └──────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

## 二、订阅产品设计

### 2.1 产品 ID 定义

| 产品 ID | 类型 | 价格 | 说明 |
|---------|------|------|------|
| `com.notelab.pro.monthly` | 自动续订订阅 | ¥12/月 | 专业版月度订阅 |
| `com.notelab.pro.yearly` | 自动续订订阅 | ¥98/年 | 专业版年度订阅 (节省17%) |
| `com.notelab.standard.monthly` | 自动续订订阅 | ¥6/月 | 标准版月度订阅 |
| `com.notelab.standard.yearly` | 自动续订订阅 | ¥48/年 | 标准版年度订阅 |

### 2.2 订阅等级 (Subscription Tier)

```swift
enum SubscriptionTier: Int, Comparable, Codable {
    case free = 0
    case standard = 1
    case pro = 2
    
    static func < (lhs: SubscriptionTier, rhs: SubscriptionTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
```

### 2.3 功能矩阵

| 功能 | Free | Standard | Pro |
|------|------|----------|-----|
| 笔记本数量 | 3 | ∞ | ∞ |
| 云同步 | ✗ | ✓ | ✓ |
| 多设备 | ✗ | ✓ | ✓ |
| 附件存储 | 本地 | 500MB | 5GB |
| AI 笔记整理 | 3次/月 | 15次/月 | ∞ |
| AI 任务提取 | 3次/月 | 15次/月 | ∞ |
| AI 笔记重写 | ✗ | 10次/月 | ∞ |
| AI 高亮补充 | ✗ | 10次/月 | ∞ |
| 最近重点报告 | ✗ | 1次/周 | 每日 |
| 语义关联发现 | ✗ | ✗ | ✓ |
| Face ID 锁定 | ✗ | ✗ | ✓ |
| PDF 导出 | 水印 | ✓ | ✓ |

## 三、核心文件结构

```
NoteLab/
├── Subscription/
│   ├── SubscriptionManager.swift      # 核心订阅管理器
│   ├── SubscriptionTier.swift         # 订阅等级枚举
│   ├── SubscriptionProduct.swift      # 产品定义
│   ├── UsageTracker.swift             # AI 用量追踪
│   ├── FeatureFlags.swift             # 功能开关
│   ├── EntitlementCache.swift         # 权益缓存 (Keychain)
│   └── StoreKitError+Extension.swift  # 错误处理扩展
├── Paywall/
│   ├── PaywallView.swift              # 付费墙主视图
│   ├── PaywallFeatureRow.swift        # 功能行组件
│   ├── SubscriptionOptionCard.swift   # 订阅选项卡片
│   └── PaywallViewModel.swift         # 付费墙 ViewModel
└── Configuration/
    └── Products.storekit              # StoreKit 配置文件
```

## 四、SubscriptionManager 详细设计

### 4.1 核心属性

```swift
@MainActor
final class SubscriptionManager: ObservableObject {
    // MARK: - Singleton
    static let shared = SubscriptionManager()
    
    // MARK: - Published State
    @Published private(set) var currentTier: SubscriptionTier = .free
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var products: [Product] = []
    @Published private(set) var purchaseError: String?
    @Published private(set) var expirationDate: Date?
    
    // MARK: - Internal State
    private var updateListenerTask: Task<Void, Never>?
    private let productIds: Set<String> = [
        "com.notelab.pro.monthly",
        "com.notelab.pro.yearly",
        "com.notelab.standard.monthly",
        "com.notelab.standard.yearly"
    ]
    
    // MARK: - Dependencies
    private let usageTracker: UsageTracker
    private let entitlementCache: EntitlementCache
}
```

### 4.2 初始化与监听

```swift
private init() {
    self.usageTracker = UsageTracker()
    self.entitlementCache = EntitlementCache()
    
    // 启动时从缓存恢复状态
    self.currentTier = entitlementCache.cachedTier
    
    // 启动交易监听
    updateListenerTask = listenForTransactionUpdates()
    
    // 异步验证当前权益
    Task {
        await refreshEntitlementState()
    }
}

private func listenForTransactionUpdates() -> Task<Void, Never> {
    Task.detached {
        for await result in Transaction.updates {
            await self.handleTransactionUpdate(result)
        }
    }
}
```

### 4.3 权益状态刷新 (关键方法)

```swift
func refreshEntitlementState() async {
    // 遍历 currentEntitlements 确定最高权益
    var highestTier: SubscriptionTier = .free
    var latestExpiration: Date?
    
    for await result in Transaction.currentEntitlements {
        guard case .verified(let transaction) = result else { continue }
        
        // 检查是否已撤销或过期
        if let revocationDate = transaction.revocationDate {
            continue // 已撤销，跳过
        }
        
        if let expirationDate = transaction.expirationDate,
           expirationDate < Date() {
            continue // 已过期，跳过
        }
        
        // 根据产品 ID 确定等级
        let tier = tierFromProductId(transaction.productID)
        if tier > highestTier {
            highestTier = tier
            latestExpiration = transaction.expirationDate
        }
    }
    
    // 更新状态
    await MainActor.run {
        self.currentTier = highestTier
        self.expirationDate = latestExpiration
        self.entitlementCache.cacheTier(highestTier, expiration: latestExpiration)
    }
}
```

### 4.4 购买流程

```swift
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
            
            // 完成交易
            await transaction.finish()
            
            // 刷新权益状态
            await refreshEntitlementState()
            
            return transaction
            
        case .userCancelled:
            return nil
            
        case .pending:
            // 等待家长批准或其他
            throw SubscriptionError.purchasePending
            
        @unknown default:
            throw SubscriptionError.unknown
        }
    } catch {
        purchaseError = error.localizedDescription
        throw error
    }
}
```

### 4.5 恢复购买

```swift
func restorePurchases() async {
    isLoading = true
    defer { isLoading = false }
    
    // StoreKit 2 会自动同步，只需刷新权益
    await refreshEntitlementState()
}
```

## 五、UsageTracker 用量追踪

### 5.1 设计原则

- **本地优先**: 用量数据存储在 UserDefaults，无需网络
- **月度重置**: 每月 1 日自动重置配额
- **防篡改**: 使用加密签名验证数据完整性

### 5.2 实现

```swift
final class UsageTracker {
    private let defaults = UserDefaults.standard
    
    // 用量 Key
    private let aiOrganizeKey = "usage.ai.organize"
    private let aiExtractTasksKey = "usage.ai.extractTasks"
    private let aiRewriteKey = "usage.ai.rewrite"
    private let aiHighlightKey = "usage.ai.highlight"
    private let lastResetDateKey = "usage.lastResetDate"
    
    init() {
        checkAndResetIfNeeded()
    }
    
    // MARK: - Public API
    
    func canUse(_ feature: AIFeature, tier: SubscriptionTier) -> Bool {
        let limit = feature.limit(for: tier)
        guard limit != .unlimited else { return true }
        
        let currentUsage = getUsage(for: feature)
        return currentUsage < limit.value
    }
    
    func recordUsage(_ feature: AIFeature) {
        let key = storageKey(for: feature)
        let current = defaults.integer(forKey: key)
        defaults.set(current + 1, forKey: key)
    }
    
    func remainingUsage(_ feature: AIFeature, tier: SubscriptionTier) -> UsageLimit {
        let limit = feature.limit(for: tier)
        guard case .limited(let max) = limit else { return .unlimited }
        
        let used = getUsage(for: feature)
        return .limited(max(0, max - used))
    }
    
    // MARK: - Monthly Reset
    
    private func checkAndResetIfNeeded() {
        let calendar = Calendar.current
        let now = Date()
        
        if let lastReset = defaults.object(forKey: lastResetDateKey) as? Date {
            let lastMonth = calendar.component(.month, from: lastReset)
            let currentMonth = calendar.component(.month, from: now)
            
            if lastMonth != currentMonth {
                resetAllUsage()
            }
        } else {
            defaults.set(now, forKey: lastResetDateKey)
        }
    }
    
    private func resetAllUsage() {
        defaults.set(0, forKey: aiOrganizeKey)
        defaults.set(0, forKey: aiExtractTasksKey)
        defaults.set(0, forKey: aiRewriteKey)
        defaults.set(0, forKey: aiHighlightKey)
        defaults.set(Date(), forKey: lastResetDateKey)
    }
}
```

### 5.3 用量限制定义

```swift
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
}

enum AIFeature: String, CaseIterable {
    case organize
    case extractTasks
    case rewrite
    case highlight
    case recentFocus
    case semanticConnections
    
    func limit(for tier: SubscriptionTier) -> UsageLimit {
        switch (self, tier) {
        // organize
        case (.organize, .free): return .limited(3)
        case (.organize, .standard): return .limited(15)
        case (.organize, .pro): return .unlimited
        
        // extractTasks
        case (.extractTasks, .free): return .limited(3)
        case (.extractTasks, .standard): return .limited(15)
        case (.extractTasks, .pro): return .unlimited
        
        // rewrite
        case (.rewrite, .free): return .disabled
        case (.rewrite, .standard): return .limited(10)
        case (.rewrite, .pro): return .unlimited
        
        // highlight
        case (.highlight, .free): return .disabled
        case (.highlight, .standard): return .limited(10)
        case (.highlight, .pro): return .unlimited
        
        // recentFocus
        case (.recentFocus, .free): return .disabled
        case (.recentFocus, .standard): return .limited(4) // 每周1次
        case (.recentFocus, .pro): return .unlimited
        
        // semanticConnections
        case (.semanticConnections, .free): return .disabled
        case (.semanticConnections, .standard): return .disabled
        case (.semanticConnections, .pro): return .unlimited
        }
    }
}
```

## 六、FeatureFlags 功能开关

```swift
struct FeatureFlags {
    let tier: SubscriptionTier
    
    // 笔记本限制
    var maxNotebooks: Int {
        switch tier {
        case .free: return 3
        case .standard, .pro: return Int.max
        }
    }
    
    // 云同步
    var canSync: Bool {
        tier >= .standard
    }
    
    // 附件存储限制 (bytes)
    var attachmentStorageLimit: Int64 {
        switch tier {
        case .free: return 0 // 仅本地
        case .standard: return 500 * 1024 * 1024 // 500MB
        case .pro: return 5 * 1024 * 1024 * 1024 // 5GB
        }
    }
    
    // Face ID 锁定
    var canUseFaceIDLock: Bool {
        tier >= .pro
    }
    
    // PDF 导出
    var pdfExportHasWatermark: Bool {
        tier < .standard
    }
    
    // AI 语义关联
    var canUseSemanticConnections: Bool {
        tier >= .pro
    }
}
```

## 七、EntitlementCache 权益缓存

### 7.1 安全存储 (Keychain)

```swift
import Security

final class EntitlementCache {
    private let service = "com.notelab.entitlement"
    private let tierKey = "subscription.tier"
    private let expirationKey = "subscription.expiration"
    
    var cachedTier: SubscriptionTier {
        guard let data = readKeychain(key: tierKey),
              let rawValue = String(data: data, encoding: .utf8),
              let intValue = Int(rawValue),
              let tier = SubscriptionTier(rawValue: intValue) else {
            return .free
        }
        
        // 检查是否过期
        if let expData = readKeychain(key: expirationKey),
           let expString = String(data: expData, encoding: .utf8),
           let expInterval = TimeInterval(expString) {
            let expDate = Date(timeIntervalSince1970: expInterval)
            if expDate < Date() {
                return .free // 已过期
            }
        }
        
        return tier
    }
    
    func cacheTier(_ tier: SubscriptionTier, expiration: Date?) {
        let tierData = String(tier.rawValue).data(using: .utf8)!
        writeKeychain(key: tierKey, data: tierData)
        
        if let exp = expiration {
            let expData = String(exp.timeIntervalSince1970).data(using: .utf8)!
            writeKeychain(key: expirationKey, data: expData)
        }
    }
    
    // MARK: - Keychain Operations
    
    private func writeKeychain(key: String, data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        SecItemDelete(query as CFDictionary)
        
        var newQuery = query
        newQuery[kSecValueData as String] = data
        SecItemAdd(newQuery as CFDictionary, nil)
    }
    
    private func readKeychain(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        SecItemCopyMatching(query as CFDictionary, &result)
        return result as? Data
    }
}
```

## 八、PaywallView 付费墙 UI

### 8.1 设计规范

- 遵循 Apple Human Interface Guidelines
- 清晰展示功能对比
- 支持年度/月度切换
- 显示节省金额
- 提供恢复购买入口

### 8.2 视图结构

```swift
struct PaywallView: View {
    @StateObject private var viewModel = PaywallViewModel()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
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
            .padding()
        }
        .background(Theme.background)
        .task {
            await viewModel.loadProducts()
        }
    }
}
```

## 九、功能限制集成点

### 9.1 笔记本创建限制

```swift
// NotebookStore.swift
func addNotebook(title: String, color: NotebookColor, iconName: String) -> UUID? {
    let flags = FeatureFlags(tier: SubscriptionManager.shared.currentTier)
    
    guard notebooks.count < flags.maxNotebooks else {
        // 触发付费墙
        NotificationCenter.default.post(
            name: .showPaywall,
            object: PaywallTrigger.notebookLimit
        )
        return nil
    }
    
    // ... 原有创建逻辑
}
```

### 9.2 云同步限制

```swift
// SyncEngine.swift
func syncNow() async {
    let flags = FeatureFlags(tier: SubscriptionManager.shared.currentTier)
    
    guard flags.canSync else {
        await MainActor.run {
            self.lastError = "云同步为付费功能，请升级订阅"
        }
        return
    }
    
    // ... 原有同步逻辑
}
```

### 9.3 AI 功能限制

```swift
// AIProcessingCenter.swift
func processOrganize(note: Note) async throws -> AIResult {
    let manager = SubscriptionManager.shared
    let tracker = manager.usageTracker
    
    guard tracker.canUse(.organize, tier: manager.currentTier) else {
        throw AIError.quotaExceeded(
            feature: .organize,
            remaining: tracker.remainingUsage(.organize, tier: manager.currentTier)
        )
    }
    
    // ... 原有处理逻辑
    
    // 成功后记录用量
    tracker.recordUsage(.organize)
}
```

## 十、StoreKit 配置文件

### 10.1 Products.storekit

```json
{
  "identifier" : "Products",
  "nonRenewingSubscriptions" : [ ],
  "products" : [ ],
  "settings" : {
    "_applicationInternalID" : "6740000000",
    "_developerTeamID" : "XXXXXXXXXX"
  },
  "subscriptionGroups" : [
    {
      "id" : "notelab_premium",
      "localizations" : [
        {
          "description" : "NoteLab 高级订阅",
          "displayName" : "NoteLab Pro",
          "locale" : "zh_CN"
        }
      ],
      "name" : "NoteLab Premium",
      "subscriptions" : [
        {
          "adHocOffers" : [ ],
          "codeOffers" : [ ],
          "displayPrice" : "98",
          "familyShareable" : true,
          "groupNumber" : 1,
          "internalID" : "pro_yearly",
          "introductoryOffer" : {
            "internalID" : "pro_yearly_intro",
            "numberOfPeriods" : 1,
            "paymentMode" : "freeTrial",
            "subscriptionPeriod" : "P1W"
          },
          "localizations" : [
            {
              "description" : "解锁全部功能，无限 AI 助手",
              "displayName" : "专业版 · 年度",
              "locale" : "zh_CN"
            }
          ],
          "productID" : "com.notelab.pro.yearly",
          "recurringSubscriptionPeriod" : "P1Y",
          "referenceName" : "Pro Yearly",
          "subscriptionGroupID" : "notelab_premium",
          "type" : "RecurringSubscription"
        },
        {
          "adHocOffers" : [ ],
          "codeOffers" : [ ],
          "displayPrice" : "12",
          "familyShareable" : true,
          "groupNumber" : 1,
          "internalID" : "pro_monthly",
          "localizations" : [
            {
              "description" : "解锁全部功能，无限 AI 助手",
              "displayName" : "专业版 · 月度",
              "locale" : "zh_CN"
            }
          ],
          "productID" : "com.notelab.pro.monthly",
          "recurringSubscriptionPeriod" : "P1M",
          "referenceName" : "Pro Monthly",
          "subscriptionGroupID" : "notelab_premium",
          "type" : "RecurringSubscription"
        },
        {
          "adHocOffers" : [ ],
          "codeOffers" : [ ],
          "displayPrice" : "48",
          "familyShareable" : true,
          "groupNumber" : 2,
          "internalID" : "standard_yearly",
          "localizations" : [
            {
              "description" : "云同步，适量 AI 配额",
              "displayName" : "标准版 · 年度",
              "locale" : "zh_CN"
            }
          ],
          "productID" : "com.notelab.standard.yearly",
          "recurringSubscriptionPeriod" : "P1Y",
          "referenceName" : "Standard Yearly",
          "subscriptionGroupID" : "notelab_premium",
          "type" : "RecurringSubscription"
        },
        {
          "adHocOffers" : [ ],
          "codeOffers" : [ ],
          "displayPrice" : "6",
          "familyShareable" : true,
          "groupNumber" : 2,
          "internalID" : "standard_monthly",
          "localizations" : [
            {
              "description" : "云同步，适量 AI 配额",
              "displayName" : "标准版 · 月度",
              "locale" : "zh_CN"
            }
          ],
          "productID" : "com.notelab.standard.monthly",
          "recurringSubscriptionPeriod" : "P1M",
          "referenceName" : "Standard Monthly",
          "subscriptionGroupID" : "notelab_premium",
          "type" : "RecurringSubscription"
        }
      ]
    }
  ],
  "version" : {
    "major" : 3,
    "minor" : 0
  }
}
```

## 十一、安全考量

### 11.1 防止越狱绕过

```swift
// 检测越狱环境
private func isJailbroken() -> Bool {
    #if targetEnvironment(simulator)
    return false
    #else
    let paths = [
        "/Applications/Cydia.app",
        "/Library/MobileSubstrate/MobileSubstrate.dylib",
        "/bin/bash",
        "/usr/sbin/sshd",
        "/etc/apt",
        "/private/var/lib/apt/"
    ]
    
    for path in paths {
        if FileManager.default.fileExists(atPath: path) {
            return true
        }
    }
    
    // 尝试写入受保护路径
    let testPath = "/private/jailbreak_test.txt"
    do {
        try "test".write(toFile: testPath, atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(atPath: testPath)
        return true
    } catch {
        return false
    }
    #endif
}
```

### 11.2 交易验证

- 始终使用 `VerificationResult.verified` 检查
- 检查 `revocationDate` 和 `expirationDate`
- 权益缓存存储在 Keychain 而非 UserDefaults

### 11.3 服务端验证 (可选增强)

```swift
// 未来可扩展：服务端验证
func verifyWithServer(transaction: Transaction) async throws -> Bool {
    // 将 transaction.jsonRepresentation 发送到服务端
    // 服务端调用 App Store Server API 验证
    // 返回验证结果
    return true
}
```

## 十二、测试策略

### 12.1 StoreKit Testing in Xcode

1. 使用 `Products.storekit` 配置文件
2. 在 Scheme 中启用 StoreKit Testing
3. 测试各种购买场景

### 12.2 测试用例

| 场景 | 预期结果 |
|------|----------|
| 首次购买专业版年度 | currentTier = .pro |
| 订阅过期 | currentTier 降级 |
| 恢复购买 | 恢复之前的订阅等级 |
| 从标准升级到专业 | currentTier = .pro |
| 取消续订 | 到期前保持权益 |
| 退款 | 立即降级到 .free |
| AI 用量达到限制 | 显示付费墙 |
| 笔记本数量达到限制 | 显示付费墙 |

### 12.3 Sandbox 测试

- 使用 Sandbox 测试账号
- 验证各种订阅状态转换
- 测试家庭共享场景

## 十三、实施步骤

### Phase 1: 基础架构 (Day 1-2)
1. 创建 `Subscription/` 目录结构
2. 实现 `SubscriptionTier` 和 `FeatureFlags`
3. 实现 `EntitlementCache` (Keychain)
4. 实现 `UsageTracker`

### Phase 2: StoreKit 集成 (Day 3-4)
1. 创建 `Products.storekit` 配置
2. 实现 `SubscriptionManager` 核心逻辑
3. 实现购买和恢复购买流程
4. 添加交易监听

### Phase 3: UI 实现 (Day 5-6)
1. 实现 `PaywallView` 付费墙
2. 更新 `SettingsView` 订阅管理部分
3. 添加订阅状态指示器

### Phase 4: 功能门控 (Day 7-8)
1. 集成笔记本数量限制
2. 集成云同步限制
3. 集成 AI 功能限制
4. 添加付费墙触发点

### Phase 5: 测试与优化 (Day 9-10)
1. StoreKit Testing
2. Sandbox 测试
3. 边界条件测试
4. 性能优化

## 十四、App Store 审核注意事项

1. **明确展示价格和订阅周期**
2. **提供恢复购买功能**
3. **包含订阅条款和隐私政策链接**
4. **确保免费功能可用**（审核员可能不购买）
5. **处理购买失败的优雅降级**

## 十五、维护与监控

### 15.1 日志记录

```swift
private let logger = Logger(subsystem: "NoteLab", category: "Subscription")

// 记录关键事件
logger.info("Purchase completed: \(productId)")
logger.warning("Verification failed for transaction: \(transactionId)")
logger.error("Purchase error: \(error.localizedDescription)")
```

### 15.2 分析事件

- 付费墙展示次数
- 购买转化率
- 订阅流失率
- AI 功能使用频率

---

## 附录：关键 API 参考

- [StoreKit 2 Documentation](https://developer.apple.com/documentation/storekit)
- [Transaction.currentEntitlements](https://developer.apple.com/documentation/storekit/transaction/currententitlements)
- [Product.SubscriptionInfo](https://developer.apple.com/documentation/storekit/product/subscriptioninfo)
- [App Store Server API](https://developer.apple.com/documentation/appstoreserverapi)
