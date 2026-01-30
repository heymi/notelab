import Foundation
#if canImport(UIKit)
import UIKit
import PDFKit

final class AttachmentPreviewViewController: UIViewController, UIScrollViewDelegate {
    private let attachmentId: UUID
    private let data: Data
    private let fileName: String
    private let type: AttachmentType
    private let onDelete: (UUID) -> Void
    private let onClose: () -> Void
    
    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let pdfView = PDFView()
    private let toolbar = UIView()
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
    private let closeButton = UIButton(type: .system)
    private let saveButton = UIButton(type: .system)
    private let deleteButton = UIButton(type: .system)
    
    init(attachmentId: UUID, data: Data, fileName: String, type: AttachmentType, onDelete: @escaping (UUID) -> Void, onClose: @escaping () -> Void) {
        self.attachmentId = attachmentId
        self.data = data
        self.fileName = fileName
        self.type = type
        self.onDelete = onDelete
        self.onClose = onClose
        super.init(nibName: nil, bundle: nil)
        modalPresentationCapturesStatusBarAppearance = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var prefersStatusBarHidden: Bool {
        true
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupContent()
        setupToolbar()
    }
    
    private func setupContent() {
        if type == .image, let image = UIImage(data: data) {
            scrollView.delegate = self
            scrollView.minimumZoomScale = 1.0
            scrollView.maximumZoomScale = 3.0
            scrollView.showsVerticalScrollIndicator = false
            scrollView.showsHorizontalScrollIndicator = false
            scrollView.backgroundColor = .black
            
            imageView.image = image
            imageView.contentMode = .scaleAspectFit
            imageView.frame = view.bounds
            
            scrollView.addSubview(imageView)
            view.addSubview(scrollView)
            scrollView.translatesAutoresizingMaskIntoConstraints = false
            
            NSLayoutConstraint.activate([
                scrollView.topAnchor.constraint(equalTo: view.topAnchor),
                scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
            ])
        } else if type == .pdf, let document = PDFDocument(data: data) {
            pdfView.document = document
            pdfView.autoScales = true
            pdfView.backgroundColor = .black
            view.addSubview(pdfView)
            pdfView.translatesAutoresizingMaskIntoConstraints = false
            
            NSLayoutConstraint.activate([
                pdfView.topAnchor.constraint(equalTo: view.topAnchor),
                pdfView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                pdfView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                pdfView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
            ])
        }
    }
    
    private func setupToolbar() {
        toolbar.backgroundColor = .clear
        toolbar.layer.cornerRadius = 28
        toolbar.clipsToBounds = true
        view.addSubview(toolbar)
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        
        toolbar.addSubview(blurView)
        blurView.translatesAutoresizingMaskIntoConstraints = false
        
        // Close Button
        let closeConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: closeConfig), for: .normal)
        closeButton.tintColor = .white
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        
        // Save Button
        let saveConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        saveButton.setImage(UIImage(systemName: "square.and.arrow.up", withConfiguration: saveConfig), for: .normal)
        saveButton.tintColor = .white
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        
        // Delete Button
        let deleteConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        deleteButton.setImage(UIImage(systemName: "trash", withConfiguration: deleteConfig), for: .normal)
        deleteButton.tintColor = .systemRed
        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
        
        toolbar.addSubview(closeButton)
        toolbar.addSubview(saveButton)
        toolbar.addSubview(deleteButton)
        
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            // Toolbar layout (compact capsule)
            toolbar.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toolbar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            toolbar.heightAnchor.constraint(equalToConstant: 56),
            toolbar.widthAnchor.constraint(equalToConstant: 200),
            
            // Blur view fills toolbar
            blurView.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor),
            blurView.topAnchor.constraint(equalTo: toolbar.topAnchor),
            blurView.bottomAnchor.constraint(equalTo: toolbar.bottomAnchor),
            
            // Buttons layout (evenly spaced)
            closeButton.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 8),
            closeButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 56),
            closeButton.heightAnchor.constraint(equalToConstant: 56),
            
            saveButton.centerXAnchor.constraint(equalTo: toolbar.centerXAnchor),
            saveButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            saveButton.widthAnchor.constraint(equalToConstant: 56),
            saveButton.heightAnchor.constraint(equalToConstant: 56),
            
            deleteButton.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -8),
            deleteButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: 56),
            deleteButton.heightAnchor.constraint(equalToConstant: 56)
        ])
    }
    
    @objc private func closeTapped() {
        onClose()
    }
    
    @objc private func saveTapped() {
        var items: [Any] = []
        
        // Prepare items for sharing
        if type == .image, let image = UIImage(data: data) {
            items.append(image)
        } else {
            // For PDF or other data, save as file URL if possible
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            do {
                try data.write(to: tempURL)
                items.append(tempURL)
            } catch {
                print("Failed to write temp file for sharing: \(error)")
                items.append(data) // Fallback to data
            }
        }
        
        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        
        // iPad popover support
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = saveButton
            popover.sourceRect = saveButton.bounds
        }
        
        present(activityVC, animated: true)
    }
    
    @objc private func deleteTapped() {
        let alert = UIAlertController(title: "删除附件", message: "确定要删除该附件吗？", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "删除", style: .destructive) { _ in
            self.onDelete(self.attachmentId)
            self.onClose()
        })
        present(alert, animated: true)
    }
    
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageView
    }
}
#endif
