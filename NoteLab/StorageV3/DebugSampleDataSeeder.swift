#if DEBUG
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import os

@MainActor
enum DebugSampleDataSeeder {
    private static let logger = Logger(subsystem: "NoteLab", category: "DebugSampleDataSeeder")

    static func seedIfNeeded(profileId: UUID) async {
        let userDefaultsKey = "debug.sampleDataSeeded.v3.\(profileId.uuidString.lowercased())"
        let repository = NotebookRepository()
        do {
            let notebooks = try repository.loadNotebooks(profileId: profileId)
            try normalizeSampleNotebookIcons(profileId: profileId, notebooks: notebooks, repository: repository)
            guard !UserDefaults.standard.bool(forKey: userDefaultsKey), notebooks.isEmpty else { return }
            try seed(profileId: profileId, repository: repository)
            UserDefaults.standard.set(true, forKey: userDefaultsKey)
            logger.info("seeded Storage v3 sample data for \(profileId.uuidString, privacy: .public)")
        } catch {
            logger.error("sample data seed failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func seed(profileId: UUID, repository: NotebookRepository) throws {
        let now = Date()
        let product = try makeNotebook(
            repository: repository,
            profileId: profileId,
            title: "产品灵感",
            color: .lime,
            iconName: "sparkles",
            description: "用于收集功能想法、发布检查清单和竞品观察。"
        )
        let work = try makeNotebook(
            repository: repository,
            profileId: profileId,
            title: "工作资料",
            color: .sky,
            iconName: "folder.fill",
            description: "会议纪要、项目推进和可执行任务。"
        )
        let travel = try makeNotebook(
            repository: repository,
            profileId: profileId,
            title: "旅行计划",
            color: .orange,
            iconName: "paperplane",
            description: "路线、预算、灵感图片和每日安排。"
        )
        let reading = try makeNotebook(
            repository: repository,
            profileId: profileId,
            title: "读书摘录",
            color: .teal,
            iconName: "book.fill",
            description: "长文摘要、引用和复盘。"
        )

        try makeNote(
            repository: repository,
            profileId: profileId,
            notebookId: product.id,
            title: "Storage v3 验收清单",
            summary: "本地可靠性、离线写入、CloudKit 同步的核心检查项。",
            createdAt: now.addingTimeInterval(-18_000),
            content: """
            # Storage v3 验收清单

            - [ ] 无网创建笔记后强杀 App，重启仍存在
            - [ ] 附件原图写入 Application Support，不受清缓存影响
            - [ ] CloudKit 失败只影响同步状态，不影响编辑
            - [ ] 多账号切换后数据按 profile 隔离

            这条样本由 Debug 构建自动生成，走正式 Repository + Outbox 写入链路。
            """
        )

        try makeImageNote(
            repository: repository,
            profileId: profileId,
            notebookId: product.id,
            title: "灵感板：编辑器附件体验",
            summary: "包含一张本地 durable original 图片附件。",
            createdAt: now.addingTimeInterval(-14_400),
            imageName: "editor-inspiration.png",
            palette: SamplePalette(background: (0.06, 0.09, 0.14), primary: (0.62, 0.92, 0.48), secondary: (0.35, 0.72, 0.95)),
            body: """
            # 灵感板：编辑器附件体验

            目标：图片插入后应该立即可见，本地缓存命中，离线也能打开。

            """
        )

        try makeNote(
            repository: repository,
            profileId: profileId,
            notebookId: work.id,
            title: "周会纪要",
            summary: "同步、订阅和编辑器稳定性的跟进事项。",
            createdAt: now.addingTimeInterval(-10_800),
            content: """
            # 周会纪要

            ## 本周重点
            - 完成 Core Data SQLite 主库接入
            - 验证 Debug Pro 临时解锁
            - 真机安装后检查冷启动和本地数据读取

            ## 风险
            - CloudKit schema 未部署到 Production 前，TestFlight 同步可能失败
            - 大附件上传需要后台重试和用户可见状态
            """
        )

        try makeNote(
            repository: repository,
            profileId: profileId,
            notebookId: work.id,
            title: "客户访谈记录",
            summary: "记录用户对离线可靠性和多设备同步的预期。",
            createdAt: now.addingTimeInterval(-8_400),
            content: """
            # 客户访谈记录

            用户真正关心的是：打开就能写，写了就别丢。

            关键表达：
            > 同步可以晚一点，但本地内容必须马上稳定保存。

            后续要在设置页明确展示 iCloud 账户、同步状态和最近一次成功同步时间。
            """
        )

        try makeImageNote(
            repository: repository,
            profileId: profileId,
            notebookId: travel.id,
            title: "京都三日路线",
            summary: "旅行文件夹样本，包含路线图风格图片。",
            createdAt: now.addingTimeInterval(-7_200),
            imageName: "kyoto-route.png",
            palette: SamplePalette(background: (0.98, 0.92, 0.78), primary: (0.94, 0.36, 0.24), secondary: (0.14, 0.46, 0.42)),
            body: """
            # 京都三日路线

            Day 1：祇园、鸭川、清水寺
            Day 2：岚山、嵯峨野、二条城
            Day 3：伏见稻荷、锦市场、咖啡店整理照片

            """
        )

        try makeNote(
            repository: repository,
            profileId: profileId,
            notebookId: travel.id,
            title: "行前打包清单",
            summary: "证件、设备、衣物和离线资料。",
            createdAt: now.addingTimeInterval(-5_400),
            content: """
            # 行前打包清单

            - 护照 / 身份证
            - 充电器、移动电源、转换头
            - 相机和备用存储卡
            - 离线地图、酒店确认单
            - 轻便雨衣
            """
        )

        try makeNote(
            repository: repository,
            profileId: profileId,
            notebookId: reading.id,
            title: "《设计中的设计》摘录",
            summary: "关于信息密度、留白和可感知秩序的读书摘录。",
            createdAt: now.addingTimeInterval(-3_600),
            content: """
            # 《设计中的设计》摘录

            好的工具不是把功能都摆出来，而是让用户在需要的时刻自然找到它。

            记录：
            - 降低启动摩擦，比增加一个新功能更重要
            - 复杂系统需要稳定的边界和可恢复路径
            - 视觉上要让状态一眼可读
            """
        )

        try makeImageNote(
            repository: repository,
            profileId: profileId,
            notebookId: reading.id,
            title: "书桌素材图",
            summary: "用于测试资料库缩略图和图片附件加载。",
            createdAt: now.addingTimeInterval(-1_800),
            imageName: "desk-reference.png",
            palette: SamplePalette(background: (0.12, 0.13, 0.11), primary: (0.95, 0.74, 0.36), secondary: (0.54, 0.78, 0.70)),
            body: """
            # 书桌素材图

            这张图用于验证：
            - 本地原图保存
            - 编辑器图片块解析
            - 附件缩略图缓存

            """
        )
    }

    private static func makeNotebook(
        repository: NotebookRepository,
        profileId: UUID,
        title: String,
        color: NotebookColor,
        iconName: String,
        description: String
    ) throws -> Notebook {
        let notebook = try repository.createNotebook(profileId: profileId, title: title, color: color, iconName: iconName)
        try repository.updateNotebook(profileId: profileId, id: notebook.id, title: nil, color: nil, description: description)
        return notebook
    }

    private static func normalizeSampleNotebookIcons(profileId: UUID, notebooks: [Notebook], repository: NotebookRepository) throws {
        let expectedIcons = [
            "产品灵感": "sparkles",
            "工作资料": "folder.fill",
            "旅行计划": "paperplane",
            "读书摘录": "book.fill"
        ]

        for notebook in notebooks {
            guard let expectedIcon = expectedIcons[notebook.title], notebook.iconName != expectedIcon else { continue }
            try repository.updateNotebook(
                profileId: profileId,
                id: notebook.id,
                title: nil,
                color: nil,
                description: nil,
                iconName: expectedIcon
            )
        }
    }

    private static func makeNote(
        repository: NotebookRepository,
        profileId: UUID,
        notebookId: UUID,
        title: String,
        summary: String,
        createdAt: Date,
        content: String
    ) throws {
        var note = Note(
            id: UUID(),
            title: title,
            summary: summary,
            paragraphCount: 0,
            bulletCount: 0,
            hasAdditionalContext: false,
            createdAt: createdAt,
            updatedAt: createdAt,
            contentRTF: nil,
            content: content
        )
        note.updateMetrics()
        try repository.createNote(profileId: profileId, notebookId: notebookId, note: note)
    }

    private static func makeImageNote(
        repository: NotebookRepository,
        profileId: UUID,
        notebookId: UUID,
        title: String,
        summary: String,
        createdAt: Date,
        imageName: String,
        palette: SamplePalette,
        body: String
    ) throws {
        let noteId = UUID()
        let attachmentId = UUID()
        let storagePath = CloudKitSchema.storagePath(ownerId: profileId, attachmentId: attachmentId, fileName: imageName)
        let imageData = try samplePNG(palette: palette)
        var note = Note(
            id: noteId,
            title: title,
            summary: summary,
            paragraphCount: 0,
            bulletCount: 0,
            hasAdditionalContext: false,
            createdAt: createdAt,
            updatedAt: createdAt,
            contentRTF: nil,
            content: body + "![Attachment](\(storagePath))\n"
        )
        note.updateMetrics()
        try repository.createNote(profileId: profileId, notebookId: notebookId, note: note)
        _ = try AttachmentStorage.shared.saveNewAttachmentV3(
            data: imageData,
            attachmentId: attachmentId,
            ownerId: profileId,
            noteId: noteId,
            fileName: imageName,
            mimeType: "image/png"
        )
    }

    private static func samplePNG(palette: SamplePalette) throws -> Data {
        let width = 900
        let height = 600
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw NSError(domain: "DebugSampleDataSeeder", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create sample image context"])
        }

        context.setFillColor(palette.backgroundColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(palette.primaryColor)
        context.fill(CGRect(x: 72, y: 72, width: 756, height: 118))
        context.setFillColor(palette.secondaryColor)
        context.fill(CGRect(x: 72, y: 238, width: 520, height: 88))
        context.setFillColor(palette.secondaryColor.copy(alpha: 0.68) ?? palette.secondaryColor)
        context.fill(CGRect(x: 72, y: 374, width: 690, height: 74))
        context.setFillColor(CGColor(gray: 1, alpha: 0.72))
        context.fill(CGRect(x: 650, y: 232, width: 150, height: 150))
        context.setFillColor(CGColor(gray: 1, alpha: 0.36))
        context.fillEllipse(in: CGRect(x: 672, y: 254, width: 106, height: 106))

        guard let image = context.makeImage() else {
            throw NSError(domain: "DebugSampleDataSeeder", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not render sample image"])
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            throw NSError(domain: "DebugSampleDataSeeder", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not create PNG destination"])
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "DebugSampleDataSeeder", code: 4, userInfo: [NSLocalizedDescriptionKey: "Could not encode sample PNG"])
        }
        return output as Data
    }
}

private struct SamplePalette {
    let background: (red: CGFloat, green: CGFloat, blue: CGFloat)
    let primary: (red: CGFloat, green: CGFloat, blue: CGFloat)
    let secondary: (red: CGFloat, green: CGFloat, blue: CGFloat)

    var backgroundColor: CGColor {
        CGColor(red: background.red, green: background.green, blue: background.blue, alpha: 1)
    }

    var primaryColor: CGColor {
        CGColor(red: primary.red, green: primary.green, blue: primary.blue, alpha: 1)
    }

    var secondaryColor: CGColor {
        CGColor(red: secondary.red, green: secondary.green, blue: secondary.blue, alpha: 1)
    }
}
#endif
