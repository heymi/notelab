import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct NotebookCardView: View {
    let notebook: Notebook
    var size: CGSize = CGSize(width: 160, height: 220)
    var previewImages: [Data] = [] // 可选的预览图片数据

    var body: some View {
        let cornerRadius: CGFloat = 26
        
        // Layout constants derived from size
        let notchDepth: CGFloat = size.width * 0.08
        let notchHeight: CGFloat = size.height * 0.52
        let pageInsetY: CGFloat = size.height * 0.08
        let pageHeight = size.height - pageInsetY
        
        // Center the pages vertically within the available space
        let pageCenterOffsetY = (size.height - pageHeight) * 0.5
        
        // Horizontal offsets for the stacked paper effect
        let backPaperOffsetX: CGFloat = size.width * 0.118
        
        let latestNote = notebook.notes.max { $0.createdAt < $1.createdAt }
        
        // 为每个笔记本生成一个基于 ID 的伪随机旋转角度 (-2 到 2 度)
        let rotationAngle: Double = {
            let seed = notebook.id.uuidString.hashValue
            return Double(seed % 40) / 10.0 - 2.0
        }()

        ZStack(alignment: .topLeading) {
            // 1. Back Layer (Decorative stack - Page 3)
            NotebookPageShape(cornerRadius: cornerRadius)
                .fill(Theme.cardBackground) // 使用主题卡片背景色
                .frame(width: size.width, height: pageHeight)
                .offset(x: backPaperOffsetX, y: pageCenterOffsetY)
                .shadow(color: Color.black.opacity(0.06), radius: 18, x: 0, y: 12)

            // 2. Middle Layer (Decorative stack - Page 2)
            NotebookPageShape(cornerRadius: cornerRadius)
                .fill(Color.notebook(notebook.color).opacity(0.3)) // 颜色跟随封面，使用低透明度
                .frame(width: size.width, height: pageHeight)
                .offset(x: size.width * 0.048, y: pageCenterOffsetY)
                .rotationEffect(.degrees(rotationAngle), anchor: .center) // 添加随机倾斜度

            // 3. Content Layer (The actual note page - Page 1)
            // Sitting directly under the cover
            NoteContentPreviewView(note: latestNote, size: CGSize(width: size.width, height: pageHeight), cornerRadius: cornerRadius, previewImages: previewImages)
                .offset(y: pageCenterOffsetY)
                .blur(radius:10.0) 
            
            // 4. Cover Layer (Tint & Texture)
            // 如果是转场源，我们只在非转场状态下显示封面，或者使用 matchedGeometryEffect
            // 但为了实现“只对内容进行转场”，我们可以将封面作为独立的层，不参与 zoom transition
            // 或者，我们可以让封面在转场开始时淡出
            
            FrostedCoverView(
                notebook: notebook,
                size: size,
                cornerRadius: cornerRadius,
                notchDepth: notchDepth,
                notchHeight: notchHeight
            )
        }
        .frame(width: size.width, height: size.height)
    }
}

// MARK: - Subviews

private struct NoteContentPreviewView: View {
    let note: Note?
    let size: CGSize
    let cornerRadius: CGFloat
    var previewImages: [Data] = []
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // Blue page sits directly under the cover and carries the content
            NotebookPageShape(cornerRadius: cornerRadius)
                .fill(Theme.paper)
            
            VStack(alignment: .leading, spacing: 6) {
                if let note = note {
                    let items = previewItems(for: note)
                    ForEach(items) { item in
                        switch item.kind {
                        case .image(let data):
                            if let image = platformImage(from: data) {
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: size.width - 28, height: (size.width - 28) * 0.5)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
                                    )
                            }
                        case .block(let block, let numberIndex):
                            NotebookPreviewBlockView(block: block, numberIndex: numberIndex)
                        }
                    }
                } else if !previewImages.isEmpty {
                    // Fallback: show first 2 preview images if note missing
                    let imagesToShow = Array(previewImages.prefix(2))
                    ForEach(imagesToShow.indices, id: \.self) { index in
                        if let image = platformImage(from: imagesToShow[index]) {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: size.width - 28, height: (size.width - 28) * 0.5)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(Theme.softShadow, lineWidth: 0.5)
                                )
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 16)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(NotebookPageShape(cornerRadius: cornerRadius))
    }
    
    private func platformImage(from data: Data) -> Image? {
        #if canImport(UIKit)
        guard let uiImage = UIImage(data: data) else { return nil }
        return Image(uiImage: uiImage)
        #elseif canImport(AppKit)
        guard let nsImage = NSImage(data: data) else { return nil }
        return Image(nsImage: nsImage)
        #else
        return nil
        #endif
    }
    
    private func previewItems(for note: Note) -> [PreviewItem] {
        let document = NoteDocument.fromMarkdown(note.content)
        var results: [PreviewItem] = []
        var numberedIndex = 0
        var isInNumberedSequence = false
        
        // Limit the total number of preview items
        let maxItems = 8

        for block in document.blocks {
            if block.kind == .attachment {
                guard let attachment = block.attachment, attachment.type == .image else {
                    continue
                }
                if let data = attachment.data {
                    results.append(.image(data))
                } else if let cached = AttachmentCache.load(attachmentId: attachment.id, fileName: attachment.fileName) {
                    results.append(.image(cached))
                }
                if results.count >= maxItems { break }
                continue
            }
            
            let trimmed = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if block.kind != .table && trimmed.isEmpty {
                continue
            }

            var numberIndex: Int?
            if block.kind == .numbered {
                numberedIndex = isInNumberedSequence ? numberedIndex + 1 : 1
                isInNumberedSequence = true
                numberIndex = numberedIndex
            } else {
                isInNumberedSequence = false
                numberedIndex = 0
            }

            results.append(.block(block: block, numberIndex: numberIndex))
            if results.count >= maxItems {
                break
            }
        }
        return results
    }
}

private struct FrostedCoverView: View {
    let notebook: Notebook
    let size: CGSize
    let cornerRadius: CGFloat
    let notchDepth: CGFloat
    let notchHeight: CGFloat
    
    var body: some View {
        WavyNotebookShape(
            cornerRadius: cornerRadius,
            notchDepth: notchDepth,
            notchHeight: notchHeight
        )
        .fill(
            // Use a gradient to simulate light reflection on plastic/glass
            LinearGradient(
                colors: [
                    Color.white.opacity(0.4), // Milky top
                    Color.white.opacity(0.1)  // Clearer bottom
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay {
            // The color tint
            WavyNotebookShape(
                cornerRadius: cornerRadius,
                notchDepth: notchDepth,
                notchHeight: notchHeight
            )
            .fill(
                LinearGradient(
                    colors: [
                        Color.notebook(notebook.color).opacity(0.45),
                        Color.notebook(notebook.color).opacity(0.32)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            ) // Stronger tint while preserving readability
        }
        // Add a thin stroke to define the edge
        .overlay {
            WavyNotebookShape(
                cornerRadius: cornerRadius,
                notchDepth: notchDepth,
                notchHeight: notchHeight
            )
            .stroke(Color.white.opacity(0.5), lineWidth: 1)
        }
        .shadow(color: Theme.cardShadow, radius: 10, x: 0, y: 6)
        .overlay(alignment: .topLeading) {
            Image(systemName: notebook.iconName)
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Theme.ink.opacity(0.8)) // Darker icon for visibility
                .padding(18)
        }
        .overlay(alignment: .topTrailing) {
            if notebook.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.red)
                    .padding(18)
            }
        }
        .overlay(alignment: .bottomLeading) {
            Text(notebook.title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.ink)
                .lineSpacing(4)
                .padding(18)
                .lineLimit(2)
        }
    }
}

// MARK: - Helper Models & Views

private struct PreviewItem: Identifiable {
    let id = UUID()
    let kind: PreviewItemKind
    
    enum PreviewItemKind {
        case image(Data)
        case block(block: Block, numberIndex: Int?)
    }
    
    static func image(_ data: Data) -> PreviewItem {
        PreviewItem(kind: .image(data))
    }
    
    static func block(block: Block, numberIndex: Int?) -> PreviewItem {
        PreviewItem(kind: .block(block: block, numberIndex: numberIndex))
    }
}

private struct NotebookPreviewBlockView: View {
    let block: Block
    let numberIndex: Int?

    var body: some View {
        switch block.kind {
        case .heading:
            Text(block.text)
                .font(.system(size: headingSize + 1, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.ink.opacity(0.95))
                .lineLimit(2)
        case .quote:
            Text(block.text)
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(Theme.ink.opacity(0.9))
                .lineLimit(2)
        case .bullet:
            prefixRow(text: "•", textColor: Theme.ink.opacity(0.75), alignment: .firstTextBaseline)
        case .numbered:
            prefixRow(text: "\(numberIndex ?? 1).", textColor: Theme.ink.opacity(0.75), alignment: .firstTextBaseline)
        case .todo:
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: (block.isChecked ?? false) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.ink.opacity((block.isChecked ?? false) ? 0.95 : 0.7))
                Text(block.text)
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundStyle(Theme.ink.opacity(0.95))
                    .lineLimit(2)
            }
        case .code:
            Text(block.text)
                .font(.system(size: 15, weight: .regular, design: .monospaced))
                .foregroundStyle(Theme.ink.opacity(0.95))
                .lineLimit(2)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Theme.groupedBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        case .table:
            TablePreviewShape()
                .stroke(Theme.ink.opacity(0.2), lineWidth: 1)
                .background(Theme.groupedBackground)
                .frame(height: 36)
        default:
            Text(block.text)
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(Theme.ink.opacity(0.95))
                .lineLimit(2)
        }
    }

    private var headingSize: CGFloat {
        switch block.level ?? 1 {
        case 1: return 22
        case 2: return 19
        default: return 17
        }
    }

    private func prefixRow(text: String, textColor: Color, alignment: VerticalAlignment) -> some View {
        HStack(alignment: alignment, spacing: 8) {
            Text(text)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(textColor)
                .frame(minWidth: 16, alignment: .trailing)
            Text(block.text)
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
        }
    }
}

private struct TablePreviewShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        let rowCount = 2
        let colCount = 3
        for row in 1..<rowCount {
            let y = rect.minY + rect.height * CGFloat(row) / CGFloat(rowCount)
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        for col in 1..<colCount {
            let x = rect.minX + rect.width * CGFloat(col) / CGFloat(colCount)
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
        }
        return path
    }
}
