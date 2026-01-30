//
//  NoteLabTests.swift
//  NoteLabTests
//
//  Created by Strictly · · on 2026/1/25.
//

import Testing
import SwiftUI
@testable import NoteLab

struct NoteLabTests {
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
}
