import Foundation
#if os(macOS)
import AppKit
import PDFKit

// MARK: - Attachment Block Cell Delegate

protocol AttachmentBlockCellViewMacDelegate: AnyObject {
    func attachmentBlockCellDidRequestDelete(_ cell: AttachmentBlockCellViewMac)
    func attachmentBlockCellDidRequestPreview(_ cell: AttachmentBlockCellViewMac)
}

// MARK: - Attachment Block Cell View

final class AttachmentBlockCellViewMac: NSView, BlockCellViewMac {
    weak var delegate: AttachmentBlockCellViewMacDelegate?
    
    private let containerView = NSView()
    private let imageView = NSImageView()
    private let fileNameLabel = NSTextField(labelWithString: "")
    private let fileSizeLabel = NSTextField(labelWithString: "")
    private let deleteButton = NSButton()
    private let loadingIndicator = NSProgressIndicator()
    private let highlightBackgroundView = NSView()
    
    private var blockId: UUID = UUID()
    private var attachmentModel: AttachmentModel?
    private var isSentHighlighted: Bool = false
    
    // MARK: - Colors
    
    private var cardBackgroundColor: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ?
                NSColor(white: 0.15, alpha: 1.0) :
                NSColor(white: 0.98, alpha: 1.0)
        }
    }
    
    private var borderColor: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ?
                NSColor(white: 0.3, alpha: 1.0) :
                NSColor(white: 0.85, alpha: 1.0)
        }
    }
    
    private var sentHighlightColor: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ?
                NSColor(red: 0.3, green: 0.25, blue: 0.05, alpha: 1.0) :
                NSColor(red: 1.0, green: 0.95, blue: 0.64, alpha: 1.0)
        }
    }
    
    // MARK: - Init
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews() {
        wantsLayer = true
        
        // Highlight background
        highlightBackgroundView.wantsLayer = true
        highlightBackgroundView.layer?.backgroundColor = sentHighlightColor.cgColor
        highlightBackgroundView.layer?.cornerRadius = 12
        highlightBackgroundView.isHidden = true
        highlightBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(highlightBackgroundView)
        
        // Container
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = cardBackgroundColor.cgColor
        containerView.layer?.borderColor = borderColor.cgColor
        containerView.layer?.borderWidth = 1
        containerView.layer?.cornerRadius = 12
        containerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(containerView)
        
        // Image view
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(imageView)
        
        // File name label
        fileNameLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        fileNameLabel.textColor = NSColor.labelColor
        fileNameLabel.lineBreakMode = .byTruncatingMiddle
        fileNameLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(fileNameLabel)
        
        // File size label
        fileSizeLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        fileSizeLabel.textColor = NSColor.secondaryLabelColor
        fileSizeLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(fileSizeLabel)
        
        // Delete button
        deleteButton.bezelStyle = .circular
        deleteButton.isBordered = false
        deleteButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Delete")
        deleteButton.target = self
        deleteButton.action = #selector(deleteButtonTapped)
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(deleteButton)
        
        // Loading indicator
        loadingIndicator.style = .spinning
        loadingIndicator.isDisplayedWhenStopped = false
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(loadingIndicator)
        
        NSLayoutConstraint.activate([
            highlightBackgroundView.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            highlightBackgroundView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            highlightBackgroundView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            highlightBackgroundView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            
            containerView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            containerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 80),
            
            imageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            imageView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 60),
            imageView.heightAnchor.constraint(equalToConstant: 60),
            
            fileNameLabel.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 12),
            fileNameLabel.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -12),
            fileNameLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 16),
            
            fileSizeLabel.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 12),
            fileSizeLabel.topAnchor.constraint(equalTo: fileNameLabel.bottomAnchor, constant: 4),
            
            deleteButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            deleteButton.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 12),
            deleteButton.widthAnchor.constraint(equalToConstant: 24),
            deleteButton.heightAnchor.constraint(equalToConstant: 24),
            
            loadingIndicator.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: imageView.centerYAnchor)
        ])
        
        // Add double-click gesture for preview
        let doubleClick = NSClickGestureRecognizer(target: self, action: #selector(handleDoubleClick))
        doubleClick.numberOfClicksRequired = 2
        containerView.addGestureRecognizer(doubleClick)
    }
    
    // MARK: - Configuration
    
    func configure(with block: Block) {
        self.blockId = block.id
        self.attachmentModel = block.attachment
        
        guard let attachment = block.attachment else { return }
        
        fileNameLabel.stringValue = attachment.fileName
        
        // Load thumbnail
        loadThumbnail(for: attachment)
    }
    
    private func loadThumbnail(for attachment: AttachmentModel) {
        loadingIndicator.startAnimation(nil)
        imageView.image = nil
        
        Task { @MainActor in
            var image: NSImage?
            
            // Try to load from storage path first
            if attachment.usesStorage {
                // Check local cache
                if let cachedData = AttachmentCache.load(attachmentId: attachment.id, fileName: attachment.fileName) {
                    image = createThumbnail(from: cachedData, type: attachment.type)
                }
            }
            
            // Fall back to embedded data
            if image == nil, let data = attachment.data {
                image = createThumbnail(from: data, type: attachment.type)
            }
            
            // Set placeholder if no image
            if image == nil {
                let symbolName = attachment.type == .pdf ? "doc.fill" : "photo.fill"
                image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
            }
            
            loadingIndicator.stopAnimation(nil)
            imageView.image = image
            
            // Update file size
            if let data = attachment.data {
                fileSizeLabel.stringValue = formatFileSize(data.count)
            } else {
                fileSizeLabel.stringValue = attachment.type == .pdf ? "PDF 文档" : "图片"
            }
        }
    }
    
    private func createThumbnail(from data: Data, type: AttachmentType) -> NSImage? {
        if type == .pdf {
            guard let pdfDocument = PDFDocument(data: data),
                  let page = pdfDocument.page(at: 0) else { return nil }
            let pageRect = page.bounds(for: .mediaBox)
            let scale: CGFloat = 60 / max(pageRect.width, pageRect.height)
            let thumbnailSize = NSSize(width: pageRect.width * scale, height: pageRect.height * scale)
            return page.thumbnail(of: thumbnailSize, for: .mediaBox)
        } else {
            guard let image = NSImage(data: data) else { return nil }
            return image
        }
    }
    
    private func formatFileSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    // MARK: - Actions
    
    @objc private func deleteButtonTapped() {
        delegate?.attachmentBlockCellDidRequestDelete(self)
    }
    
    @objc private func handleDoubleClick() {
        delegate?.attachmentBlockCellDidRequestPreview(self)
    }
    
    // MARK: - BlockCellViewMac
    
    func setSentHighlight(_ highlighted: Bool) {
        isSentHighlighted = highlighted
        highlightBackgroundView.isHidden = !highlighted
    }
    
    func setMultiSelected(_ selected: Bool) {
        if selected {
            highlightBackgroundView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.06).cgColor
            highlightBackgroundView.isHidden = false
        } else if !isSentHighlighted {
            highlightBackgroundView.isHidden = true
        }
    }
    
    // MARK: - Layout
    
    override var intrinsicContentSize: NSSize {
        return NSSize(width: NSView.noIntrinsicMetric, height: 96)
    }
}

#endif
