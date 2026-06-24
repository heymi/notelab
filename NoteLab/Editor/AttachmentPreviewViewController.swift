import Foundation
#if canImport(UIKit)
import UIKit
import PDFKit
import AVKit
import PhotosUI

final class AttachmentPreviewViewController: UIViewController, UIScrollViewDelegate {
    private let attachmentId: UUID
    private let data: Data
    private let fileName: String
    private let type: AttachmentType
    private let livePhotoMotionData: Data?
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
    private var playerController: AVPlayerViewController?
    private var temporaryPreviewURL: URL?
    private var temporaryLivePhotoURLs: [URL] = []
    private var livePhotoView: PHLivePhotoView?
    
    init(attachmentId: UUID, data: Data, fileName: String, type: AttachmentType, livePhotoMotionData: Data? = nil, onDelete: @escaping (UUID) -> Void, onClose: @escaping () -> Void) {
        self.attachmentId = attachmentId
        self.data = data
        self.fileName = fileName
        self.type = type
        self.livePhotoMotionData = livePhotoMotionData
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
        if type == .image, let image = AttachmentImage.image(data: data, fileName: fileName) {
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
            configureLivePhotoIfAvailable(placeholder: image)
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
        } else if type == .video, let url = writeTemporaryPreviewFile() {
            let playerController = AVPlayerViewController()
            playerController.player = AVPlayer(url: url)
            addChild(playerController)
            view.addSubview(playerController.view)
            playerController.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                playerController.view.topAnchor.constraint(equalTo: view.topAnchor),
                playerController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                playerController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                playerController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
            ])
            playerController.didMove(toParent: self)
            self.playerController = playerController
            playerController.player?.play()
        }
    }

    private func writeTemporaryPreviewFile() -> URL? {
        let safeFileName = (fileName as NSString).lastPathComponent
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(attachmentId.uuidString)-\(safeFileName)")
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            try data.write(to: url, options: [.atomic])
            temporaryPreviewURL = url
            return url
        } catch {
            print("Failed to write temp video preview: \(error)")
            return nil
        }
    }

    private func configureLivePhotoIfAvailable(placeholder: UIImage) {
        guard let livePhotoMotionData,
              let stillURL = writeTemporaryLivePhotoResource(data: data, fileName: fileName),
              let motionURL = writeTemporaryLivePhotoResource(data: livePhotoMotionData, fileName: LivePhotoAttachment.motionFileName(for: attachmentId)) else {
            return
        }

        let livePhotoView = PHLivePhotoView()
        livePhotoView.contentMode = .scaleAspectFit
        livePhotoView.backgroundColor = .black
        livePhotoView.isMuted = false
        scrollView.isHidden = true
        view.addSubview(livePhotoView)
        livePhotoView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            livePhotoView.topAnchor.constraint(equalTo: view.topAnchor),
            livePhotoView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            livePhotoView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            livePhotoView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        self.livePhotoView = livePhotoView

        PHLivePhoto.request(
            withResourceFileURLs: [stillURL, motionURL],
            placeholderImage: placeholder,
            targetSize: view.bounds.size == .zero ? UIScreen.main.bounds.size : view.bounds.size,
            contentMode: .aspectFit
        ) { [weak self] livePhoto, info in
            DispatchQueue.main.async {
                guard let self else { return }
                if let livePhoto {
                    livePhotoView.livePhoto = livePhoto
                    livePhotoView.startPlayback(with: .full)
                } else if info[PHLivePhotoInfoErrorKey] != nil {
                    livePhotoView.removeFromSuperview()
                    self.scrollView.isHidden = false
                }
            }
        }
    }

    private func writeTemporaryLivePhotoResource(data: Data, fileName: String) -> URL? {
        let safeFileName = (fileName as NSString).lastPathComponent
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(attachmentId.uuidString)-\(UUID().uuidString)-\(safeFileName)")
        do {
            try data.write(to: url, options: [.atomic])
            temporaryLivePhotoURLs.append(url)
            return url
        } catch {
            print("Failed to write temp live photo resource: \(error)")
            return nil
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

    deinit {
        if let temporaryPreviewURL {
            try? FileManager.default.removeItem(at: temporaryPreviewURL)
        }
        for url in temporaryLivePhotoURLs {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
#endif
