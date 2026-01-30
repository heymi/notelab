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
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    private let closeButton = UIButton(type: .system)
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
        view.addSubview(toolbar)
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        
        toolbar.addSubview(blurView)
        blurView.translatesAutoresizingMaskIntoConstraints = false
        
        closeButton.setTitle("关闭", for: .normal)
        closeButton.setTitleColor(.white, for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        closeButton.backgroundColor = UIColor(white: 1.0, alpha: 0.15)
        closeButton.layer.cornerRadius = 18
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        
        deleteButton.setTitle("删除", for: .normal)
        deleteButton.setTitleColor(.white, for: .normal)
        deleteButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        deleteButton.backgroundColor = UIColor.systemRed.withAlphaComponent(0.85)
        deleteButton.layer.cornerRadius = 18
        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
        
        toolbar.addSubview(closeButton)
        toolbar.addSubview(deleteButton)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 70),
            
            blurView.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor),
            blurView.topAnchor.constraint(equalTo: toolbar.topAnchor),
            blurView.bottomAnchor.constraint(equalTo: toolbar.bottomAnchor),
            
            closeButton.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 20),
            closeButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            closeButton.heightAnchor.constraint(equalToConstant: 36),
            closeButton.widthAnchor.constraint(equalToConstant: 90),
            
            deleteButton.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -20),
            deleteButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            deleteButton.heightAnchor.constraint(equalToConstant: 36),
            deleteButton.widthAnchor.constraint(equalToConstant: 90)
        ])
    }
    
    @objc private func closeTapped() {
        onClose()
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
