# CloudKit 初始化修复 & 调试配置

> 2026-06-17 — feature/subscription-system 分支

## 一、真机卡"初始化本地服务环境"根因

### 问题
真机调试时 App 启动后一直停在 loading 画面（`ProgressView` + "正在初始化本地数据…"），模拟器正常。

### 根因：SwiftData 自动启用 CloudKit 导致 schema 冲突

调用链：
```
ContentView.initializeWithTimeout()
  → PersistenceController.makeContainer()
    → ModelConfiguration(schema:url:)
      → cloudKitDatabase 默认 = .automatic
        → 检测到 entitlements 有 CloudKit → 自动启用 SwiftData CloudKit
          → schema 不兼容 CloudKit → NSCocoaError 134060 → 创建失败
```

**错误信息**：
```
CloudKit integration requires that all attributes be optional, or have a default value set.
CloudKit integration requires that all relationships be optional.
  LocalNotebook: notes — is NOT optional
CloudKit integration does not support unique constraints.
  LocalAttachment: id / LocalNote: id / LocalNotebook: id / SyncMetadata: key
```

schema 有三类 CloudKit 不兼容：
- `@Attribute(.unique)` 约束（4 个实体）
- 非 optional 属性（如 `createdAt`、`title` 等）
- 非 optional 关系（`LocalNotebook.notes: [LocalNote]`）

### 为什么模拟器不报错？
模拟器没有 CloudKit daemon，`ModelConfiguration` 的 `.automatic` 检测不到 CloudKit 环境，不会尝试启用 SwiftData CloudKit，所以 store 能正常创建。

### 修复

**文件**：`NoteLab/Persistence/PersistenceController.swift`

在 `ModelConfiguration` 初始化时显式禁用 CloudKit：

```swift
// 文件 store
let configuration = ModelConfiguration(
    schema: schema,
    url: storeURL,
    cloudKitDatabase: .none   // ← 关键：禁用 SwiftData 自动 CloudKit
)

// 内存 store
let configuration = ModelConfiguration(
    schema: schema,
    isStoredInMemoryOnly: true,
    cloudKitDatabase: .none
)
```

**注意**：App 的 CloudKit entitlement 保留给 `SyncEngine` 直调 `CKDatabase` API 使用。SwiftData 层面不再自动启用 CloudKit 是因为 App 使用手动 CKDatabase 同步，不依赖 `NSPersistentCloudKitContainer`。

### 其他改动

| 改动 | 文件 | 说明 |
|------|------|------|
| store 文件名 `NoteLabCloudKitV1.store` → `NoteLabV2.store` | PersistenceController | 避免 iCloud daemon 对旧 CloudKit 标记文件持有 coordinator lock |
| `resetStore()` 错误处理加强 | PersistenceController | `try?` → `try` + os.Logger 记录失败原因 |
| 15s 超时保护 | ContentView | `TaskGroup` 包装初始化，超时后降级到 in-memory fallback |
| 诊断日志 | ContentView + PersistenceController | `Logger(subsystem: "NoteLab", category: "Init"|"Persistence")` |
| `.onChange(of: auth.userId)` 加 guard | ContentView | 防止初始渲染时误清 `modelContainer` |

## 二、调试 Pro 用户配置

### 实现

**文件**：`NoteLab/NoteLabApp.swift`

```swift
ContentView()
    .onAppear {
        #if DEBUG
        SubscriptionManager.shared.debugSetTier(.pro)
        #endif
    }
```

**文件**：`NoteLab/Subscription/SubscriptionManager.swift`

```swift
#if DEBUG
private var debugTierOverride: SubscriptionTier?

func debugSetTier(_ tier: SubscriptionTier) {
    debugTierOverride = tier
    self.currentTier = tier
    entitlementCache.cacheTier(tier, expiration: Date().addingTimeInterval(86400 * 30))
}
#endif
```

### 时序保护

`refreshEntitlementState()` 在 `for await Transaction.currentEntitlements` 循环**之后**检查 `debugTierOverride` flag。因为 `@MainActor` 保证串行执行——`debugSetTier` 可能在循环被 await 挂起期间运行，循环结束后检查就能捕获。

```swift
func refreshEntitlementState() async {
    // ... for await Transaction.currentEntitlements ...

    #if DEBUG
    if debugTierOverride != nil {
        return  // 不覆盖 debug 设置的 tier
    }
    #endif

    self.currentTier = highestTier
    // ...
}
```

## 三、CloudKit 同步当前状态

### 已实现

- 手动 CKDatabase push/pull（Notebook、Note、Attachment 三类）
- 增量同步（`CKServerChangeToken` → UserDefaults）
- `isDirty` 标记驱动的推送上行
- 冲突检测 + 自动解决（服务端版本号更高时保留本地副本）
- iCloud 账户可用性检查
- 订阅等级门槛（Standard/Pro 才可同步；debug 时 Pro）

### 已知缺口

| 缺口 | 影响 | 优先级 |
|------|------|--------|
| 无后台/周期性同步 | 切后台后其他设备改动不推送，必须前台触发 `startSync()` | 高 |
| 无 `CKSubscription` 远程推送 | 无法被动接收远端变更通知 | 高 |
| `startSync()` 依赖导航 idle | 需要 1.5s 延迟 + 30s 导航 idle 检测，如果用户快速导航可能长时间不触发 | 中 |
| 附件 change token 不回退 | 附件父 Note 未到达时跳过，但 token 不更新，每次 sync 重拉 | 低 |
| 无离线重试队列 | push 中途网络失败，脏记录留到下一轮 sync | 中 |
| SyncPayloads 未接入 CloudKit | 用户偏好/白板 payload 有 sync 结构但未集成 | 低 |

### 前置条件

CloudKit container `iCloud.com.psg.NoteLab` 必须在 Apple Developer 后台：
1. 创建并部署到 **Production**
2. Xcode Capabilities 里勾选 CloudKit 并关联此 container

如果 container 未部署，`CKContainer.accountStatus()` 返回 `.couldNotDetermine`，sync 静默跳过。

## 四、调试日志过滤

在 Xcode Console 搜索：

| 过滤条件 | 查看内容 |
|----------|----------|
| `subsystem:NoteLab category:Init` | 初始化流程计时、tier 成功/失败 |
| `subsystem:NoteLab category:Persistence` | store 创建、reset、删除 |
| `subsystem:NoteLab category:Sync` | syncNow push/pull 全流程 |
| `subsystem:NoteLab category:Subscription` | 权益刷新、购买 |
