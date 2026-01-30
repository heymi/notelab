import Foundation

import Foundation

enum SampleData {
    private static let meetingContent = """
## 总体印象
- [x] 界面专注，没有干扰感
- [x] 写作优先，而不是排版
- [x] 打开速度极快
- [ ] 结构与自由之间平衡不错

## 总体评价
产品的速度感很强，打开即写。界面保持克制，让思路几乎不被打断。适合高频记录与会议整理，不追求花哨排版。

## 改进建议
当笔记变长时，希望能快速折叠分区或高亮行动项，减少视觉噪音。
AI 的整理和待办提取要尽量可回滚，以避免误删内容。
"""

    private static let shortContent = """
## 速记
- [ ] 整理需求清单
- [ ] 补充交互方案
今天先完成主要结构，再补充细节。
"""

    static let notebooks: [Notebook] = [
        Notebook(
            id: UUID(),
            title: "Beta 反馈",
            color: .lime,
            iconName: "scribble",
            createdAt: Date(timeIntervalSinceNow: -86400 * 16),
            notes: [
                Note(id: UUID(), title: "Figma 会议", summary: "16 additional context", paragraphCount: 16, bulletCount: 0, hasAdditionalContext: true, createdAt: Date(timeIntervalSinceNow: -86400 * 2), contentRTF: nil, content: meetingContent),
                Note(id: UUID(), title: "Vercel Palo Alto", summary: "19 paragraphs, 8 bullets", paragraphCount: 19, bulletCount: 8, hasAdditionalContext: true, createdAt: Date(timeIntervalSinceNow: -86400 * 1), contentRTF: nil, content: meetingContent),
                Note(id: UUID(), title: "Vercel SF", summary: "No context found", paragraphCount: 0, bulletCount: 0, hasAdditionalContext: false, createdAt: Date(timeIntervalSinceNow: -3600 * 18), contentRTF: nil, content: shortContent),
                Note(id: UUID(), title: "Stripe 设计评审", summary: "12 bullet points", paragraphCount: 0, bulletCount: 12, hasAdditionalContext: true, createdAt: Date(timeIntervalSinceNow: -3600 * 6), contentRTF: nil, content: meetingContent)
            ]
        ),
        Notebook(
            id: UUID(),
            title: "新功能",
            color: .sky,
            iconName: "paperplane",
            createdAt: Date(timeIntervalSinceNow: -86400 * 8),
            notes: [
                Note(id: UUID(), title: "新需求清单", summary: "6 paragraphs, 4 bullets", paragraphCount: 6, bulletCount: 4, hasAdditionalContext: true, createdAt: Date(timeIntervalSinceNow: -3600 * 20), contentRTF: nil, content: shortContent)
            ]
        ),
        Notebook(
            id: UUID(),
            title: "代码原型",
            color: .teal,
            iconName: "sparkles",
            createdAt: Date(timeIntervalSinceNow: -86400 * 5),
            notes: [
                Note(id: UUID(), title: "AI 编辑器", summary: "8 paragraphs, 3 bullets", paragraphCount: 8, bulletCount: 3, hasAdditionalContext: true, createdAt: Date(timeIntervalSinceNow: -86400 * 4), contentRTF: nil, content: meetingContent)
            ]
        ),
        Notebook(
            id: UUID(),
            title: "顶级设计",
            color: .orange,
            iconName: "moon.stars.fill",
            createdAt: Date(timeIntervalSinceNow: -86400 * 3),
            notes: [
                Note(id: UUID(), title: "UI 方向", summary: "10 paragraphs", paragraphCount: 10, bulletCount: 0, hasAdditionalContext: true, createdAt: Date(timeIntervalSinceNow: -86400 * 2), contentRTF: nil, content: meetingContent)
            ]
        ),
        Notebook(
            id: UUID(),
            title: "Whop Lab",
            color: .lavender,
            iconName: "paperclip",
            createdAt: Date(timeIntervalSinceNow: -86400 * 21),
            notes: [
                Note(id: UUID(), title: "访谈记录", summary: "4 paragraphs, 2 bullets", paragraphCount: 4, bulletCount: 2, hasAdditionalContext: true, createdAt: Date(timeIntervalSinceNow: -86400 * 18), contentRTF: nil, content: meetingContent)
            ]
        ),
        Notebook(
            id: UUID(),
            title: "Vercel 研报",
            color: .mint,
            iconName: "triangle.fill",
            createdAt: Date(timeIntervalSinceNow: -86400 * 12),
            notes: [
                Note(id: UUID(), title: "竞品对比", summary: "7 paragraphs", paragraphCount: 7, bulletCount: 0, hasAdditionalContext: true, createdAt: Date(timeIntervalSinceNow: -86400 * 9), contentRTF: nil, content: meetingContent)
            ]
        )
    ]
}
