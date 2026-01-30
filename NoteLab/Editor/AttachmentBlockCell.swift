import Foundation
import Combine
#if canImport(UIKit)
import UIKit
import PDFKit

protocol AttachmentBlockCellDelegate: AnyObject {
    func attachmentBlockCellDidRequestDelete(_ cell: AttachmentBlockCell)
    func attachmentBlockCellDidRequestPreview(_ cell: AttachmentBlockCell, attachmentId: UUID, data: Data, fileName: String, type: AttachmentType)
    func attachmentBlockCellDidBeginDragging(_ cell: AttachmentBlockCell, locationInWindow: CGPoint)
    func attachmentBlockCellDidDrag(_ cell: AttachmentBlockCell, locationInWindow: CGPoint)
    func attachmentBlockCellDidEndDragging(_ cell: AttachmentBlockCell, locationInWindow: CGPoint)
}

final class AttachmentBlockCell: UITableViewCell {
    static let reuseIdentifier = "AttachmentBlockCell"
    
    weak var delegate: AttachmentBlockCellDelegate?
    
    private let containerView = UIView()
    private let thumbnailImageView = UIImageView()
    private let infoLabel = UILabel()
    private let deleteButton = UIButton(type: .system)
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    
    private var attachmentData: Data?
    private var attachmentType: AttachmentType?
    private var fileName: String?
    private var storagePath: String?
    private var attachmentId: UUID?
    
    private var blockId: UUID = UUID()
    private var isMultiSelected: Bool = false
    private var isSentHighlighted: Bool = false
    private var isDragging: Bool = false
    private var loadTask: Task<Void, Never>?
    
    private let multiSelectBackgroundView = UIView()
    private let sentHighlightBackgroundView = UIView()
    private let dragHandleView = UIImageView()
    private var twoFingerPanGesture: UIPanGestureRecognizer!
    
    private var containerHeightConstraint: NSLayoutConstraint?
    private var containerMaxHeightConstraint: NSLayoutConstraint?
    private var imageAspectRatioConstraint: NSLayoutConstraint?
    
    private var containerBackgroundColor: UIColor {
        UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ?
                UIColor(white: 0.15, alpha: 1.0) :
                UIColor(white: 0.97, alpha: 1.0)
        }
    }
    
    private var containerBorderColor: UIColor {
        UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ?
                UIColor(white: 0.3, alpha: 1.0) :
                UIColor(white: 0.9, alpha: 1.0)
        }
    }
    
    private var infoLabelColor: UIColor {
        UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ?
                UIColor(white: 0.7, alpha: 1.0) :
                UIColor.darkGray
        }
    }
    
    private var dragHandleBackgroundColor: UIColor {
        UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ?
                UIColor(white: 0.3, alpha: 0.5) :
                UIColor.black.withAlphaComponent(0.3)
        }
    }
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private var sentHighlightColor: UIColor {
        UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ?
                UIColor(red: 0.3, green: 0.25, blue: 0.05, alpha: 1.0) :
                UIColor(red: 1.0, green: 0.95, blue: 0.64, alpha: 1.0)
        }
    }

    private func setupViews() {
        sentHighlightBackgroundView.backgroundColor = sentHighlightColor
        sentHighlightBackgroundView.layer.cornerRadius = 12
        sentHighlightBackgroundView.isHidden = true
        contentView.addSubview(sentHighlightBackgroundView)
        sentHighlightBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        
        multiSelectBackgroundView.backgroundColor = UIColor.black.withAlphaComponent(0.06)
        multiSelectBackgroundView.layer.cornerRadius = 12
        multiSelectBackgroundView.isHidden = true
        contentView.addSubview(multiSelectBackgroundView)
        multiSelectBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        
        containerView.backgroundColor = containerBackgroundColor
        containerView.layer.cornerRadius = 12
        containerView.clipsToBounds = true
        containerView.layer.borderWidth = 0.5
        containerView.layer.borderColor = containerBorderColor.cgColor
        
        contentView.addSubview(containerView)
        containerView.translatesAutoresizingMaskIntoConstraints = false
        
        // Default height constraint (will be modified for images)
        let heightConstraint = containerView.heightAnchor.constraint(equalToConstant: 200)
        heightConstraint.priority = .defaultHigh
        self.containerHeightConstraint = heightConstraint
        
        thumbnailImageView.contentMode = .scaleAspectFill
        thumbnailImageView.clipsToBounds = true
        thumbnailImageView.backgroundColor = .white
        
        infoLabel.font = .systemFont(ofSize: 14, weight: .medium)
        infoLabel.textColor = infoLabelColor
        infoLabel.numberOfLines = 1
        
        deleteButton.isHidden = true
        
        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.color = .gray
        
        containerView.addSubview(thumbnailImageView)
        containerView.addSubview(infoLabel)
        containerView.addSubview(deleteButton)
        containerView.addSubview(loadingIndicator)
        
        thumbnailImageView.translatesAutoresizingMaskIntoConstraints = false
        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            sentHighlightBackgroundView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 2),
            sentHighlightBackgroundView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -2),
            sentHighlightBackgroundView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            sentHighlightBackgroundView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            
            multiSelectBackgroundView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 2),
            multiSelectBackgroundView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -2),
            multiSelectBackgroundView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            multiSelectBackgroundView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            heightConstraint,
            
            thumbnailImageView.topAnchor.constraint(equalTo: containerView.topAnchor),
            thumbnailImageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            thumbnailImageView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            {
                let c = thumbnailImageView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
                c.priority = UILayoutPriority(999)
                return c
            }(),
            
            infoLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            infoLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -12),
            infoLabel.trailingAnchor.constraint(lessThanOrEqualTo: deleteButton.leadingAnchor, constant: -12),
            
            deleteButton.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 12),
            deleteButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            deleteButton.widthAnchor.constraint(equalToConstant: 32),
            deleteButton.heightAnchor.constraint(equalToConstant: 32),
            
            loadingIndicator.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: containerView.centerYAnchor)
        ])
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        containerView.addGestureRecognizer(tap)
        
        // Drag handle
        dragHandleView.image = UIImage(systemName: "line.3.horizontal")
        dragHandleView.tintColor = UIColor.white.withAlphaComponent(0.9)
        dragHandleView.contentMode = .scaleAspectFit
        dragHandleView.backgroundColor = dragHandleBackgroundColor
        dragHandleView.layer.cornerRadius = 12
        containerView.addSubview(dragHandleView)
        dragHandleView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            dragHandleView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 12),
            dragHandleView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            dragHandleView.widthAnchor.constraint(equalToConstant: 32),
            dragHandleView.heightAnchor.constraint(equalToConstant: 24)
        ])
        
        // Two-finger pan gesture for dragging
        twoFingerPanGesture = UIPanGestureRecognizer(target: self, action: #selector(handleTwoFingerPan(_:)))
        twoFingerPanGesture.minimumNumberOfTouches = 2
        twoFingerPanGesture.maximumNumberOfTouches = 2
        containerView.addGestureRecognizer(twoFingerPanGesture)
    }
    
    func configure(with block: Block) {
        // Cancel any ongoing load task
        loadTask?.cancel()
        loadTask = nil
        
        self.blockId = block.id
        guard let attachment = block.attachment else { return }
        
        self.attachmentId = attachment.id
        self.attachmentType = attachment.type
        self.fileName = attachment.fileName
        self.storagePath = attachment.storagePath
        self.attachmentData = nil  // Will be loaded
        
        let isFullBleedAttachment = attachment.type == .image || attachment.type == .pdf
        infoLabel.text = isFullBleedAttachment ? nil : attachment.fileName
        thumbnailImageView.image = nil
        
        // Reset layout to default state first
        resetLayout()
        
        if isFullBleedAttachment {
            configureImageLayout()
        }
        
        // Check if we have embedded data (legacy) or need to load from storage
        if let data = attachment.data, !data.isEmpty {
            // Legacy: use embedded data directly
            self.attachmentData = data
            displayThumbnail(data: data, type: attachment.type)
        } else if attachment.usesStorage, let storagePath = attachment.storagePath {
            // New: load from local cache or storage
            loadFromStorage(attachmentId: attachment.id, storagePath: storagePath, fileName: attachment.fileName, type: attachment.type)
        } else {
            // No data available
            thumbnailImageView.image = UIImage(systemName: "photo")
            thumbnailImageView.contentMode = .scaleAspectFit
        }
        
        // Enable dragging by default
        setDraggingEnabled(true)
    }
    
    private func resetLayout() {
        containerView.backgroundColor = containerBackgroundColor
        containerView.layer.borderWidth = 0.5
        dragHandleView.isHidden = false
        thumbnailImageView.contentMode = .scaleAspectFill
        
        // Reset height constraint to default
        containerHeightConstraint?.isActive = false
        containerHeightConstraint = containerView.heightAnchor.constraint(equalToConstant: 200)
        containerHeightConstraint?.priority = .defaultHigh
        containerHeightConstraint?.isActive = true
        
        // Remove aspect ratio constraint if exists
        imageAspectRatioConstraint?.isActive = false
        imageAspectRatioConstraint = nil
        
        // Remove max height constraint if exists
        containerMaxHeightConstraint?.isActive = false
        containerMaxHeightConstraint = nil
    }
    
    private func configureImageLayout() {
        containerView.backgroundColor = .clear
        containerView.layer.borderWidth = 0
        dragHandleView.isHidden = true
        thumbnailImageView.contentMode = .scaleAspectFill
        
        // Height will be determined by aspect ratio when image loads
        // Set a temporary height or let intrinsic size handle it if possible,
        // but for now we wait for image data to set aspect ratio.
    }
    
    private func loadFromStorage(attachmentId: UUID, storagePath: String, fileName: String, type: AttachmentType) {
        // Try local cache first (synchronous, using AttachmentCache directly)
        if let cachedData = AttachmentCache.load(attachmentId: attachmentId, fileName: fileName) {
            self.attachmentData = cachedData
            displayThumbnail(data: cachedData, type: type)
            return
        }
        
        // Show loading indicator and load from storage
        loadingIndicator.startAnimating()
        thumbnailImageView.image = nil
        
        loadTask = Task { [weak self] in
            do {
                let data = try await AttachmentStorage.shared.loadAttachmentData(
                    attachmentId: attachmentId,
                    storagePath: storagePath,
                    fileName: fileName
                )
                
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    self?.attachmentData = data
                    self?.loadingIndicator.stopAnimating()
                    self?.displayThumbnail(data: data, type: type)
                }
            } catch {
                await MainActor.run {
                    self?.loadingIndicator.stopAnimating()
                    self?.thumbnailImageView.image = UIImage(systemName: "exclamationmark.triangle")
                    self?.thumbnailImageView.contentMode = .scaleAspectFit
                    self?.thumbnailImageView.tintColor = .systemOrange
                }
            }
        }
    }
    
    private func displayThumbnail(data: Data, type: AttachmentType) {
        if type == .image {
            if let image = UIImage(data: data) {
                thumbnailImageView.image = image
                thumbnailImageView.contentMode = .scaleAspectFill
                
                // Update layout for image dimensions
                updateImageLayout(for: image)
            }
        } else if type == .pdf {
            // Generate high-resolution PDF thumbnail to avoid blur
            if let pdfDocument = PDFDocument(data: data), let page = pdfDocument.page(at: 0) {
                layoutIfNeeded()
                let pageRect = page.bounds(for: .mediaBox)
                let fallbackWidth = UIScreen.main.bounds.width - 32
                let targetWidth = max(containerView.bounds.width, fallbackWidth)
                let aspectRatio = pageRect.width > 0 ? pageRect.width / pageRect.height : 1
                let targetHeight = min(900, targetWidth / aspectRatio)
                let targetSize = CGSize(width: targetWidth, height: targetHeight)

                if let thumbnail = renderPDFThumbnail(page: page, targetSize: targetSize) {
                    thumbnailImageView.image = thumbnail
                    thumbnailImageView.contentMode = .scaleAspectFill
                    updateImageLayout(for: thumbnail)
                } else {
                    thumbnailImageView.image = UIImage(systemName: "doc.text.fill")
                    thumbnailImageView.contentMode = .scaleAspectFit
                }
            } else {
                thumbnailImageView.image = UIImage(systemName: "doc.text.fill")
                thumbnailImageView.contentMode = .scaleAspectFit
            }
        }
    }

    private func renderPDFThumbnail(page: PDFPage, targetSize: CGSize) -> UIImage? {
        guard targetSize.width > 0, targetSize.height > 0 else { return nil }
        let pageRect = page.bounds(for: .mediaBox)
        guard pageRect.width > 0, pageRect.height > 0 else { return nil }

        let scale = min(targetSize.width / pageRect.width, targetSize.height / pageRect.height)
        let renderSize = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: targetSize))

            let x = (targetSize.width - renderSize.width) * 0.5
            let y = (targetSize.height - renderSize.height) * 0.5
            ctx.cgContext.translateBy(x: x, y: y + renderSize.height)
            ctx.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: ctx.cgContext)
        }
    }
    
    private func updateImageLayout(for image: UIImage) {
        guard image.size.width > 0 && image.size.height > 0 else { return }
        
        // Remove existing aspect ratio constraint
        imageAspectRatioConstraint?.isActive = false
        
        // Calculate aspect ratio
        let aspectRatio = image.size.width / image.size.height
        
        // Create new aspect ratio constraint
        let ratioConstraint = thumbnailImageView.widthAnchor.constraint(equalTo: thumbnailImageView.heightAnchor, multiplier: aspectRatio)
        ratioConstraint.priority = .required
        imageAspectRatioConstraint = ratioConstraint
        ratioConstraint.isActive = true
        
        // Update container height constraint
        containerHeightConstraint?.isActive = false
        
        // Calculate target height based on container width (which is screen width - margins)
        // Since we don't know the exact width here easily without layout pass, 
        // we rely on the aspect ratio constraint and the max height constraint.
        
        // However, we need to constrain the height to be <= 900
        // We can do this by setting a lessThanOrEqualToConstant constraint
        containerMaxHeightConstraint?.isActive = false
        let maxHeightConstraint = containerView.heightAnchor.constraint(lessThanOrEqualToConstant: 900)
        maxHeightConstraint.priority = .required
        containerMaxHeightConstraint = maxHeightConstraint
        maxHeightConstraint.isActive = true
        
        // And we need the container to fit the image height
        // The image view is pinned to container edges.
        // So we just need to let the aspect ratio drive the height, bounded by width and max height.
        // But we need to ensure the container doesn't collapse.
        
        // Actually, for a cell, we usually want to define height. 
        // If we use aspect ratio on the image view (which is pinned to container), 
        // and the container width is fixed by the table view, the height should resolve automatically.
        // But we need to handle the max height case.
        
        // If height > 900, we want to limit it to 900.
        // In that case, aspect fit will handle the width shrinking (centering is handled by image view content mode).
        // But the container itself needs to be 900 high.
        
        // Let's try this:
        // 1. Aspect ratio constraint on containerView (or image view)
        // 2. Width is fixed by parent
        // 3. Height <= 900
        
        // We already added aspect ratio to thumbnailImageView.
        // thumbnailImageView is pinned to containerView.
        // So containerView will try to respect that aspect ratio.
        
        // We need to store the max height constraint to remove it later if needed (e.g. reuse)
        // For simplicity in this method, let's just set the height constraint to be the aspect ratio one?
        // No, `containerHeightConstraint` was an explicit height constraint. We disabled it.
        
        // We need to ensure the container height is determined by the image.
        // If we only have aspect ratio and width, height is determined.
        // If that height > 900, we need to cap it.
        
        // So:
        // containerHeight = min(900, width / aspectRatio)
        // But width is dynamic.
        
        // Solution:
        // Allow the height to be determined by the aspect ratio, but cap it at 900.
        // If it hits 900, the aspect ratio constraint on the VIEW might conflict if we require width to match container.
        // But we want the image to "fit" inside if it's too tall.
        
        // Actually, if we set `thumbnailImageView.contentMode = .scaleAspectFit`, the image view itself can be any size.
        // We want the *container* to hug the image content.
        
        // Let's set the container height constraint to be <= 900.
        // And also equal to (width / aspectRatio) with lower priority?
        
        // Better approach for cell:
        // Calculate the expected height based on current bounds width (if available) or screen width approximation?
        // No, that's flaky.
        
        // Let's use Auto Layout:
        // 1. Image View Aspect Ratio constraint (Priority 999)
        // 2. Image View Height <= 900 (Priority 1000)
        // 3. Image View Width == Container Width (Already set by pinning)
        // 4. Container Height == Image View Height (Already set by pinning)
        
        // If the calculated height from aspect ratio > 900:
        // Constraint 2 forces Height = 900.
        // Constraint 3 forces Width = Container Width.
        // Constraint 1 (Aspect Ratio) will break. 
        // Since contentMode is .scaleAspectFit, the image will just be centered in the 900pt high view. This is exactly what we want.
        
        // So we just need to add the height <= 900 constraint to the container (or image view).
        // And we already disabled the fixed 200 height.
        
        // We need to keep track of this max height constraint to reset it.
        // Let's reuse `containerHeightConstraint` to store the active height-related constraint.
        
        containerHeightConstraint = containerView.heightAnchor.constraint(lessThanOrEqualToConstant: 900)
        containerHeightConstraint?.isActive = true
        
        // We also need to tell the layout system that the height is determined by the aspect ratio.
        // Since we added `ratioConstraint` to `thumbnailImageView` and it is pinned to `containerView`,
        // and `containerView` width is fixed by the cell width, the height should be solvable.
        
        // We set priority to required so the image view forces its height based on width.
        // The container's max height constraint (lessThanOrEqualToConstant: 900) will constrain the container.
        // Since thumbnailImageView.bottomAnchor constraint has priority 999, it will break if the image is taller than 900.
        // The image view will extend beyond the container bottom, but clipsToBounds will cut it off.
        // This achieves top alignment.
        
        ratioConstraint.priority = .required
        imageAspectRatioConstraint = ratioConstraint
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        loadTask?.cancel()
        loadTask = nil
        loadingIndicator.stopAnimating()
        thumbnailImageView.image = nil
        attachmentData = nil
        attachmentId = nil
        storagePath = nil
        
        // Reset layout for reuse
        resetLayout()
    }
    
    func setMultiSelected(_ selected: Bool) {
        multiSelectBackgroundView.isHidden = !selected
        isMultiSelected = selected
        updateHighlightVisibility()
        // Disable dragging when in multi-select mode
        setDraggingEnabled(!selected)
    }
    
    func setSentHighlight(_ highlighted: Bool) {
        isSentHighlighted = highlighted
        updateHighlightVisibility()
    }
    
    private func updateHighlightVisibility() {
        sentHighlightBackgroundView.isHidden = !isSentHighlighted || isMultiSelected
    }
    
    func blockIdentifier() -> UUID {
        blockId
    }
    
    @objc private func handleTap() {
        guard !isDragging else { return }
        guard let data = attachmentData, let fileName = fileName, let type = attachmentType else { return }
        delegate?.attachmentBlockCellDidRequestPreview(self, attachmentId: blockId, data: data, fileName: fileName, type: type)
    }
    
    @objc private func handleTwoFingerPan(_ gesture: UIPanGestureRecognizer) {
        let windowLocation = gesture.location(in: nil)
        switch gesture.state {
        case .began:
            isDragging = true
            Haptics.shared.play(.long(duration: 0.15, intensity: 0.7, sharpness: 0.5))
            
            // Allow shadow to show outside bounds
            contentView.clipsToBounds = false
            self.clipsToBounds = false
            
            UIView.animate(withDuration: 0.2, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.5) {
                self.containerView.transform = CGAffineTransform(scaleX: 1.03, y: 1.03)
                self.contentView.layer.shadowColor = UIColor.black.cgColor
                self.contentView.layer.shadowOpacity = 0.25
                self.contentView.layer.shadowRadius = 16
                self.contentView.layer.shadowOffset = CGSize(width: 0, height: 8)
                self.contentView.layer.shadowPath = UIBezierPath(roundedRect: self.containerView.frame, cornerRadius: 12).cgPath
            }
            delegate?.attachmentBlockCellDidBeginDragging(self, locationInWindow: windowLocation)
            
        case .changed:
            delegate?.attachmentBlockCellDidDrag(self, locationInWindow: windowLocation)
            
        case .ended, .cancelled:
            isDragging = false
            UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0.3) {
                self.containerView.transform = .identity
                self.contentView.layer.shadowOpacity = 0
            } completion: { _ in
                self.contentView.clipsToBounds = true
                self.clipsToBounds = true
            }
            delegate?.attachmentBlockCellDidEndDragging(self, locationInWindow: windowLocation)
            
        default:
            break
        }
    }
    
    func setDraggingEnabled(_ enabled: Bool) {
        twoFingerPanGesture.isEnabled = enabled
        let isFullBleedAttachment = attachmentType == .image || attachmentType == .pdf
        dragHandleView.isHidden = isFullBleedAttachment ? true : !enabled
    }
}
#endif
