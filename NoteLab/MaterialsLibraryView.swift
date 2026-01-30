import SwiftUI
import Combine
import SwiftData
import PDFKit

#if canImport(UIKit)
import UIKit
private typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
private typealias PlatformImage = NSImage
#endif

struct MaterialsLibraryView: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var auth: AuthManager

    @Query(
        filter: #Predicate<LocalAttachment> { att in
            att.deletedAt == nil
        },
        sort: [SortDescriptor(\LocalAttachment.createdAt, order: .reverse)]
    )
    private var attachments: [LocalAttachment]

    @Query(
        filter: #Predicate<LocalNote> { note in
            note.deletedAt == nil
        }
    )
    private var notes: [LocalNote]

    var body: some View {
        if groups.isEmpty {
            ContentUnavailableView("暂无素材", systemImage: "paperclip")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 16),
                        GridItem(.flexible(), spacing: 16),
                        GridItem(.flexible(), spacing: 16)
                    ],
                    spacing: 28
                ) {
                    ForEach(groups) { group in
                        Button {
                            Haptics.shared.play(.selection)
                            router.push(.note(group.noteId))
                        } label: {
                            MaterialGroupCard(group: group)
                        }
                        .buttonStyle(BouncyCardButtonStyle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 100)
            }
        }
    }

    private var groups: [MaterialGroup] {
        guard let ownerId = auth.userId else { return [] }
        let noteLookup = notes
            .filter { $0.ownerId == ownerId }
            .reduce(into: [UUID: LocalNote]()) { $0[$1.id] = $1 }

        let validAttachments = attachments
            .filter { $0.ownerId == ownerId }
            .filter { noteLookup[$0.noteId] != nil }

        let grouped = Dictionary(grouping: validAttachments, by: \.noteId)
        var results: [MaterialGroup] = []
        results.reserveCapacity(grouped.count)

        for (noteId, items) in grouped {
            guard let note = noteLookup[noteId] else { continue }
            let sorted = items.sorted { $0.createdAt > $1.createdAt }
            let newestAt = sorted.first?.createdAt ?? Date.distantPast
            results.append(
                MaterialGroup(
                    id: noteId,
                    noteId: noteId,
                    noteTitle: note.title.isEmpty ? "无标题" : note.title,
                    attachments: sorted,
                    newestAt: newestAt
                )
            )
        }

        return results.sorted { $0.newestAt > $1.newestAt }
    }
}

private struct MaterialGroup: Identifiable {
    let id: UUID
    let noteId: UUID
    let noteTitle: String
    let attachments: [LocalAttachment]
    let newestAt: Date
}

private struct MaterialGroupCard: View {
    let group: MaterialGroup
    private let previewMaxHeight: CGFloat = 104

    private var subtitle: String {
        let count = group.attachments.count
        let dateString = group.newestAt.formatted(date: .numeric, time: .omitted)
        if count > 1 {
            return "\(count) 个文件 | \(dateString)"
        } else {
            return dateString
        }
    }

    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            StackedThumbnailsView(
                attachments: group.attachments,
                previewMaxHeight: previewMaxHeight
            )
            .frame(height: previewMaxHeight)
            .clipped()

            VStack(alignment: .center, spacing: 4) {
                Text(group.noteTitle)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                
                Text(subtitle)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(Theme.secondaryInk.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
        }
    }
}

private struct StackedThumbnailsView: View {
    let attachments: [LocalAttachment]
    let previewMaxHeight: CGFloat
    private let maxStackCount = 3

    private var displayedAttachments: [LocalAttachment] {
        Array(attachments.prefix(maxStackCount))
    }
    
    // Config for stack look
    private var cardHeight: CGFloat {
        min(90, max(72, previewMaxHeight - 10))
    }
    private let verticalOffsetStep: CGFloat = 8
    private let scaleStep: CGFloat = 0.15

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .center) {
                // Render in reverse order so the first item (index 0) is on top
                ForEach(Array(displayedAttachments.enumerated().reversed()), id: \.element.id) { index, attachment in
                    let width = geometry.size.width * scale(for: index)
                    // Offset: Move back items UP slightly to peek out, but keep centered relative to top card
                    // Since we are using ZStack(alignment: .center), we just need to shift them up.
                    // The top card (index 0) stays at 0.
                    let yOffset = -CGFloat(index) * verticalOffsetStep
                    
                    AttachmentThumbView(attachment: attachment)
                        .frame(width: width, height: cardHeight)
                        .shadow(color: Theme.cardShadow.opacity(0.2), radius: 4, x: 0, y: 2)
                        .offset(y: yOffset)
                        .zIndex(Double(3 - index))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            // Important: Shift the entire stack down slightly so the visual center (considering the peek) looks balanced
            .offset(y: CGFloat(maxStackCount - 1) * verticalOffsetStep * 0.5)
        }
    }
    
    private func scale(for index: Int) -> CGFloat {
        // Top item (0) is 1.0, others get smaller
        1.0 - (CGFloat(index) * scaleStep)
    }
}

private struct AttachmentThumbView: View {
    let attachment: LocalAttachment

    @State private var thumbnail: PlatformImage?
    @State private var isLoading = false

    private var fileType: FileType {
        FileType(fileName: attachment.fileName, mimeType: attachment.mimeType)
    }

    var body: some View {
        ZStack {
            if let thumbnail {
                platformImage(thumbnail)
                    .resizable()
                    .scaledToFit()
                    .layoutPriority(1)
                    .overlay(
                        // Add border for non-image types (e.g. PDF thumbnails)
                        Group {
                            if fileType != .image {
                                RoundedRectangle(cornerRadius: 0)
                                    .strokeBorder(Color.gray.opacity(0.2), lineWidth: 1)
                            }
                        }
                    )
            } else if isLoading {
                ProgressView()
            } else {
                // Fallback / File Icon View
                FileIconView(type: fileType, fileName: attachment.fileName)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.gray.opacity(0.2), lineWidth: 1)
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: attachment.id) {
            await loadThumbnailIfNeeded()
        }
    }

    private func platformImage(_ image: PlatformImage) -> Image {
        #if canImport(UIKit)
        return Image(uiImage: image)
        #else
        return Image(nsImage: image)
        #endif
    }

    private func loadThumbnailIfNeeded() async {
        // Only load thumbnails for images and PDFs
        guard fileType == .image || fileType == .pdf else { return }
        
        guard thumbnail == nil else { return }
        if let cached = await Task.detached(priority: .utility, operation: { () -> PlatformImage? in
            guard let data = AttachmentCache.load(attachmentId: attachment.id, fileName: attachment.fileName) else {
                return nil
            }
            return makeThumbnail(from: data)
        }).value {
            thumbnail = cached
            return
        }
        guard !attachment.storagePath.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let data = try await AttachmentStorage.shared.loadAttachmentData(
                attachmentId: attachment.id,
                storagePath: attachment.storagePath,
                fileName: attachment.fileName
            )
            thumbnail = makeThumbnail(from: data)
        } catch {
            return
        }
    }

    private func makeThumbnail(from data: Data) -> PlatformImage? {
        if fileType == .pdf {
            guard let pdfDocument = PDFDocument(data: data),
                  let page = pdfDocument.page(at: 0) else {
                return nil
            }
            let size = CGSize(width: 480, height: 480)
            return page.thumbnail(of: size, for: .mediaBox)
        }
        return PlatformImage(data: data)
    }
}

// MARK: - Helper Views & Types

private struct BouncyCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

private enum FileType {
    case image
    case pdf
    case word
    case excel
    case ppt
    case unknown
    
    init(fileName: String, mimeType: String) {
        let ext = (fileName as NSString).pathExtension.lowercased()
        
        if mimeType.hasPrefix("image/") { self = .image; return }
        if mimeType == "application/pdf" || ext == "pdf" { self = .pdf; return }
        
        switch ext {
        case "doc", "docx", "pages": self = .word
        case "xls", "xlsx", "numbers": self = .excel
        case "ppt", "pptx", "key": self = .ppt
        case "jpg", "jpeg", "png", "gif", "webp", "heic": self = .image
        default: self = .unknown
        }
    }
    
    var iconName: String {
        switch self {
        case .image: return "photo"
        case .pdf: return "doc.text.fill"
        case .word: return "doc.text.fill"
        case .excel: return "tablecells.fill"
        case .ppt: return "rectangle.on.rectangle.angled"
        case .unknown: return "doc.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .image: return .purple
        case .pdf: return .red
        case .word: return .blue
        case .excel: return .green
        case .ppt: return .orange
        case .unknown: return .gray
        }
    }
}

private struct FileIconView: View {
    let type: FileType
    let fileName: String
    
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(type.color.opacity(0.1))
                    .frame(width: 56, height: 56)
                
                Image(systemName: type.iconName)
                    .font(.system(size: 28))
                    .foregroundStyle(type.color)
            }
            
            Text((fileName as NSString).pathExtension.uppercased())
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(type.color)
        }
    }
}
