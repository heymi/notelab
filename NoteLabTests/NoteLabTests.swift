//
//  NoteLabTests.swift
//  NoteLabTests
//
//  Created by Strictly · · on 2026/1/25.
//

import Testing
import SwiftUI
import SwiftData
@testable import NoteLab

struct NoteLabTests {
    @MainActor @Test func swiftDataInMemoryContainerInitializes() async throws {
        let container = try PersistenceController.makeInMemoryContainer()
        let context = ModelContext(container)
        var fetch = FetchDescriptor<SyncMetadata>()
        fetch.fetchLimit = 1
        _ = try context.fetch(fetch)
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
}
