//
//  NoteLabTests.swift
//  NoteLabTests
//
//  Created by Strictly · · on 2026/1/25.
//

import Testing
import SwiftUI
import SwiftData
import CloudKit
@testable import NoteLab

struct NoteLabTests {
    @MainActor @Test func swiftDataInMemoryContainerInitializes() async throws {
        let container = try PersistenceController.makeInMemoryContainer()
        let context = ModelContext(container)
        var fetch = FetchDescriptor<SyncMetadata>()
        fetch.fetchLimit = 1
        _ = try context.fetch(fetch)
    }

    @MainActor @Test func storageV3CreatesNotebookAndOutboxItem() async throws {
        let profileId = UUID()
        let repository = NotebookRepository()
        let notebook = try repository.createNotebook(
            profileId: profileId,
            title: "Storage v3 smoke",
            color: .lime,
            iconName: "book"
        )

        let loaded = try repository.loadNotebooks(profileId: profileId)
        #expect(loaded.contains(where: { $0.id == notebook.id && $0.title == "Storage v3 smoke" }))

        let pending = try repository.pendingOutbox(profileId: profileId)
        #expect(pending.contains(where: { $0.entityType == .notebook && $0.entityId == notebook.id }))
    }

    @MainActor @Test func voiceNoteRepositoryPersistsAndUpdatesStatus() async throws {
        let profileId = UUID()
        let notebookId = UUID()
        let noteId = UUID()
        let attachmentId = UUID()
        let repository = VoiceNoteRepository()
        let now = Date()
        let record = VoiceNoteRecord(
            id: UUID(),
            profileId: profileId,
            noteId: noteId,
            notebookId: notebookId,
            audioAttachmentId: attachmentId,
            audioStoragePath: "icloud/\(profileId.uuidString)/\(attachmentId.uuidString).m4a",
            audioFileName: "\(attachmentId.uuidString).m4a",
            duration: 12.4,
            status: .transcribing,
            rawTranscript: "",
            errorMessage: nil,
            retryCount: 0,
            createdAt: now,
            updatedAt: now
        )

        try repository.create(record)
        let loadedRecord = try repository.record(noteId: noteId)
        let loaded = try #require(loadedRecord)
        #expect(loaded.status == .transcribing)
        #expect(loaded.audioAttachmentId == attachmentId)

        let updatedRecord = try repository.update(
            id: record.id,
            profileId: profileId,
            status: .failed,
            rawTranscript: "嗯 今天要整理需求",
            errorMessage: "network timeout",
            incrementRetry: true
        )
        let updated = try #require(updatedRecord)
        #expect(updated.status == .failed)
        #expect(updated.rawTranscript == "嗯 今天要整理需求")
        #expect(updated.errorMessage == "network timeout")
        #expect(updated.retryCount == 1)
    }

    @Test func voiceNoteStatusProcessingFlagsAreNarrow() async throws {
        #expect(VoiceNoteStatus.transcribing.isProcessing)
        #expect(VoiceNoteStatus.organizing.isProcessing)
        #expect(!VoiceNoteStatus.completed.isProcessing)
        #expect(!VoiceNoteStatus.failed.isProcessing)
        #expect(!VoiceNoteStatus.needsAI.isProcessing)
    }

    @Test func voiceAudioMimeTypeUsesStandardAudioMP4ForM4A() async throws {
        #expect(AttachmentStorage.mimeType(for: "recording.m4a") == "audio/mp4")
        #expect(AttachmentStorage.mimeType(for: "recording.mp3") == "audio/mpeg")
        #expect(AttachmentStorage.mimeType(for: "recording.wav") == "audio/wav")
    }

    @Test func homeTodoSectionsHideCompletedAndSortByNewestVisibleTodo() async throws {
        let oldNotebookId = UUID()
        let newNotebookId = UUID()
        let oldNoteId = UUID()
        let newNoteId = UUID()
        let oldDate = Date(timeIntervalSince1970: 100)
        let newDate = Date(timeIntervalSince1970: 200)
        let newestDate = Date(timeIntervalSince1970: 300)
        let notebooks = [
            Notebook(id: oldNotebookId, title: "Old", color: .lime, iconName: "book", createdAt: oldDate, notes: []),
            Notebook(id: newNotebookId, title: "New", color: .sky, iconName: "book", createdAt: newDate, notes: [])
        ]
        let todos = [
            todo("old-0", noteId: oldNoteId, notebookId: oldNotebookId, title: "old first", lineIndex: 0, isCompleted: false, sortDate: oldDate),
            todo("done", noteId: newNoteId, notebookId: newNotebookId, title: "done", lineIndex: 0, isCompleted: true, sortDate: newestDate),
            todo("new", noteId: newNoteId, notebookId: newNotebookId, title: "new", lineIndex: 1, isCompleted: false, sortDate: newDate),
            todo("old-1", noteId: oldNoteId, notebookId: oldNotebookId, title: "old second", lineIndex: 1, isCompleted: false, sortDate: oldDate)
        ]

        let sections = buildSections(from: todos, transient: [:], notebooks: notebooks)

        #expect(sections.map(\.title) == ["New", "Old"])
        #expect(sections.flatMap(\.items).map(\.id) == ["new", "old-0", "old-1"])
    }

    @MainActor @Test func materialsLibraryExcludesVoiceAudioAttachments() async throws {
        let profileId = UUID()
        let noteId = UUID()
        let createdAt = Date()
        let note = Note(
            id: noteId,
            title: "会议资料",
            summary: "",
            paragraphCount: 0,
            bulletCount: 0,
            hasAdditionalContext: false,
            createdAt: createdAt,
            contentRTF: nil,
            content: ""
        )
        let imageAttachment = AttachmentRecord(
            id: UUID(),
            profileId: profileId,
            noteId: noteId,
            storagePath: "attachments/image.png",
            fileName: "image.png",
            mimeType: "image/png",
            fileSize: 128,
            originalPath: nil,
            createdAt: createdAt,
            updatedAt: createdAt,
            deletedAt: nil,
            missingLocalFile: false,
            isUploaded: false
        )
        let voiceAttachment = AttachmentRecord(
            id: UUID(),
            profileId: profileId,
            noteId: noteId,
            storagePath: "attachments/recording.m4a",
            fileName: "recording.m4a",
            mimeType: "audio/mp4",
            fileSize: 256,
            originalPath: nil,
            createdAt: createdAt.addingTimeInterval(1),
            updatedAt: createdAt.addingTimeInterval(1),
            deletedAt: nil,
            missingLocalFile: false,
            isUploaded: false
        )

        let groups = MaterialsLibraryModel.buildGroups(
            attachments: [voiceAttachment, imageAttachment],
            notes: [note]
        )

        #expect(groups.count == 1)
        #expect(groups.first?.attachments == [imageAttachment])
    }

    @Test func stableIdentityUsesCloudKitRecordNameAsCanonicalScope() async throws {
        let recordName = "_abc123"
        let first = StableIdentity.uuid(for: "icloud:\(recordName)")
        let second = StableIdentity.uuid(for: "icloud:\(recordName)")
        let local = StableIdentity.uuid(for: "simulator-local-com.psg.NoteLab")

        #expect(first == second)
        #expect(first != local)
    }

    @Test func noteTitleDeriverSkipsGeneratedStructureHeadings() async throws {
        let markdown = """
        ## 摘要

        本文档说明原生图标资源规则。

        ## 核心规则
        """
        let title = NoteTitleDeriver.title(fromMarkdown: markdown, fallback: "")
        #expect(title == "本文档说明原生图标资源规则。")
    }

    @Test func aiTitleDeriverRejectsGenericHeadingsAndLimitsLength() async throws {
        #expect(NoteTitleDeriver.title(fromAI: "摘要", fallback: "正文标题") == "正文标题")
        #expect(NoteTitleDeriver.title(fromAI: "原生图标资源配置验证流程", fallback: "") == "原生图标资源配置验证")
        #expect(NoteTitleDeriver.title(fromAI: "Native Icon Resource Validation Workflow Details", fallback: "") == "Native Icon Resource Validation Workflow")
    }

    private func todo(
        _ id: String,
        noteId: UUID,
        notebookId: UUID,
        title: String,
        lineIndex: Int,
        isCompleted: Bool,
        sortDate: Date
    ) -> LocalTodoItem {
        LocalTodoItem(
            id: id,
            title: title,
            noteId: noteId,
            noteTitle: "Note",
            notebookId: notebookId,
            notebookTitle: "Notebook",
            lineIndex: lineIndex,
            isWhiteboard: false,
            isCompleted: isCompleted,
            sortDate: sortDate
        )
    }

    @Test func aiInsightComposerPersistsAITitleAsFirstMarkdownLine() async throws {
        let report = AINoteInsightReport(
            title: "图标治理",
            summary: "说明图标资源配置策略。",
            sections: [
                AIReportSection(heading: "核心规则", paragraphs: ["只保留一个图标系统。"], bullets: [])
            ],
            tables: []
        )
        let markdown = AIInsightComposer.composeInsightMarkdown(
            formattedMarkdown: "保留 AppIcon.appiconset 并移除冲突资源。",
            report: report,
            tasks: [],
            fallbackTitle: "旧标题"
        )

        #expect(markdown.hasPrefix("# 图标治理\n\n"))
        #expect(NoteTitleDeriver.title(fromMarkdown: markdown, fallback: "") == "图标治理")
    }

    @Test func aiInsightComposerDoesNotDuplicateLeadingBodyTitle() async throws {
        let report = AINoteInsightReport(
            title: "图标治理",
            summary: "",
            sections: [],
            tables: []
        )
        let markdown = AIInsightComposer.composeInsightMarkdown(
            formattedMarkdown: """
            # 旧标题

            保留 AppIcon.appiconset 并移除冲突资源。
            """,
            report: report,
            tasks: [],
            fallbackTitle: "旧标题"
        )

        let titleOccurrences = markdown.components(separatedBy: "# 图标治理").count - 1
        #expect(titleOccurrences == 1)
        #expect(markdown.hasPrefix("# 图标治理\n\n"))
        #expect(markdown.contains("保留 AppIcon.appiconset"))
    }

    @Test func aiInsightComposerDropsLowValueTodoStatusTable() async throws {
        let report = AINoteInsightReport(
            title: "云条录音",
            summary: "",
            sections: [],
            tables: [
                AIReportTable(
                    title: "待办事项清单",
                    columns: ["任务", "状态"],
                    rows: [
                        ["在首页顶部添加云条 UI 组件", "待办"],
                        ["实现长按手势识别与录音功能", "待办"]
                    ],
                    notes: nil
                )
            ]
        )
        let tasks = [
            AITaskSuggestion(
                text: "完成云条录音入口设计与验证",
                dueDate: nil,
                priority: "high",
                confidence: 0.8,
                sourceAnchor: AIAnchor(paragraphIndex: 2)
            )
        ]
        let markdown = AIInsightComposer.composeInsightMarkdown(
            formattedMarkdown: "",
            report: report,
            tasks: tasks,
            fallbackTitle: "云条录音"
        )
        #expect(!markdown.contains("| 任务 | 状态 |"))
        #expect(markdown.contains("## 待办"))
        #expect(markdown.contains("- [ ] 完成云条录音入口设计与验证"))
    }

    @Test func aiInsightComposerSegmentsLongParagraphs() async throws {
        let longParagraph = "识别项目类型和图标源：如果仓库是 Expo/React Native，使用 Expo 应用图标工作流；如果是原生 Xcode，检查 .xcodeproj/project.pbxproj、Assets.xcassets 和 Info.plist 输出。选择恰好一个图标系统：保留 AppIcon.appiconset 以获得保守兼容性；仅当目标明确配置为使用 .icon 文件时，才迁移到 Icon Composer。移除冲突资源：删除复制的 AppIcon.icon 资源，删除过时的 appicon.imageset，删除过时的项目引用和资源构建阶段条目。验证源图片：必须尺寸正确、不透明，并确保 1024 营销图标存在。"
        let report = AINoteInsightReport(
            title: "图标验证",
            summary: "",
            sections: [
                AIReportSection(heading: "工作流步骤", paragraphs: [longParagraph], bullets: [])
            ],
            tables: []
        )
        let markdown = AIInsightComposer.composeInsightMarkdown(
            formattedMarkdown: "",
            report: report,
            tasks: [],
            fallbackTitle: "图标验证"
        )
        #expect(markdown.contains("工作流步骤"))
        let hasBlankSeparator = markdown
            .split(separator: "\n", omittingEmptySubsequences: false)
            .contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        #expect(hasBlankSeparator)
        #expect(markdown.contains("选择恰好一个图标系统"))
        #expect(markdown.contains("Assets.xcassets"))
        #expect(markdown.contains("AppIcon.appiconset"))
    }

    @MainActor @Test func legacyProfileMigratesIntoCanonicalProfileWithoutDuplicateNotebook() async throws {
        let account = AppleAccount(
            appleUserId: "simulator-local-test-\(UUID().uuidString)",
            email: nil,
            displayName: "Simulator Local",
            localUserId: UUID()
        )
        let canonicalProfileId = UUID()
        let repository = NotebookRepository()
        let notebook = try repository.createNotebook(
            profileId: account.localUserId,
            title: "Legacy notebook",
            color: .sky,
            iconName: "book"
        )
        let note = Note(
            id: UUID(),
            title: "Legacy note",
            summary: "migrate me",
            paragraphCount: 0,
            bulletCount: 0,
            hasAdditionalContext: false,
            createdAt: Date(),
            contentRTF: nil,
            content: "legacy"
        )
        _ = try repository.createNote(profileId: account.localUserId, notebookId: notebook.id, note: note)

        let identity = SyncProfileIdentity(
            profileId: canonicalProfileId,
            legacyProfileId: account.localUserId,
            iCloudAccountHash: "test-hash",
            source: .cloudKit
        )
        let profile = try ProfileRepository().ensureProfile(account: account, syncIdentity: identity)

        #expect(profile.profileId == canonicalProfileId)
        #expect(try repository.loadNotebooks(profileId: account.localUserId).isEmpty)
        let migrated = try repository.loadNotebooks(profileId: canonicalProfileId)
        #expect(migrated.filter { $0.id == notebook.id }.count == 1)
        #expect(migrated.first(where: { $0.id == notebook.id })?.notes.contains(where: { $0.id == note.id }) == true)
        let pending = try repository.pendingOutbox(profileId: canonicalProfileId)
        #expect(pending.contains(where: { $0.entityType == .notebook && $0.entityId == notebook.id }))
        #expect(pending.contains(where: { $0.entityType == .note && $0.entityId == note.id }))
    }

    @MainActor @Test func syncSummaryMergePreservesFailureMessage() async throws {
        var summary = SyncSummary(reason: .manual, pushed: 1)
        summary.merge(SyncSummary(reason: .manual, failed: 1, message: "部分内容同步失败，稍后会自动重试"))
        #expect(summary.pushed == 1)
        #expect(summary.failed == 1)
        #expect(summary.hasFailures)
        #expect(summary.message == "部分内容同步失败，稍后会自动重试")
        #expect(SyncReason.remoteNotification.shouldShowPaywall == false)
    }

    @MainActor @Test func cloudKitDeletedRecordParsesStorageV3RecordName() async throws {
        let profileId = UUID()
        let noteId = UUID()
        let recordID = CKRecord.ID(
            recordName: "\(profileId.uuidString.lowercased()):\(SyncEntityType.note.rawValue):\(noteId.uuidString.lowercased())",
            zoneID: CloudKitSchema.zoneID
        )
        let deleted = CloudKitTransport.deletedRecord(from: recordID)
        #expect(deleted?.profileId == profileId)
        #expect(deleted?.entityType == .note)
        #expect(deleted?.id == noteId)
    }

    @MainActor @Test func remoteHardDeleteSoftDeletesLocalNote() async throws {
        let profileId = UUID()
        let repository = NotebookRepository()
        let notebook = try repository.createNotebook(
            profileId: profileId,
            title: "Hard delete notebook",
            color: .lime,
            iconName: "book"
        )
        let note = Note(
            id: UUID(),
            title: "Remote hard delete",
            summary: "Before delete",
            paragraphCount: 0,
            bulletCount: 0,
            hasAdditionalContext: false,
            createdAt: Date(),
            contentRTF: nil,
            content: ""
        )
        _ = try repository.createNote(profileId: profileId, notebookId: notebook.id, note: note)

        try repository.applyRemoteHardDelete(profileId: profileId, entityType: .note, id: note.id)
        try StorageController.shared.saveMainContext()

        let loaded = try repository.loadNotebooks(profileId: profileId)
        let loadedNotebook = try #require(loaded.first(where: { $0.id == notebook.id }))
        #expect(loadedNotebook.notes.contains(where: { $0.id == note.id }) == false)
    }

    @MainActor @Test func remoteNoteWithPendingLocalEditCreatesConflictCopy() async throws {
        let profileId = UUID()
        let repository = NotebookRepository()
        let notebook = try repository.createNotebook(
            profileId: profileId,
            title: "Conflict notebook",
            color: .lime,
            iconName: "book"
        )
        let original = Note(
            id: UUID(),
            title: "Local draft",
            summary: "Local",
            paragraphCount: 0,
            bulletCount: 0,
            hasAdditionalContext: false,
            createdAt: Date(),
            contentRTF: nil,
            content: ""
        )
        _ = try repository.createNote(profileId: profileId, notebookId: notebook.id, note: original)

        let edited = Note(
            id: original.id,
            title: "Local edited",
            summary: "Unsynced local",
            paragraphCount: original.paragraphCount,
            bulletCount: original.bulletCount,
            hasAdditionalContext: original.hasAdditionalContext,
            createdAt: original.createdAt,
            updatedAt: Date(),
            contentRTF: original.contentRTF,
            content: original.content,
            isPinned: original.isPinned
        )
        try repository.updateNote(profileId: profileId, notebookId: notebook.id, note: edited)

        let remote = NoteRemoteRecord(
            id: original.id,
            profileIdHash: CloudKitTransport.hash(profileId.uuidString.lowercased()),
            notebookId: notebook.id,
            title: "Remote canonical",
            summary: "Remote",
            paragraphCount: 0,
            bulletCount: 0,
            hasAdditionalContext: false,
            createdAt: original.createdAt,
            updatedAt: Date(),
            deletedAt: nil,
            version: 1,
            contentRTF: nil,
            content: "",
            isPinned: false,
            conflictParentId: nil,
            localRevision: 2,
            lastSyncedHash: "remote-hash",
            deviceId: "other-device"
        )

        try repository.applyRemoteNote(profileId: profileId, record: remote)
        try StorageController.shared.saveMainContext()

        let loadedNotes = try repository.loadNotebooks(profileId: profileId).flatMap(\.notes)
        #expect(loadedNotes.contains(where: { $0.id == original.id && $0.title == "Remote canonical" }))
        #expect(loadedNotes.contains(where: { $0.title == "Local edited（冲突副本）" }))
    }

    @MainActor @Test func richTextRoundTripPreservesPlainText() async throws {
        let original = AttributedString("Hello 世界\n- [ ] Task")
        let data = RichTextCodec.encodeRTF(from: original)
        #expect(data != nil)
        let decoded = RichTextCodec.decodeRTF(data!)
        #expect(RichTextCodec.plainText(from: decoded) == RichTextCodec.plainText(from: original))
    }

    @MainActor @Test func richTextPlainTextHandlesNilData() async throws {
        let result = RichTextCodec.plainText(from: nil)
        #expect(result == nil)
    }

    @MainActor @Test func snapperClampsWithinBounds() async throws {
        let container = CGSize(width: 320, height: 480)
        let insets = EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        let overlay = CGSize(width: 120, height: 100)
        let raw = CGSize(width: 1000, height: 1000)
        let clamped = WhiteboardLinkSnapper.clamp(offset: raw, container: container, insets: insets, overlaySize: overlay, padding: 12)
        #expect(clamped.width == 0)
        #expect(clamped.height == 356)
    }

    @MainActor @Test func snapperSnapsToClosestPoint() async throws {
        let container = CGSize(width: 320, height: 480)
        let insets = EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        let overlay = CGSize(width: 120, height: 100)
        let nearLeftTop = CGSize(width: -140, height: 5)
        let snapped = WhiteboardLinkSnapper.snap(offset: nearLeftTop, container: container, insets: insets, overlaySize: overlay, padding: 12)
        #expect(snapped.width == -176)
        #expect(snapped.height == 0)
    }

    @Test func noteShareBuilderCopiesMarkdownWithTitleHeading() async throws {
        let doc = NoteDocument.fromMarkdown("""
        Body paragraph

        - Item
        """)
        let markdown = NoteShareBuilder.markdown(title: "Meeting Notes", document: doc, fallbackMarkdown: "")
        #expect(markdown == """
        # Meeting Notes

        Body paragraph

        - Item
        """)
    }

    @Test func noteShareBuilderDoesNotDuplicateExistingMarkdownTitle() async throws {
        let doc = NoteDocument.fromMarkdown("""
        # Meeting Notes

        Body paragraph
        """)
        let markdown = NoteShareBuilder.markdown(title: "Meeting Notes", document: doc, fallbackMarkdown: "")
        #expect(markdown == """
        # Meeting Notes

        Body paragraph
        """)
    }

    @Test func noteShareBuilderFallsBackToPersistedMarkdownForEmptyDocument() async throws {
        let doc = NoteDocument.fromPlainText("")
        let markdown = NoteShareBuilder.markdown(title: "Existing", document: doc, fallbackMarkdown: """
        ## Existing

        - [ ] Task
        """)
        #expect(markdown == """
        ## Existing

        - [ ] Task
        """)
    }

    @MainActor @Test func noteDocumentParsesLegacyAttachmentToken() async throws {
        let attachmentId = UUID()
        let markdown = "![图片](attachment:\(attachmentId.uuidString.lowercased()))"
        let doc = NoteDocument.fromMarkdown(markdown)
        #expect(doc.blocks.count == 1)
        #expect(doc.blocks[0].attachment?.id == attachmentId)
        #expect(doc.flattenMarkdown().contains("![Attachment](attachment:\(attachmentId.uuidString.lowercased()))"))
    }

    @MainActor @Test func noteDocumentParsesStoragePathAttachmentWithCustomAlt() async throws {
        let ownerId = UUID()
        let attachmentId = UUID()
        let target = "\(ownerId.uuidString)/\(attachmentId.uuidString).png"
        let markdown = "![任意Alt](\(target))"
        let doc = NoteDocument.fromMarkdown(markdown)
        #expect(doc.blocks.count == 1)
        #expect(doc.blocks[0].attachment?.id == attachmentId)
        #expect(doc.blocks[0].attachment?.storagePath == target)
        #expect(doc.flattenMarkdown().contains("![Attachment](\(target))"))
    }

    @MainActor @Test func noteDocumentParsesLegacyPathAttachmentContainingUUID() async throws {
        let attachmentId = UUID()
        let markdown = "![x](/var/mobile/Containers/Data/\(attachmentId.uuidString.lowercased()).png)"
        let doc = NoteDocument.fromMarkdown(markdown)
        #expect(doc.blocks.count == 1)
        #expect(doc.blocks[0].kind == .attachment)
        #expect(doc.blocks[0].attachment?.id == attachmentId)
    }

    @MainActor @Test func noteDocumentSkipsNonAttachmentMarkdownImages() async throws {
        let markdown = """
        ![x](https://example.com/a.png)

        ![x](#)

        ![x](random-text-without-uuid)
        """
        let doc = NoteDocument.fromMarkdown(markdown)
        #expect(doc.blocks.count == 3)
        #expect(doc.blocks[0].kind == .paragraph)
        #expect(doc.blocks[1].kind == .paragraph)
        #expect(doc.blocks[2].kind == .paragraph)
        #expect(doc.flattenMarkdown().contains("https://example.com/a.png"))
        #expect(doc.flattenMarkdown().contains("![x](#)"))
        #expect(doc.flattenMarkdown().contains("random-text-without-uuid"))
    }

    @MainActor @Test func noteDocumentRoundTripsSupportedMarkdownBlocks() async throws {
        let ownerId = UUID()
        let attachmentId = UUID()
        let markdown = """
        Intro **bold** *italic* `code` ==yellow:highlight==

        # Heading 1

        ## Heading 2

        - Bullet

        2. Numbered

        - [x] Done

        > Quote

        ```
        let value = 1
        ```

        | Field | Value |
        | --- | --- |
        | name | NoteLab |

        ![Attachment](\(AttachmentPathFactory.storagePath(ownerId: ownerId, attachmentId: attachmentId, fileName: "source.png")))
        """

        let first = NoteDocument.fromMarkdown(markdown)
        let second = NoteDocument.fromMarkdown(first.flattenMarkdown())
        #expect(second.blocks.map(\.kind) == first.blocks.map(\.kind))
        #expect(second.blocks.count == 10)
        #expect(second.blocks[0].text.contains("**bold**"))
        #expect(second.blocks[1].level == 1)
        #expect(second.blocks[2].level == 2)
        #expect(second.blocks[5].isChecked == true)
        #expect(second.blocks[8].table?.cells[1][1] == "NoteLab")
        #expect(second.blocks[9].attachment?.id == attachmentId)
    }

    @MainActor @Test func attachmentPathFactoryCreatesParseableStoragePath() async throws {
        let ownerId = UUID()
        let attachmentId = UUID()
        let path = AttachmentPathFactory.storagePath(ownerId: ownerId, attachmentId: attachmentId, fileName: "original.pdf")
        let doc = NoteDocument.fromMarkdown("![Attachment](\(path))")
        #expect(doc.blocks.count == 1)
        #expect(doc.blocks[0].kind == .attachment)
        #expect(doc.blocks[0].attachment?.id == attachmentId)
        #expect(doc.blocks[0].attachment?.storagePath == path)
    }

    @MainActor @Test func notePersistenceDebounceFlushesLatestEditOnly() async throws {
        let profileId = UUID()
        let repository = NotebookRepository()
        let notebook = try repository.createNotebook(
            profileId: profileId,
            title: "Debounce notebook",
            color: .lime,
            iconName: "book"
        )
        let note = Note(
            id: UUID(),
            title: "Draft",
            summary: "",
            paragraphCount: 0,
            bulletCount: 0,
            hasAdditionalContext: false,
            createdAt: Date(),
            contentRTF: nil,
            content: "Initial"
        )
        try repository.createNote(profileId: profileId, notebookId: notebook.id, note: note)

        let initialNoteOutboxCount = try repository.pendingOutbox(profileId: profileId)
            .filter { $0.entityType == .note && $0.entityId == note.id }
            .count

        let store = NotebookStore()
        store.configure(profileId: profileId)
        let binding = try #require(store.noteBinding(noteId: note.id))
        var first = binding.wrappedValue
        first.content = "First"
        binding.wrappedValue = first
        var second = binding.wrappedValue
        second.content = "Second"
        binding.wrappedValue = second
        var third = binding.wrappedValue
        third.content = "Third"
        binding.wrappedValue = third

        let beforeFlushCount = try repository.pendingOutbox(profileId: profileId)
            .filter { $0.entityType == .note && $0.entityId == note.id }
            .count
        #expect(beforeFlushCount == initialNoteOutboxCount)

        store.flushPendingNotePersistence(noteId: note.id)

        let loaded = try repository.loadNotebooks(profileId: profileId)
        let loadedNote = try #require(loaded.flatMap(\.notes).first(where: { $0.id == note.id }))
        #expect(loadedNote.content == "Third")

        let afterFlushCount = try repository.pendingOutbox(profileId: profileId)
            .filter { $0.entityType == .note && $0.entityId == note.id }
            .count
        #expect(afterFlushCount == initialNoteOutboxCount + 1)
    }
}
