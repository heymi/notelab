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
            containerView.heightAnchor.constraint(equalToConstant: 200),
            
            thumbnailImageView.topAnchor.constraint(equalTo: containerView.topAnchor),
            thumbnailImageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            thumbnailImageView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            thumbnailImageView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            
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
        
        infoLabel.text = attachment.type == .image ? nil : attachment.fileName
        thumbnailImageView.image = nil
        
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
            thumbnailImageView.image = UIImage(data: data)
            thumbnailImageView.contentMode = .scaleAspectFill
        } else if type == .pdf {
            // Generate PDF thumbnail
            if let pdfDocument = PDFDocument(data: data), let page = pdfDocument.page(at: 0) {
                let thumbnail = page.thumbnail(of: CGSize(width: 400, height: 400), for: .mediaBox)
                thumbnailImageView.image = thumbnail
            } else {
                thumbnailImageView.image = UIImage(systemName: "doc.text.fill")
            }
            thumbnailImageView.contentMode = .scaleAspectFit
        }
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
        dragHandleView.isHidden = !enabled
    }
}
#endif
