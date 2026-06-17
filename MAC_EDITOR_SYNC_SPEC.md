### NoteLab 跨端一致性文档（iOS ⇄ macOS）：编辑器重写与同步显示格式统一指南

> **目标**：你在 macOS 端重写编辑器（UI/交互完全原生），仍然保证 iOS 与 macOS 在同步后**展示效果、块结构、格式**一致。  
> **核心原则**：**内容协议优先于编辑器实现**。两端都以同一份“canonical content”作为权威格式进行存储、同步与渲染。

---

### 1. 背景与现状（基于当前 NoteLab 代码）

#### 1.1 权威存储字段
- **跨端同步与持久化的权威内容字段是 `Note.content`（Markdown 字符串）**。
- 同步引擎会把远端 `notes.content` 拉取写入本地 `LocalNote.content`，并在冲突处理、更新、创建时同样使用 `content` 字段。
- `contentRTF` 在同步落库时为 `nil`，说明它不是跨端协议的一部分（更多是本地/历史兼容用途）。

#### 1.2 文档模型与序列化/反序列化
当前工程已定义一个稳定的块级文档模型：
- `NoteDocument.fromMarkdown(_:)`：Markdown → Block 列表（解析）
- `NoteDocument.flattenMarkdown()`：Block 列表 → Markdown（序列化）
- `Block.markdownText`：单个块的 Markdown 输出规则

> 结论：要跨端一致，macOS 端编辑器最终必须**生成与 iOS 相同方言的 Markdown**，或至少在保存时通过同一套 `NoteDocument/Block` 规则输出。

---

### 2. Canonical Content 协议：Note Markdown 方言 v1

本节定义你必须在 iOS 与 macOS 都遵守的“**笔记内容协议**”。  
macOS 编辑器可以内部使用任意表示（TextKit、NSAttributedString、DOM、prosemirror…），但只要落到 `Note.content`，就必须符合该方言。

#### 2.1 允许的块类型（BlockKind）
- paragraph（段落）
- heading（标题 H1~H6）
- bullet（无序列表）
- numbered（有序列表，序列化统一为 `1.`）
- todo（任务列表，`- [ ]` / `- [x]`）
- quote（引用）
- code（代码块：围栏 ```）
- table（Markdown pipe 表格）
- attachment（附件行：`![Attachment](...)`）

#### 2.2 块与块之间的分隔
- **块与块之间用两个换行分隔**（`\"\\n\\n\"`）。
- `flattenMarkdown()` 会将每个块 `markdownText` 用 `\\n\\n` 连接，因此 mac 端保存时也应保持该约定，避免多余空行导致解析差异。

#### 2.3 Heading（标题）
- 输出：`#` ~ `######` + 空格 + 文本
- 解析：必须是 `^(#+)\\s+` 形式；没有空格的不算标题（例如 `#Title` 不会被识别）

示例：

```md
## 会议纪要
### 决策
```

#### 2.4 Bullet（无序列表）
- 解析支持：`- `、`* `、`• `
- **序列化统一输出：`- `**
- **建议**：mac 端内部允许用户输入 `*`/`•`，但保存时必须规范化为 `- `，否则 round-trip 会变化。

示例：

```md
- 第一项
- 第二项
```

#### 2.5 Numbered（有序列表）
- 解析：匹配 `数字 + \". \" + 文本`（如 `2. xxx`）
- **序列化统一输出：`1. `**（不会保留原始序号）
- **建议**：mac 端 UI 不要承诺“序号保持不变”；如果需要真正保序号，需要升级协议（v2）。

示例：

```md
1. Step one
1. Step two
```

#### 2.6 Todo（任务列表）
- 未完成：`- [ ] `
- 已完成：`- [x] ` 或 `- [X] `
- **序列化输出**：只会输出 `- [ ]` 或 `- [x]`

示例：

```md
- [ ] 订机票
- [x] 发会议邀请
```

#### 2.7 Quote（引用）
- 解析与输出：`> ` + 文本

示例：

```md
> 这里是引用
```

#### 2.8 Code block（代码块）
- 解析条件：行首（忽略前后空白后）以 ``` 开始与结束
- **不保留语言标记**：例如 ```swift 会被解析为“进入代码块”，但最终序列化会输出无语言的 ```。  
- **建议**：mac 端若提供语言选择，只能作为 UI 辅助，不应期望跨端保真；或协议升级后再支持。

示例：

```md
```
let x = 1
print(x)
```
```

#### 2.9 Table（表格）
识别规则（必须同时满足）：
1) header 行：包含 `|`
2) 下一行：separator 行，除 `| - : 空格` 外不应有其它字符，且必须包含 `-`
3) 后续连续的 `|` 行作为数据行

序列化规范（`markdownTable(from:)`）：
- header 行：`| a | b |`
- separator：`| --- | --- |`
- rows：同样 `| ... | ... |`

**重要约束**：
- 当前实现不处理单元格内 `|` 的转义；mac 端应避免让单元格包含 `|`，或在保存时做替换/禁止输入。

示例：

```md
| 字段 | 说明 |
| --- | --- |
| title | 标题 |
| content | 正文 |
```

#### 2.10 Attachment（附件）
**唯一合法的附件行形态**：

```md
![Attachment](<target>)
```

其中 `<target>` 应优先为 **Supabase Storage path**（例如 `{userId}/{attachmentId}.jpg`）。  
解析时会从 `target` 的文件名中尝试提取 UUID 作为 `attachmentId`（用“文件名去扩展名”解析 UUID）。

##### 必须遵守的附件一致性约束（强烈推荐）
为了保证 iOS/mac 两端解析出的 `attachmentId` 一致，必须满足：

- 生成附件时先生成 `attachmentId = UUID()`
- Storage 的最终文件名必须是：`<attachmentId>.<ext>`
- Markdown 行 target 必须指向该 storage path

示例：

```md
![Attachment](6B4A1B30-9B8C-4B8D-9F3E-6B3E2A2B9A19.jpg)
```

或：

```md
![Attachment](<userId>/6B4A1B30-9B8C-4B8D-9F3E-6B3E2A2B9A19.pdf)
```

##### AI 处理附件的兼容约束
工程里存在“附件 token 化”机制，防止 AI 改写时丢附件：
- 原始附件行会被替换为 `[[ATTACHMENT:n]]`
- AI 返回后再还原，并确保缺失的附件追加到“## 附件”段落

因此 mac 端必须输出同样的附件行语法 `![Attachment](...)`，否则 token 提取/恢复会失效。

---

### 3. 跨端一致性的工程化策略

#### 3.1 强制采用统一的“协议层”
推荐你在 macOS 项目中复用（复制或做成 Swift Package）以下协议实现文件，确保 iOS/mac 解析/序列化完全一致：
- `NoteLab/Editor/NoteDocument.swift`
- `NoteLab/Editor/TableModel.swift`
- `NoteLab/AttachmentPreserver.swift`

这样 macOS 端编辑器实现差异再大，也不会影响协议一致性。

#### 3.2 推荐的数据流（Hydrate / Edit / Commit）
把编辑器分为三个阶段，且每个阶段只有一个入口/出口：

##### A. Hydrate（加载）
- 输入：`note.content`（Markdown）
- 处理：`NoteDocument.fromMarkdown(note.content)`
- 输出：`NoteDocument`（blocks）

##### B. Edit（编辑）
- 内部状态：任意（TextKit2、AttributedString、DOM…）
- 但必须能映射回 blocks（至少在保存时）

##### C. Commit（保存）
- 输入：当前编辑状态
- 处理：生成或更新 `NoteDocument.blocks` → `flattenMarkdown()`
- 输出：写回 `note.content`（Markdown）
- 同步：由现有 SyncEngine 推送

> **关键要求**：mac 端不要把“富文本格式”直接写入 `note.content`。最终必须写入 Markdown 方言 v1。

---

### 4. macOS 编辑器设计建议（保证一致性但不牺牲原生体验）

#### 4.1 UI 可以原生，但“格式集合”要受控
为避免协议外的语法造成跨端展示不一致，建议 mac 编辑器提供的格式按钮/快捷键只覆盖 v1 支持的块类型：
- 标题（H1~H6）
- 无序列表
- 有序列表（显示可递增，但保存时会归一为 `1.`，需在 UI 文档里说明）
- 待办
- 引用
- 代码块（不保语言）
- 表格（pipe 表格）
- 附件（统一 `![Attachment](storagePath)`）

#### 4.2 “看起来一样”与“内容一样”的区别
你的目标是“同步后展示效果一致”。这建议拆成两层：
- **内容一致**：靠协议（Markdown v1）保证
- **视觉一致**：靠渲染层（mac/iOS 可不同，但建议在字体、间距、列表缩进、表格样式、附件卡片样式上制定一套 Design Token）

> 建议：先做到“内容一致 + 块结构一致”，视觉差异可以接受；再逐步用 Design Token 收敛视觉。

---

### 5. 同步与冲突：对编辑器的要求

#### 5.1 版本与冲突处理（概念）
当前同步采用“带 version 条件的更新 + 冲突副本”的策略：
- 更新时带 `eq(\"version\", local.version)`，成功则版本推进
- 若更新失败且远端存在不同版本：本地接受远端内容，并创建“冲突副本”保存本地未同步内容（标记 dirty）

#### 5.2 编辑器要配合的行为建议
- **保存时机**：尽量让 `note.content` 的更新是原子性的（一次 commit 写入完整 Markdown）
- **避免协议外差异**：否则冲突副本内容可能无法在另一端正确解析/展示
- **附件上传顺序**：附件应先上传到 storage，再写入 `note.content` 里的 `![Attachment](storagePath)` 行，避免出现“内容引用了不存在的 storagePath”

---

### 6. 一致性测试（强烈建议作为跨端验收标准）

#### 6.1 Round-trip 稳定性测试（核心）
为每个样例 Markdown `M` 执行：

1) `D1 = fromMarkdown(M)`
2) `M2 = D1.flattenMarkdown()`
3) `D2 = fromMarkdown(M2)`
4) 断言：
- `D1` 与 `D2` 在块类型与关键字段上等价（kind、text、table cells、attachment storagePath/id、todo checked 等）
- `M2` 与预期的“规范化输出”一致（注意 bullet 归一、numbered 归一、code fence 语言丢失等）

#### 6.2 附件一致性测试（必做）
覆盖以下输入：
- `![Attachment]({userId}/{uuid}.jpg)`：两端解析得到相同 `attachmentId`
- `![Attachment](foo.jpg)`：确认会生成随机 UUID（并决定是否要禁止这种 target）
- PDF 与 image 两类扩展名

#### 6.3 表格边界测试
- 空单元格
- 不规则列数（解析时会补齐）
- 单元格包含 `|`（当前实现会拆裂，建议作为“不支持”的明确限制）

---

### 7. 最小实现路线图（独立 mac 项目 + API 同步）

1) **先打通协议层**  
   - 复制 `NoteDocument.swift`、`TableModel.swift`、`AttachmentPreserver.swift` 到 mac 项目  
2) **实现最小编辑器 MVP**（只支持 paragraph + heading + bullet + todo + code）  
3) **实现附件**  
   - 上传 storage → 写入 `![Attachment](storagePath)` 行  
4) **实现 table**  
5) **补齐快捷键与 mac 原生体验**  
   - Toolbar、菜单、右键菜单、多窗口等（不影响协议）

---

### 8. 附录：推荐的“黄金样例 Markdown 集”

#### 8.1 基础块
```md
## 标题

一段普通文本。

- 列表 A
- 列表 B

1. 有序 1
2. 有序 2

- [ ] 待办 1
- [x] 待办 2

> 引用一句话

```
code line 1
code line 2
```
```

#### 8.2 表格
```md
| 字段 | 说明 |
| --- | --- |
| title | 标题 |
| content | 正文 |
```

#### 8.3 附件（建议用真实 uuid）
```md
![Attachment](123E4567-E89B-12D3-A456-426614174000.jpg)
```

---

### 9. 最重要的约束总结（给实现者的 Checklist）
- **只把 Markdown 方言 v1 写入 `note.content`**
- 保存时必须走统一序列化（建议复用 `NoteDocument.flattenMarkdown()`）
- 附件 target 的文件名必须能提取到 UUID（`<attachmentId>.<ext>`）
- 不要承诺：有序列表序号保真、code fence 语言保真、复杂 Markdown 语法保真
- 表格单元格不要允许 `|`（或明确替换/禁止）

