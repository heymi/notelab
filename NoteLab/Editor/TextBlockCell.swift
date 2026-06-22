import Foundation
import Synchronization
#if canImport(UIKit)
import UIKit
import LinkPresentation
import WebKit

protocol TextBlockCellDelegate: AnyObject {
    func textBlockCellDidChange(_ cell: TextBlockCell, text: String)
    func textBlockCellDidRequestNewBlock(_ cell: TextBlockCell, splitAtLocation location: Int)
    func textBlockCellDidTrigger(_ cell: TextBlockCell, trigger: MarkdownTrigger)
    func textBlockCellSelectionDidChange(_ cell: TextBlockCell, selectedText: String, range: NSRange)
    func textBlockCellDidRequestBackspaceAtStart(_ cell: TextBlockCell)
    func textBlockCellDidToggleTodo(_ cell: TextBlockCell)
    func textBlockCellDidRequestLayoutUpdate(_ cell: TextBlockCell)
    func textBlockCellDidRequestCommand(_ cell: TextBlockCell, command: EditorCommand)
}

private extension NSAttributedString.Key {
    static let noteMarkerHighlightColor = NSAttributedString.Key("noteMarkerHighlightColor")
}

private final class MarkerHighlightLayoutManager: NSLayoutManager {
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)

        guard let textStorage else { return }
        let characterRange = self.characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        textStorage.enumerateAttribute(.noteMarkerHighlightColor, in: characterRange) { value, range, _ in
            guard let color = value as? UIColor else { return }
            let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let visibleRange = NSIntersectionRange(glyphRange, glyphsToShow)
            guard visibleRange.length > 0 else { return }

            self.enumerateLineFragments(forGlyphRange: visibleRange) { _, _, textContainer, lineGlyphRange, _ in
                let lineRange = NSIntersectionRange(lineGlyphRange, visibleRange)
                guard lineRange.length > 0 else { return }

                var rect = self.boundingRect(forGlyphRange: lineRange, in: textContainer)
                guard rect.width > 0, rect.height > 0 else { return }

                rect.origin.x += origin.x - 6
                rect.origin.y += origin.y + rect.height * 0.26
                rect.size.width += 12
                rect.size.height = max(10, rect.height * 0.66)

                self.fillMarkerStroke(rect, color: color, alphaScale: 1.0)
                self.fillMarkerStroke(rect.offsetBy(dx: 2.0, dy: -1.8), color: color, alphaScale: 0.66)
            }
        }
    }

    private func fillMarkerStroke(_ rect: CGRect, color: UIColor, alphaScale: CGFloat) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        let fillColor = color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            ? UIColor(red: red, green: green, blue: blue, alpha: alpha * alphaScale)
            : color.withAlphaComponent(0.28 * alphaScale)
        fillColor.setFill()
        markerPath(in: rect).fill()
    }

    private func markerPath(in rect: CGRect) -> UIBezierPath {
        let path = UIBezierPath()
        let left = rect.minX - jitter(rect, index: 1, amount: 2.5)
        let right = rect.maxX + jitter(rect, index: 2, amount: 3)
        let midX = rect.midX + jitter(rect, index: 3, amount: 5)
        let top = rect.minY + jitter(rect, index: 4, amount: 1.4)
        let bottom = rect.maxY + jitter(rect, index: 5, amount: 1.6)
        let slant = jitter(rect, index: 6, amount: 2.4)

        path.move(to: CGPoint(x: left, y: top + slant))
        path.addLine(to: CGPoint(x: midX, y: top + jitter(rect, index: 7, amount: 1.1)))
        path.addLine(to: CGPoint(x: right, y: top - slant * 0.35))
        path.addLine(to: CGPoint(x: right + jitter(rect, index: 8, amount: 2), y: bottom - slant))
        path.addLine(to: CGPoint(x: midX + jitter(rect, index: 9, amount: 4), y: bottom + jitter(rect, index: 10, amount: 1.2)))
        path.addLine(to: CGPoint(x: left + jitter(rect, index: 11, amount: 2), y: bottom + slant * 0.25))
        path.close()
        return path
    }

    private func jitter(_ rect: CGRect, index: Int, amount: CGFloat) -> CGFloat {
        let seed = Double(rect.minX * 0.17 + rect.minY * 0.31 + CGFloat(index) * 12.9898)
        return CGFloat(sin(seed) * 0.5 + cos(seed * 1.7) * 0.5) * amount
    }
}

private final class PasteAwareTextView: UITextView {
    var onPasteAttachment: ((Data, AttachmentType, String) -> Void)?
    var onPasteLoadingChange: ((Bool) -> Void)?

    override func paste(_ sender: Any?) {
        let pasteboard = UIPasteboard.general
        if let image = pasteboard.image, let data = image.pngData() {
            onPasteAttachment?(data, .image, "pasted-\(Int(Date().timeIntervalSince1970)).png")
            return
        }

        guard let url = pasteURL(from: pasteboard), Self.isSupportedMediaURL(url) else {
            super.paste(sender)
            return
        }

        if url.isFileURL {
            guard let data = try? Data(contentsOf: url),
                  let type = Self.mediaType(fileName: url.lastPathComponent, mimeType: nil) else {
                super.paste(sender)
                return
            }
            onPasteAttachment?(data, type, url.lastPathComponent)
            return
        }

        onPasteLoadingChange?(true)
        Task { [weak self] in
            do {
                let payload = try await Self.downloadMedia(from: url)
                await MainActor.run {
                    self?.onPasteLoadingChange?(false)
                    self?.onPasteAttachment?(payload.data, payload.type, payload.fileName)
                }
            } catch {
                await MainActor.run {
                    self?.onPasteLoadingChange?(false)
                    self?.insertText(url.absoluteString)
                }
            }
        }
    }

    private func pasteURL(from pasteboard: UIPasteboard) -> URL? {
        if let url = pasteboard.url {
            return url
        }
        guard let raw = pasteboard.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: raw) else {
            return nil
        }
        return url
    }

    nonisolated private static func isSupportedMediaURL(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["jpg", "jpeg", "png", "gif", "webp", "heic", "mov", "mp4", "m4v"].contains(ext)
    }

    nonisolated private static func mediaType(fileName: String, mimeType: String?) -> AttachmentType? {
        if let mimeType {
            if mimeType.hasPrefix("image/") {
                return .image
            }
            if mimeType.hasPrefix("video/") {
                return .video
            }
            guard mimeType == "application/octet-stream" else { return nil }
        }
        guard isSupportedMediaURL(URL(fileURLWithPath: fileName)) else { return nil }
        return AttachmentType.from(fileName: fileName)
    }

    nonisolated private static func fileName(from url: URL, response: URLResponse) -> String {
        let suggested = response.suggestedFilename ?? ""
        if !suggested.isEmpty, !URL(fileURLWithPath: suggested).pathExtension.isEmpty {
            return suggested
        }
        let lastPath = url.lastPathComponent
        return lastPath.isEmpty ? "pasted-\(Int(Date().timeIntervalSince1970))" : lastPath
    }

    nonisolated private static func downloadMedia(from url: URL) async throws -> (data: Data, type: AttachmentType, fileName: String) {
        let (data, response) = try await URLSession.shared.data(from: url)
        let fileName = fileName(from: url, response: response)
        guard let type = mediaType(fileName: fileName, mimeType: response.mimeType) else {
            throw URLError(.unsupportedURL)
        }
        return (data, type, fileName)
    }
}

private enum TweetLinkPreviewDetector {
    nonisolated static func firstTweetURL(in text: String) -> URL? {
        guard let regex = try? NSRegularExpression(
            pattern: #"https?://[^\s<>\]\)"']+"#,
            options: [.caseInsensitive]
        ) else {
            return nil
        }
        let nsText = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
        for match in matches {
            let rawURL = nsText.substring(with: match.range)
                .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)]}\"'"))
            guard let url = URL(string: rawURL), isTweetURL(url) else { continue }
            return url
        }
        return nil
    }

    nonisolated private static func isTweetURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        switch host {
        case "x.com", "www.x.com", "twitter.com", "www.twitter.com", "mobile.twitter.com":
            break
        default:
            return false
        }
        let components = url.pathComponents.map { $0.lowercased() }
        return components.contains("status") || components.contains("statuses")
    }
}

private struct TweetPreviewPayload: Codable {
    let url: String?
    let author_name: String?
    let author_url: String?
    let html: String?
}

private enum GitHubLinkPreviewDetector {
    nonisolated static func firstGitHubURL(in text: String) -> URL? {
        guard let regex = try? NSRegularExpression(
            pattern: #"https?://[^\s<>\]\)"']+"#,
            options: [.caseInsensitive]
        ) else {
            return nil
        }
        let nsText = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
        for match in matches {
            let rawURL = nsText.substring(with: match.range)
                .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)]}\"'"))
            guard let url = URL(string: rawURL), isGitHubURL(url) else { continue }
            return url
        }
        return nil
    }

    nonisolated private static func isGitHubURL(_ url: URL) -> Bool {
        url.host?.lowercased() == "github.com" || url.host?.lowercased() == "www.github.com"
    }
}

private enum GitHubPreviewLoader {
    private static let cache = Mutex<[URL: LPLinkMetadata]>([:])

    static func cachedMetadata(for url: URL) -> LPLinkMetadata? {
        if let cached = cache.withLock({ $0[url] }) {
            return cached
        }
        guard let metadata = LinkPreviewDiskCache.loadMetadata(for: url) else { return nil }
        cache.withLock { $0[url] = metadata }
        return metadata
    }

    static func load(from url: URL) async throws -> LPLinkMetadata {
        if let cached = cachedMetadata(for: url) {
            return cached
        }
        let provider = LPMetadataProvider()
        let metadata = try await withCheckedThrowingContinuation { continuation in
            provider.startFetchingMetadata(for: url) { metadata, error in
                if let metadata {
                    continuation.resume(returning: metadata)
                } else {
                    continuation.resume(throwing: error ?? URLError(.cannotLoadFromNetwork))
                }
            }
        }
        cache.withLock { $0[url] = metadata }
        LinkPreviewDiskCache.saveMetadata(metadata, for: url)
        return metadata
    }
}

private enum TweetPreviewLoader {
    private static let cache = Mutex<[URL: TweetPreviewPayload]>([:])
    private static let snapshots = Mutex<[URL: UIImage]>([:])

    static func cachedPayload(for tweetURL: URL) -> TweetPreviewPayload? {
        if let cached = cache.withLock({ $0[tweetURL] }) {
            return cached
        }
        guard let payload: TweetPreviewPayload = LinkPreviewDiskCache.loadJSON(for: tweetURL, suffix: "tweet.json") else { return nil }
        cache.withLock { $0[tweetURL] = payload }
        return payload
    }

    static func cachedSnapshot(for tweetURL: URL) -> UIImage? {
        if let cached = snapshots.withLock({ $0[tweetURL] }) {
            return cached
        }
        guard let image = LinkPreviewDiskCache.loadImage(for: tweetURL) else { return nil }
        snapshots.withLock { $0[tweetURL] = image }
        return image
    }

    static func load(from tweetURL: URL) async throws -> TweetPreviewPayload {
        if let cached = cachedPayload(for: tweetURL) {
            return cached
        }
        var components = URLComponents(string: "https://publish.twitter.com/oembed")!
        components.queryItems = [
            URLQueryItem(name: "omit_script", value: "false"),
            URLQueryItem(name: "url", value: tweetURL.absoluteString)
        ]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let payload = try JSONDecoder().decode(TweetPreviewPayload.self, from: data)
        store(payload, for: tweetURL)
        return payload
    }

    private static func store(_ payload: TweetPreviewPayload, for tweetURL: URL) {
        cache.withLock { $0[tweetURL] = payload }
        LinkPreviewDiskCache.saveJSON(payload, for: tweetURL, suffix: "tweet.json")
    }

    static func storeSnapshot(_ image: UIImage, for tweetURL: URL) {
        snapshots.withLock { $0[tweetURL] = image }
        LinkPreviewDiskCache.saveImage(image, for: tweetURL)
    }

    static func plainText(from html: String) -> String {
        guard let data = html.data(using: .utf8),
              let attributed = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.html],
                documentAttributes: nil
              ) else {
            return html
        }
        return attributed.string
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

private enum LinkPreviewDiskCache {
    private static let directory: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let directory = base.appendingPathComponent("LinkPreviews", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()

    private static func key(for url: URL) -> String {
        Data(url.absoluteString.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func fileURL(for url: URL, suffix: String) -> URL {
        directory.appendingPathComponent("\(key(for: url)).\(suffix)")
    }

    static func loadJSON<T: Decodable>(for url: URL, suffix: String) -> T? {
        guard let data = try? Data(contentsOf: fileURL(for: url, suffix: suffix)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func saveJSON<T: Encodable>(_ value: T, for url: URL, suffix: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: fileURL(for: url, suffix: suffix), options: .atomic)
    }

    static func loadImage(for url: URL) -> UIImage? {
        guard let data = try? Data(contentsOf: fileURL(for: url, suffix: "png")) else { return nil }
        return UIImage(data: data)
    }

    static func saveImage(_ image: UIImage, for url: URL) {
        guard let data = image.pngData() else { return }
        try? data.write(to: fileURL(for: url, suffix: "png"), options: .atomic)
    }

    static func loadMetadata(for url: URL) -> LPLinkMetadata? {
        guard let data = try? Data(contentsOf: fileURL(for: url, suffix: "lpmetadata")) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: LPLinkMetadata.self, from: data)
    }

    static func saveMetadata(_ metadata: LPLinkMetadata, for url: URL) {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: metadata, requiringSecureCoding: true) else { return }
        try? data.write(to: fileURL(for: url, suffix: "lpmetadata"), options: .atomic)
    }
}

final class TextBlockCell: UITableViewCell, UITextViewDelegate, WKNavigationDelegate {
    static let reuseIdentifier = "TextBlockCell"

    weak var delegate: TextBlockCellDelegate?

    private let prefixLabel = UILabel()
    private let checkboxButton = UIButton(type: .system)
    private let textView: UITextView = {
        let storage = NSTextStorage()
        let layoutManager = MarkerHighlightLayoutManager()
        let textContainer = NSTextContainer(size: .zero)
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)
        return PasteAwareTextView(frame: .zero, textContainer: textContainer)
    }()
    private let hStack = UIStackView()
    private let textColumnStack = UIStackView()
    private let pasteLoadingIndicator = UIActivityIndicatorView(style: .medium)
    private let tweetPreviewContainer = UIView()
    private let quoteBorderView = UIView()
    private let multiSelectBackgroundView = UIView()
    private let sentHighlightBackgroundView = UIView()
    private let todoCardBackgroundView = UIView()
    private var tweetPreviewTask: Task<Void, Never>?
    private var tweetPreviewURL: URL?
    private var tweetPreviewWebViews: [ObjectIdentifier: URL] = [:]

    private var kind: BlockKind = .paragraph
    private var blockId: UUID = UUID()
    private var numberIndex: Int = 1
    private var headingLevel: Int = 1
    private var todoChecked: Bool = false
    private var isMultiSelected: Bool = false
    private var isSentHighlighted: Bool = false
    private var isVisuallyCollapsed: Bool = false
    private var presentationMode: NoteDetailPresentationMode = .reading
    private var background: NotebookBackground = .default
    private var lastRenderedText: String = ""
    private var isApplyingStyle: Bool = false
    private var fontSizeOffset: CGFloat = 0
    private var pasteLoadingCount: Int = 0
    
    

    private var inkColor: UIColor {
        generatedStyle.map { notebookTextColor(hex: $0.inkHex, alpha: 0.92) } ?? .noteEditorInk
    }
    
    private var bodyColor: UIColor {
        generatedStyle.map { notebookTextColor(hex: $0.inkHex, alpha: 0.82) } ?? .noteEditorBody
    }

    private var secondaryInkColor: UIColor {
        generatedStyle.map { notebookTextColor(hex: $0.secondaryInkHex, alpha: 0.82) } ?? .noteEditorSecondaryInk
    }

    private var checkedTextColor: UIColor {
        generatedStyle.map { notebookTextColor(hex: $0.secondaryInkHex, alpha: 0.62) } ?? .secondaryLabel
    }

    private var accentColor: UIColor {
        usesLightForeground ? UIColor(red: 0.58, green: 0.92, blue: 0.86, alpha: 1) : .noteEditorAccent
    }

    private var accentDeepColor: UIColor {
        usesLightForeground ? UIColor(red: 0.76, green: 0.98, blue: 0.94, alpha: 1) : .noteEditorAccentDeep
    }

    private var codeBackgroundColor: UIColor {
        usesLightForeground ? UIColor(white: 1, alpha: 0.10) : .noteEditorPaperSoft
    }

    private var codeBorderColor: UIColor {
        usesLightForeground ? UIColor(white: 1, alpha: 0.18) : .noteEditorLine
    }

    private var quoteBackgroundColor: UIColor {
        usesLightForeground ? UIColor(white: 1, alpha: 0.08) : .noteEditorPaperSoft
    }
    
    private var quoteBorderColor: UIColor {
        accentColor
    }

    private var cardBackgroundColor: UIColor {
        usesLightForeground ? UIColor(white: 1, alpha: 0.10) : UIColor.noteEditorPaper.withAlphaComponent(0.72)
    }

    private var cardBorderColor: UIColor {
        usesLightForeground ? UIColor(white: 1, alpha: 0.16) : UIColor.noteEditorLine.withAlphaComponent(0.2)
    }

    private var selectionColor: UIColor {
        usesLightForeground ? UIColor(red: 0.72, green: 0.95, blue: 0.90, alpha: 0.18) : .noteEditorSelection
    }

    private var usesLightForeground: Bool {
        generatedStyle?.usesLightForeground ?? false
    }

    private var generatedStyle: NotebookBackgroundStyle? {
        background.generatedStyle(isDarkMode: traitCollection.userInterfaceStyle == .dark)
    }

    private func notebookTextColor(hex: String, alpha: CGFloat) -> UIColor {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&int)
        return UIColor(
            red: CGFloat((int >> 16) & 0xFF) / 255,
            green: CGFloat((int >> 8) & 0xFF) / 255,
            blue: CGFloat(int & 0xFF) / 255,
            alpha: alpha
        )
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

    deinit {
        tweetPreviewTask?.cancel()
    }

    private var sentHighlightColor: UIColor {
        selectionColor
    }

    private func displayFont(size: CGFloat, weight: UIFont.Weight = .semibold) -> UIFont {
        UIFont(name: "STSongti-SC-Black", size: size)
            ?? UIFont(name: "STSongti-SC-Bold", size: size)
            ?? UIFont(name: "SongtiSC-Black", size: size)
            ?? UIFont(name: "SongtiSC-Bold", size: size)
            ?? UIFont.systemFont(ofSize: size, weight: weight)
    }

    private func bodyFont(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        UIFont.systemFont(ofSize: size, weight: weight)
    }

    private func readingBodyFont(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        UIFont.systemFont(ofSize: size, weight: weight)
    }

    private func readingParagraphStyle(size: CGFloat, lineHeightMultiple: CGFloat = 1.44, lineSpacing: CGFloat = 2.5, paragraphSpacing: CGFloat = 7) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        let scale = size / 17
        style.lineHeightMultiple = lineHeightMultiple
        style.lineSpacing = lineSpacing * scale
        style.paragraphSpacing = paragraphSpacing * scale
        return style
    }

    private func setupViews() {
        sentHighlightBackgroundView.backgroundColor = sentHighlightColor
        sentHighlightBackgroundView.layer.cornerRadius = 12
        sentHighlightBackgroundView.isHidden = true
        contentView.addSubview(sentHighlightBackgroundView)
        sentHighlightBackgroundView.translatesAutoresizingMaskIntoConstraints = false

        quoteBorderView.backgroundColor = quoteBorderColor
        quoteBorderView.layer.cornerRadius = 2
        quoteBorderView.isHidden = true
        contentView.addSubview(quoteBorderView)
        quoteBorderView.translatesAutoresizingMaskIntoConstraints = false

        todoCardBackgroundView.layer.cornerRadius = 22
        todoCardBackgroundView.layer.cornerCurve = .continuous
        todoCardBackgroundView.layer.borderWidth = 0.6
        todoCardBackgroundView.layer.shadowColor = UIColor.black.cgColor
        todoCardBackgroundView.layer.shadowOpacity = 0.035
        todoCardBackgroundView.layer.shadowRadius = 18
        todoCardBackgroundView.layer.shadowOffset = CGSize(width: 0, height: 8)
        todoCardBackgroundView.isHidden = true
        contentView.addSubview(todoCardBackgroundView)
        todoCardBackgroundView.translatesAutoresizingMaskIntoConstraints = false

        multiSelectBackgroundView.backgroundColor = selectionColor
        multiSelectBackgroundView.layer.cornerRadius = 12
        multiSelectBackgroundView.isHidden = true
        contentView.addSubview(multiSelectBackgroundView)
        multiSelectBackgroundView.translatesAutoresizingMaskIntoConstraints = false

        hStack.axis = .horizontal
        hStack.alignment = .top
        hStack.spacing = 8
        contentView.addSubview(hStack)
        hStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            sentHighlightBackgroundView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 2),
            sentHighlightBackgroundView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -2),
            sentHighlightBackgroundView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            sentHighlightBackgroundView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            quoteBorderView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 28),
            quoteBorderView.topAnchor.constraint(equalTo: hStack.topAnchor, constant: 2),
            quoteBorderView.bottomAnchor.constraint(equalTo: hStack.bottomAnchor, constant: -2),
            quoteBorderView.widthAnchor.constraint(equalToConstant: 4),
            todoCardBackgroundView.topAnchor.constraint(equalTo: hStack.topAnchor),
            todoCardBackgroundView.bottomAnchor.constraint(equalTo: hStack.bottomAnchor),
            todoCardBackgroundView.leadingAnchor.constraint(equalTo: hStack.leadingAnchor),
            todoCardBackgroundView.trailingAnchor.constraint(equalTo: hStack.trailingAnchor),
            multiSelectBackgroundView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 2),
            multiSelectBackgroundView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -2),
            multiSelectBackgroundView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            multiSelectBackgroundView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            hStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            hStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            hStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            hStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24)
        ])

        prefixLabel.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        prefixLabel.textColor = secondaryInkColor
        prefixLabel.setContentHuggingPriority(.required, for: .horizontal)
        prefixLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        checkboxButton.setImage(UIImage(systemName: "circle"), for: .normal)
        checkboxButton.tintColor = secondaryInkColor
        checkboxButton.addTarget(self, action: #selector(toggleCheckbox), for: .touchUpInside)
        checkboxButton.setContentHuggingPriority(.required, for: .horizontal)
        checkboxButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        textView.font = bodyFont(size: 17)
        textView.textColor = inkColor
        textView.tintColor = accentDeepColor
        textView.backgroundColor = .clear
        textView.isScrollEnabled = false
        textView.delegate = self
        (textView as? PasteAwareTextView)?.onPasteAttachment = { [weak self] data, type, fileName in
            guard let self else { return }
            delegate?.textBlockCellDidRequestCommand(self, command: .insertAttachment(data: data, type: type, fileName: fileName))
        }
        (textView as? PasteAwareTextView)?.onPasteLoadingChange = { [weak self] isLoading in
            self?.setPasteLoading(isLoading)
        }
        textView.textContainerInset = UIEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)
        textView.textContainer.lineFragmentPadding = 0
        // Must use high priority to ensure textView expands properly when content changes (e.g., paste)
        textView.setContentCompressionResistancePriority(.required, for: .vertical)
        textView.setContentHuggingPriority(.defaultHigh, for: .vertical)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        textColumnStack.axis = .vertical
        textColumnStack.alignment = .fill
        textColumnStack.spacing = 6
        textColumnStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textColumnStack.setContentHuggingPriority(.defaultLow, for: .horizontal)

        pasteLoadingIndicator.hidesWhenStopped = true
        pasteLoadingIndicator.color = accentDeepColor
        pasteLoadingIndicator.stopAnimating()

        tweetPreviewContainer.isHidden = true
        tweetPreviewContainer.clipsToBounds = true
        tweetPreviewContainer.layer.cornerRadius = 14
        tweetPreviewContainer.setContentCompressionResistancePriority(.required, for: .vertical)

        hStack.addArrangedSubview(prefixLabel)
        hStack.addArrangedSubview(checkboxButton)
        textColumnStack.addArrangedSubview(textView)
        textColumnStack.addArrangedSubview(pasteLoadingIndicator)
        textColumnStack.addArrangedSubview(tweetPreviewContainer)
        hStack.addArrangedSubview(textColumnStack)

        NSLayoutConstraint.activate([
            checkboxButton.widthAnchor.constraint(equalToConstant: 24),
            checkboxButton.heightAnchor.constraint(equalToConstant: 24)
        ])

        applyAdaptiveColors()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else { return }
        applyAdaptiveColors()
        applyStyle()
    }

    private func applyAdaptiveColors() {
        sentHighlightBackgroundView.backgroundColor = sentHighlightColor
        quoteBorderView.backgroundColor = quoteBorderColor
        todoCardBackgroundView.backgroundColor = cardBackgroundColor
        todoCardBackgroundView.layer.borderColor = cardBorderColor.cgColor
        multiSelectBackgroundView.backgroundColor = selectionColor
        prefixLabel.textColor = secondaryInkColor
        textView.textColor = inkColor
        textView.tintColor = accentDeepColor
    }

    func setMultiSelected(_ selected: Bool) {
        multiSelectBackgroundView.isHidden = !selected
        isMultiSelected = selected
        updateHighlightVisibility()
    }

    func setSentHighlight(_ highlighted: Bool) {
        isSentHighlighted = highlighted
        updateHighlightVisibility()
    }

    private func updateHighlightVisibility() {
        sentHighlightBackgroundView.isHidden = !isSentHighlighted || isMultiSelected
    }

    func setContentInteraction(editable: Bool, selectable: Bool) {
        textView.isEditable = editable && !isVisuallyCollapsed
        textView.isSelectable = selectable && !isVisuallyCollapsed
        textView.isUserInteractionEnabled = (editable || selectable) && !isVisuallyCollapsed
    }

    func setContentInteractionEnabled(_ enabled: Bool) {
        setContentInteraction(editable: enabled, selectable: enabled)
    }

    func setVisuallyCollapsed(_ collapsed: Bool) {
        isVisuallyCollapsed = collapsed
        contentView.isHidden = collapsed
        isUserInteractionEnabled = !collapsed
        textColumnStack.isHidden = collapsed
        textView.isHidden = collapsed
        prefixLabel.isHidden = collapsed || prefixLabel.isHidden
        checkboxButton.isHidden = collapsed || checkboxButton.isHidden
        quoteBorderView.isHidden = true
        multiSelectBackgroundView.isHidden = true
        sentHighlightBackgroundView.isHidden = true
    }

    func configure(with block: Block, numberIndex: Int, presentationMode: NoteDetailPresentationMode = .reading, background: NotebookBackground = .default) {
        isVisuallyCollapsed = false
        contentView.isHidden = false
        isUserInteractionEnabled = true
        self.presentationMode = presentationMode
        self.background = background
        textView.isHidden = false
        self.kind = block.kind
        self.blockId = block.id
        self.numberIndex = numberIndex
        self.headingLevel = block.level ?? 1
        self.todoChecked = block.isChecked ?? false
        self.fontSizeOffset = block.fontSizeOffset ?? 0
        textView.text = block.text
        applyAdaptiveColors()
        applyStyle()
        updateLinkPreview(for: block.text)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        clearTweetPreview()
        pasteLoadingCount = 0
        pasteLoadingIndicator.stopAnimating()
        delegate = nil
    }

    func blockIdentifier() -> UUID {
        blockId
    }

    private func applyStyle() {
        applyStyle(animated: false)
    }
    
    private func applyStyle(animated: Bool) {
        isApplyingStyle = true
        defer { isApplyingStyle = false }
        
        prefixLabel.isHidden = true
        checkboxButton.isHidden = true
        quoteBorderView.isHidden = true
        todoCardBackgroundView.isHidden = true
        textView.textColor = inkColor
        textView.backgroundColor = .clear
        textView.layer.cornerRadius = 0
        textView.layer.borderWidth = 0
        textView.textContainerInset = UIEdgeInsets(top: 7, left: 0, bottom: 7, right: 0)
        hStack.alignment = .top
        hStack.spacing = presentationMode.isEditing ? 8 : 11
        hStack.isLayoutMarginsRelativeArrangement = false
        
        let currentText = textView.text ?? ""
        let savedSelection = textView.selectedRange
        
        // Default paragraph style with good line spacing
        let defaultParagraphStyle = NSMutableParagraphStyle()
        let defaultScale = (17 + fontSizeOffset) / 17
        defaultParagraphStyle.lineSpacing = 6 * defaultScale
        defaultParagraphStyle.lineHeightMultiple = 1.2

        if presentationMode.isEditing {
            applyPlainEditingStyle(currentText: currentText, paragraphStyle: defaultParagraphStyle, animated: animated)
            restoreSelection(savedSelection)
            updateTypingAttributes(paragraphStyle: defaultParagraphStyle)
            lastRenderedText = currentText
            return
        }

        switch kind {
        case .heading:
            let baseSize: CGFloat
            switch headingLevel {
            case 1: baseSize = 31
            case 2: baseSize = 23
            case 3: baseSize = 19
            default: baseSize = 18
            }
            let size = baseSize + fontSizeOffset
            let scale = size / baseSize
            let headingParagraphStyle = NSMutableParagraphStyle()
            headingParagraphStyle.lineSpacing = (headingLevel == 1 ? 2 : 4) * scale
            headingParagraphStyle.lineHeightMultiple = headingLevel == 1 ? 1.08 : 1.16
            headingParagraphStyle.paragraphSpacingBefore = headingLevel == 1 ? 16 : 12
            headingParagraphStyle.paragraphSpacing = headingLevel == 1 ? 8 : 6
            let attrString = NSMutableAttributedString(string: currentText)
            attrString.addAttribute(.paragraphStyle, value: headingParagraphStyle, range: NSMakeRange(0, attrString.length))
            let headingFont = headingLevel == 1 ? displayFont(size: size) : bodyFont(size: size, weight: .bold)
            attrString.addAttribute(.font, value: headingFont, range: NSMakeRange(0, attrString.length))
            attrString.addAttribute(.foregroundColor, value: inkColor, range: NSMakeRange(0, attrString.length))
            applyInlineMarkdownStyles(to: attrString, baseFont: headingFont)
            setAttributedTextAnimated(attrString, animated: animated)
            textView.textContainerInset = UIEdgeInsets(top: headingLevel == 1 ? 15 : 12, left: 0, bottom: headingLevel == 1 ? 10 : 7, right: 0)
            
        case .quote:
            textView.backgroundColor = quoteBackgroundColor
            textView.layer.cornerRadius = 18
            
            let size = 17 + fontSizeOffset
            let quoteParagraphStyle = readingParagraphStyle(size: size, lineHeightMultiple: 1.42, lineSpacing: 3, paragraphSpacing: 7)
            let attrString = NSMutableAttributedString(string: currentText)
            attrString.addAttribute(.paragraphStyle, value: quoteParagraphStyle, range: NSMakeRange(0, attrString.length))
            let quoteFont = readingBodyFont(size: size, weight: .regular)
            attrString.addAttribute(.font, value: quoteFont, range: NSMakeRange(0, attrString.length))
            attrString.addAttribute(.foregroundColor, value: accentDeepColor, range: NSMakeRange(0, attrString.length))
            applyInlineMarkdownStyles(to: attrString, baseFont: quoteFont)
            setAttributedTextAnimated(attrString, animated: animated)
            hStack.layoutMargins = UIEdgeInsets(top: 6, left: 2, bottom: 8, right: 2)
            hStack.isLayoutMarginsRelativeArrangement = true
            textView.textContainerInset = UIEdgeInsets(top: 16, left: 18, bottom: 16, right: 18)
            
        case .bullet:
            prefixLabel.isHidden = false
            prefixLabel.text = "•"
            let size = 16.5 + fontSizeOffset
            prefixLabel.font = UIFont.systemFont(ofSize: 15 + fontSizeOffset, weight: .bold)
            prefixLabel.textColor = accentColor
            let attrString = NSMutableAttributedString(string: currentText)
            let listParagraphStyle = readingParagraphStyle(size: size, lineHeightMultiple: 1.42, lineSpacing: 2.5, paragraphSpacing: 5)
            attrString.addAttribute(.paragraphStyle, value: listParagraphStyle, range: NSMakeRange(0, attrString.length))
            let font = readingBodyFont(size: size)
            attrString.addAttribute(.font, value: font, range: NSMakeRange(0, attrString.length))
            attrString.addAttribute(.foregroundColor, value: bodyColor, range: NSMakeRange(0, attrString.length))
            applyInlineMarkdownStyles(to: attrString, baseFont: font)
            setAttributedTextAnimated(attrString, animated: animated)
            hStack.alignment = .firstBaseline
            textView.textContainerInset = UIEdgeInsets(top: 4, left: 0, bottom: 7, right: 0)
            
        case .numbered:
            prefixLabel.isHidden = false
            prefixLabel.text = "\(numberIndex)."
            let size = 16.5 + fontSizeOffset
            prefixLabel.font = UIFont.monospacedDigitSystemFont(ofSize: size, weight: .medium)
            prefixLabel.textColor = accentDeepColor
            let attrString = NSMutableAttributedString(string: currentText)
            let listParagraphStyle = readingParagraphStyle(size: size, lineHeightMultiple: 1.42, lineSpacing: 2.5, paragraphSpacing: 5)
            attrString.addAttribute(.paragraphStyle, value: listParagraphStyle, range: NSMakeRange(0, attrString.length))
            let font = readingBodyFont(size: size)
            attrString.addAttribute(.font, value: font, range: NSMakeRange(0, attrString.length))
            attrString.addAttribute(.foregroundColor, value: bodyColor, range: NSMakeRange(0, attrString.length))
            applyInlineMarkdownStyles(to: attrString, baseFont: font)
            setAttributedTextAnimated(attrString, animated: animated)
            hStack.alignment = .firstBaseline
            textView.textContainerInset = UIEdgeInsets(top: 4, left: 0, bottom: 7, right: 0)
            
        case .todo:
            checkboxButton.isHidden = false
            hStack.alignment = presentationMode.isEditing ? .top : .center
            todoCardBackgroundView.isHidden = false
            hStack.layoutMargins = UIEdgeInsets(top: 13, left: 16, bottom: 13, right: 16)
            hStack.isLayoutMarginsRelativeArrangement = true
            hStack.spacing = 14
            let size = 16.5 + fontSizeOffset
            let config = UIImage.SymbolConfiguration(pointSize: 21, weight: .regular)
            let name = todoChecked ? "checkmark.circle.fill" : "circle"
            checkboxButton.setImage(UIImage(systemName: name, withConfiguration: config), for: .normal)
            checkboxButton.tintColor = todoChecked ? accentDeepColor : secondaryInkColor
            checkboxButton.imageView?.contentMode = .scaleAspectFit // Prevent distortion
            
            // Adjust text inset to align visually with checkbox
            textView.textContainerInset = UIEdgeInsets(top: 1, left: 0, bottom: 4, right: 0)
            
            let attrString = NSMutableAttributedString(string: currentText)
            let todoParagraphStyle = readingParagraphStyle(size: size, lineHeightMultiple: 1.42, lineSpacing: 2.5, paragraphSpacing: 5)
            attrString.addAttribute(.paragraphStyle, value: todoParagraphStyle, range: NSMakeRange(0, attrString.length))
            let font = readingBodyFont(size: size, weight: .regular)
            attrString.addAttribute(.font, value: font, range: NSMakeRange(0, attrString.length))
            
            if todoChecked {
                attrString.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: NSMakeRange(0, attrString.length))
                attrString.addAttribute(.foregroundColor, value: checkedTextColor, range: NSMakeRange(0, attrString.length))
            } else {
                attrString.addAttribute(.foregroundColor, value: bodyColor, range: NSMakeRange(0, attrString.length))
                applyInlineMarkdownStyles(to: attrString, baseFont: font)
            }
            setAttributedTextAnimated(attrString, animated: animated)
            
        case .code:
            let size = 14.5 + fontSizeOffset
            let scale = size / 14.5
            let codeParagraphStyle = NSMutableParagraphStyle()
            codeParagraphStyle.lineSpacing = 4 * scale
            codeParagraphStyle.lineHeightMultiple = 1.38
            codeParagraphStyle.paragraphSpacing = 4 * scale
            let attrString = NSMutableAttributedString(string: currentText)
            attrString.addAttribute(.paragraphStyle, value: codeParagraphStyle, range: NSMakeRange(0, attrString.length))
            attrString.addAttribute(.font, value: UIFont.monospacedSystemFont(ofSize: size, weight: .regular), range: NSMakeRange(0, attrString.length))
            attrString.addAttribute(.foregroundColor, value: inkColor, range: NSMakeRange(0, attrString.length))
            // Don't apply inline markdown to code blocks
            setAttributedTextAnimated(attrString, animated: animated)
            textView.backgroundColor = codeBackgroundColor
            textView.layer.cornerRadius = 18
            textView.layer.borderWidth = 0.7
            textView.layer.borderColor = codeBorderColor.cgColor
            textView.textContainerInset = UIEdgeInsets(top: 16, left: 18, bottom: 16, right: 18)
            
        default:
            // Paragraph style with inline markdown
            let size = 17 + fontSizeOffset
            let attrString = NSMutableAttributedString(string: currentText)
            let paragraphStyle = readingParagraphStyle(size: size)
            attrString.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSMakeRange(0, attrString.length))
            let font = readingBodyFont(size: size)
            attrString.addAttribute(.font, value: font, range: NSMakeRange(0, attrString.length))
            attrString.addAttribute(.foregroundColor, value: bodyColor, range: NSMakeRange(0, attrString.length))
            applyInlineMarkdownStyles(to: attrString, baseFont: font)
            setAttributedTextAnimated(attrString, animated: animated)
            textView.textContainerInset = UIEdgeInsets(top: 6, left: 0, bottom: 10, right: 0)
        }

        restoreSelection(savedSelection)
        updateTypingAttributes(paragraphStyle: defaultParagraphStyle)

        lastRenderedText = currentText
    }

    private func applyPlainEditingStyle(currentText: String, paragraphStyle: NSMutableParagraphStyle, animated: Bool) {
        switch kind {
        case .bullet:
            prefixLabel.isHidden = false
            prefixLabel.text = "•"
            prefixLabel.font = UIFont.systemFont(ofSize: 18 + fontSizeOffset, weight: .bold)
            prefixLabel.textColor = accentColor
            hStack.alignment = .firstBaseline
            textView.textContainerInset = UIEdgeInsets(top: 4, left: 0, bottom: 5, right: 0)
        case .numbered:
            prefixLabel.isHidden = false
            prefixLabel.text = "\(numberIndex)."
            prefixLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 17 + fontSizeOffset, weight: .semibold)
            prefixLabel.textColor = accentDeepColor
            hStack.alignment = .firstBaseline
            textView.textContainerInset = UIEdgeInsets(top: 4, left: 0, bottom: 5, right: 0)
        case .todo:
            checkboxButton.isHidden = false
            hStack.alignment = .top
            let config = UIImage.SymbolConfiguration(pointSize: 17 + fontSizeOffset, weight: .regular)
            let name = todoChecked ? "checkmark.circle.fill" : "circle"
            checkboxButton.setImage(UIImage(systemName: name, withConfiguration: config), for: .normal)
            checkboxButton.tintColor = todoChecked ? accentDeepColor : secondaryInkColor
            textView.textContainerInset = UIEdgeInsets(top: 2, left: 0, bottom: 4, right: 0)
        case .code:
            textView.textContainerInset = UIEdgeInsets(top: 7, left: 0, bottom: 7, right: 0)
        default:
            textView.textContainerInset = UIEdgeInsets(top: 7, left: 0, bottom: 7, right: 0)
        }

        let size: CGFloat = kind == .code ? 15 + fontSizeOffset : 17 + fontSizeOffset
        let font = kind == .code
            ? UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
            : bodyFont(size: size)
        let attrString = NSMutableAttributedString(string: currentText)
        attrString.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSMakeRange(0, attrString.length))
        attrString.addAttribute(.font, value: font, range: NSMakeRange(0, attrString.length))
        attrString.addAttribute(.foregroundColor, value: todoChecked ? checkedTextColor : bodyColor, range: NSMakeRange(0, attrString.length))
        if kind == .todo && todoChecked {
            attrString.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: NSMakeRange(0, attrString.length))
        }
        setAttributedTextAnimated(attrString, animated: animated)
    }

    private func restoreSelection(_ savedSelection: NSRange) {
        let textLength = (textView.text as NSString).length
        if savedSelection.location <= textLength {
            let clampedLength = min(savedSelection.length, max(0, textLength - savedSelection.location))
            textView.selectedRange = NSRange(location: savedSelection.location, length: clampedLength)
        }
    }

    private func updateTypingAttributes(paragraphStyle: NSMutableParagraphStyle) {
        textView.typingAttributes = [
            .font: textView.font ?? bodyFont(size: 17),
            .foregroundColor: textView.textColor ?? inkColor,
            .paragraphStyle: paragraphStyle
        ]
    }
    
    // MARK: - Inline Markdown Rendering
    
    private func applyInlineMarkdownStyles(to attrString: NSMutableAttributedString, baseFont: UIFont) {
        let text = attrString.string as NSString
        let fullRange = NSRange(location: 0, length: text.length)
        
        // Bold: **text** - process first to handle ** before *
        applyInlinePattern("\\*\\*(.+?)\\*\\*", to: attrString, in: fullRange, style: .bold, baseFont: baseFont)
        
        // Italic: *text* (but not inside bold)
        applyInlinePattern("(?<!\\*)\\*([^*]+?)\\*(?!\\*)", to: attrString, in: fullRange, style: .italic, baseFont: baseFont)
        
        // Inline code: `text`
        applyInlinePattern("`([^`]+)`", to: attrString, in: fullRange, style: .code, baseFont: baseFont)
        
        // Highlight: ==color:text==
        applyHighlightPattern(to: attrString, in: fullRange)
    }
    
    private func applyHighlightPattern(to attrString: NSMutableAttributedString, in range: NSRange) {
        let pattern = "==([A-Za-z]+):([\\s\\S]+?)=="
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        let text = attrString.string as NSString
        let matches = regex.matches(in: text as String, options: [], range: range)
        
        let highlightColors: [String: UIColor] = [
            "yellow": UIColor(red: 1.0, green: 0.88, blue: 0.18, alpha: 0.62),
            "green": UIColor(red: 0.48, green: 0.88, blue: 0.50, alpha: 0.48),
            "blue": UIColor(red: 0.45, green: 0.75, blue: 1.0, alpha: 0.46),
            "pink": UIColor(red: 1.0, green: 0.58, blue: 0.76, alpha: 0.46),
            "orange": UIColor(red: 1.0, green: 0.65, blue: 0.26, alpha: 0.50),
            "purple": UIColor(red: 0.68, green: 0.56, blue: 0.96, alpha: 0.46)
        ]
        
        let markerHiddenFont = UIFont.systemFont(ofSize: 0.1)
        
        for match in matches.reversed() {
            guard match.numberOfRanges >= 3 else { continue }
            let fullMatchRange = match.range(at: 0)
            let colorKeyRange = match.range(at: 1)
            let contentRange = match.range(at: 2)
            
            let colorKey = text.substring(with: colorKeyRange)
            guard !containsInlineMarker(text.substring(with: contentRange)) else { continue }
            let bgColor = highlightColors[colorKey] ?? highlightColors["yellow"]!
            
            attrString.addAttribute(.noteMarkerHighlightColor, value: bgColor, range: contentRange)
            
            // Hide the ==color: prefix and == suffix
            let prefixLength = colorKey.count + 3  // == + color + :
            let prefixRange = NSRange(location: fullMatchRange.location, length: prefixLength)
            let suffixRange = NSRange(location: fullMatchRange.location + fullMatchRange.length - 2, length: 2)
            
            attrString.addAttribute(.foregroundColor, value: UIColor.clear, range: prefixRange)
            attrString.addAttribute(.foregroundColor, value: UIColor.clear, range: suffixRange)
            attrString.addAttribute(.font, value: markerHiddenFont, range: prefixRange)
            attrString.addAttribute(.font, value: markerHiddenFont, range: suffixRange)
        }
    }
    
    private enum InlineStyle {
        case bold
        case italic
        case code
    }
    
    private func applyInlinePattern(_ pattern: String, to attrString: NSMutableAttributedString, in range: NSRange, style: InlineStyle, baseFont: UIFont) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        let text = attrString.string as NSString
        let matches = regex.matches(in: text as String, options: [], range: range)
        
        let markerHiddenFont = UIFont.systemFont(ofSize: 0.1)
        let codeBg = codeBackgroundColor
        
        for match in matches.reversed() {
            guard match.numberOfRanges >= 2 else { continue }
            let fullRange = match.range(at: 0)
            let innerRange = match.range(at: 1)
            guard !containsInlineMarker(text.substring(with: innerRange)) else { continue }
            
            // Apply style to inner content
            switch style {
            case .bold:
                let boldFont = UIFont.systemFont(ofSize: baseFont.pointSize, weight: .medium)
                attrString.addAttribute(.font, value: boldFont, range: innerRange)
                // Hide the ** markers
                let prefixRange = NSRange(location: fullRange.location, length: 2)
                let suffixRange = NSRange(location: fullRange.location + fullRange.length - 2, length: 2)
                attrString.addAttribute(.foregroundColor, value: UIColor.clear, range: prefixRange)
                attrString.addAttribute(.foregroundColor, value: UIColor.clear, range: suffixRange)
                attrString.addAttribute(.font, value: markerHiddenFont, range: prefixRange)
                attrString.addAttribute(.font, value: markerHiddenFont, range: suffixRange)
                
            case .italic:
                let italicFont = UIFont.italicSystemFont(ofSize: baseFont.pointSize)
                attrString.addAttribute(.font, value: italicFont, range: innerRange)
                // Hide the * markers
                let prefixRange = NSRange(location: fullRange.location, length: 1)
                let suffixRange = NSRange(location: fullRange.location + fullRange.length - 1, length: 1)
                attrString.addAttribute(.foregroundColor, value: UIColor.clear, range: prefixRange)
                attrString.addAttribute(.foregroundColor, value: UIColor.clear, range: suffixRange)
                attrString.addAttribute(.font, value: markerHiddenFont, range: prefixRange)
                attrString.addAttribute(.font, value: markerHiddenFont, range: suffixRange)
                
            case .code:
                let codeFont = UIFont.monospacedSystemFont(ofSize: baseFont.pointSize * 0.9, weight: .regular)
                attrString.addAttribute(.font, value: codeFont, range: innerRange)
                attrString.addAttribute(.backgroundColor, value: codeBg, range: innerRange)
                attrString.addAttribute(.foregroundColor, value: accentDeepColor, range: innerRange)
                // Hide the ` markers
                let prefixRange = NSRange(location: fullRange.location, length: 1)
                let suffixRange = NSRange(location: fullRange.location + fullRange.length - 1, length: 1)
                attrString.addAttribute(.foregroundColor, value: UIColor.clear, range: prefixRange)
                attrString.addAttribute(.foregroundColor, value: UIColor.clear, range: suffixRange)
                attrString.addAttribute(.font, value: markerHiddenFont, range: prefixRange)
                attrString.addAttribute(.font, value: markerHiddenFont, range: suffixRange)
            }
        }
    }

    private func containsInlineMarker(_ text: String) -> Bool {
        text.contains("**") || text.contains("*") || text.contains("`") || text.contains("==")
    }
    
    private func setAttributedTextAnimated(_ attrString: NSAttributedString, animated: Bool) {
        if animated && !isApplyingStyle {
            UIView.transition(with: textView, duration: 0.15, options: [.transitionCrossDissolve, .allowUserInteraction]) {
                self.textView.attributedText = attrString
            }
        } else {
            textView.attributedText = attrString
        }
    }
    
    // MARK: - Inline Format Insertion
    
    func insertInlineFormat(prefix: String, suffix: String, selectedRange: NSRange?) {
        let currentText = textView.text ?? ""
        
        if let range = selectedRange, range.length > 0 {
            // Wrap selected text
            let nsString = currentText as NSString
            let selectedText = nsString.substring(with: range)
            let replacement = prefix + selectedText + suffix
            
            // Check if already formatted - if so, remove formatting
            let beforeIndex = max(0, range.location - prefix.count)
            let afterIndex = min(currentText.count, range.location + range.length + suffix.count)
            
            if beforeIndex >= 0 && range.location >= prefix.count {
                let beforeRange = NSRange(location: beforeIndex, length: prefix.count)
                let afterRange = NSRange(location: range.location + range.length, length: suffix.count)
                
                if afterRange.location + afterRange.length <= currentText.count {
                    let beforeText = nsString.substring(with: beforeRange)
                    let afterText = nsString.substring(with: afterRange)
                    
                    if beforeText == prefix && afterText == suffix {
                        // Remove formatting
                        var newText = currentText
                        let suffixStartIndex = newText.index(newText.startIndex, offsetBy: afterRange.location)
                        let suffixEndIndex = newText.index(suffixStartIndex, offsetBy: suffix.count)
                        newText.removeSubrange(suffixStartIndex..<suffixEndIndex)
                        
                        let prefixStartIndex = newText.index(newText.startIndex, offsetBy: beforeRange.location)
                        let prefixEndIndex = newText.index(prefixStartIndex, offsetBy: prefix.count)
                        newText.removeSubrange(prefixStartIndex..<prefixEndIndex)
                        
                        textView.text = newText
                        textView.selectedRange = NSRange(location: beforeRange.location, length: range.length)
                        delegate?.textBlockCellDidChange(self, text: newText)
                        applyStyle(animated: true)
                        return
                    }
                }
            }
            
            // Apply formatting
            textView.textStorage.replaceCharacters(in: range, with: replacement)
            let newCursorPosition = range.location + replacement.count
            textView.selectedRange = NSRange(location: range.location + prefix.count, length: selectedText.count)
            delegate?.textBlockCellDidChange(self, text: textView.text)
            applyStyle(animated: true)
        } else {
            // No selection - insert format markers with cursor between them
            let cursorPosition = textView.selectedRange.location
            let placeholder = prefix + suffix
            let nsString = (currentText as NSString).mutableCopy() as! NSMutableString
            nsString.insert(placeholder, at: cursorPosition)
            textView.text = nsString as String
            textView.selectedRange = NSRange(location: cursorPosition + prefix.count, length: 0)
            delegate?.textBlockCellDidChange(self, text: textView.text)
            applyStyle(animated: true)
        }
    }

    @objc private func toggleCheckbox() {
        guard kind == .todo else { return }
        Haptics.shared.play(.selection)
        delegate?.textBlockCellDidToggleTodo(self)
    }

    func textViewDidChange(_ textView: UITextView) {
        delegate?.textBlockCellDidChange(self, text: textView.text)
        // Request layout update to handle height changes (e.g., after paste)
        delegate?.textBlockCellDidRequestLayoutUpdate(self)
        
        // Re-apply inline markdown styles if text changed and contains markdown markers
        let currentText = textView.text ?? ""
        if !presentationMode.isEditing && currentText != lastRenderedText && kind != .code {
            // Check if text contains any markdown patterns that need rendering
            if containsInlineMarkdown(currentText) {
                applyStyle(animated: true)
            } else {
                lastRenderedText = currentText
            }
        }
        updateLinkPreview(for: currentText)
    }

    private func setPasteLoading(_ isLoading: Bool) {
        pasteLoadingCount = max(0, pasteLoadingCount + (isLoading ? 1 : -1))
        if pasteLoadingCount > 0 {
            pasteLoadingIndicator.startAnimating()
        } else {
            pasteLoadingIndicator.stopAnimating()
        }
        delegate?.textBlockCellDidRequestLayoutUpdate(self)
    }

    private func updateLinkPreview(for text: String) {
        guard kind != .code else {
            clearTweetPreview()
            return
        }
        if let url = TweetLinkPreviewDetector.firstTweetURL(in: text) {
            updateTweetPreview(url: url)
            return
        }
        if let url = GitHubLinkPreviewDetector.firstGitHubURL(in: text) {
            updateGitHubPreview(url: url)
            return
        }
        clearTweetPreview()
    }

    private func updateTweetPreview(url: URL) {
        guard tweetPreviewURL != url else { return }

        tweetPreviewTask?.cancel()
        tweetPreviewURL = url
        if let cachedPayload = TweetPreviewLoader.cachedPayload(for: url) {
            renderTweetPreview(url: url, payload: cachedPayload)
            return
        }
        renderTweetPreview(url: url, payload: nil)

        tweetPreviewTask = Task { [weak self] in
            do {
                let payload = try await TweetPreviewLoader.load(from: url)
                await MainActor.run {
                    guard let self, self.tweetPreviewURL == url else { return }
                    self.renderTweetPreview(url: url, payload: payload)
                }
            } catch {
                await MainActor.run {
                    guard let self, self.tweetPreviewURL == url else { return }
                    self.tweetPreviewTask = nil
                }
            }
        }
    }

    private func updateGitHubPreview(url: URL) {
        guard tweetPreviewURL != url else { return }

        tweetPreviewTask?.cancel()
        tweetPreviewURL = url
        if let cachedMetadata = GitHubPreviewLoader.cachedMetadata(for: url) {
            renderGitHubPreview(url: url, metadata: cachedMetadata)
            return
        }
        renderGitHubPreview(url: url, metadata: nil)

        tweetPreviewTask = Task { [weak self] in
            do {
                let metadata = try await GitHubPreviewLoader.load(from: url)
                await MainActor.run {
                    guard let self, self.tweetPreviewURL == url else { return }
                    self.renderGitHubPreview(url: url, metadata: metadata)
                }
            } catch {
                await MainActor.run {
                    guard let self, self.tweetPreviewURL == url else { return }
                    self.tweetPreviewTask = nil
                }
            }
        }
    }

    private func renderTweetPreview(url: URL, payload: TweetPreviewPayload?) {
        removeTweetPreviewSubviews()
        let card = makeTweetPreviewCard(url: url, payload: payload)
        tweetPreviewContainer.addSubview(card)
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: tweetPreviewContainer.topAnchor),
            card.bottomAnchor.constraint(equalTo: tweetPreviewContainer.bottomAnchor),
            card.leadingAnchor.constraint(equalTo: tweetPreviewContainer.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: tweetPreviewContainer.trailingAnchor)
        ])
        tweetPreviewContainer.isHidden = false
        delegate?.textBlockCellDidRequestLayoutUpdate(self)
    }

    private func renderGitHubPreview(url: URL, metadata: LPLinkMetadata?) {
        removeTweetPreviewSubviews()
        let card = makeGitHubPreviewCard(url: url, metadata: metadata)
        tweetPreviewContainer.addSubview(card)
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: tweetPreviewContainer.topAnchor),
            card.bottomAnchor.constraint(equalTo: tweetPreviewContainer.bottomAnchor),
            card.leadingAnchor.constraint(equalTo: tweetPreviewContainer.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: tweetPreviewContainer.trailingAnchor)
        ])
        tweetPreviewContainer.isHidden = false
        delegate?.textBlockCellDidRequestLayoutUpdate(self)
    }

    private func makeGitHubPreviewCard(url: URL, metadata: LPLinkMetadata?) -> UIView {
        let card = UIStackView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.axis = .vertical
        card.spacing = 10
        card.layoutMargins = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        card.isLayoutMarginsRelativeArrangement = true
        card.backgroundColor = .secondarySystemBackground
        card.layer.cornerRadius = 14
        card.layer.borderWidth = 0.7
        card.layer.borderColor = UIColor.separator.withAlphaComponent(0.35).cgColor

        let header = makePreviewHeader(title: "GitHub", url: url)
        card.addArrangedSubview(header)

        let previewHeight: CGFloat = 180
        if let metadata {
            let linkView = LPLinkView(metadata: metadata)
            linkView.translatesAutoresizingMaskIntoConstraints = false
            card.addArrangedSubview(linkView)
            linkView.heightAnchor.constraint(equalToConstant: previewHeight).isActive = true
        } else {
            let loadingView = makeTweetLoadingView()
            card.addArrangedSubview(loadingView)
            loadingView.heightAnchor.constraint(equalToConstant: previewHeight).isActive = true
        }
        return card
    }

    private func makeTweetPreviewCard(url: URL, payload: TweetPreviewPayload?) -> UIView {
        let card = UIStackView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.axis = .vertical
        card.spacing = 8
        card.layoutMargins = UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        card.isLayoutMarginsRelativeArrangement = true
        card.backgroundColor = .secondarySystemBackground
        card.layer.cornerRadius = 14
        card.layer.borderWidth = 0.7
        card.layer.borderColor = UIColor.separator.withAlphaComponent(0.35).cgColor

        let author = payload?.author_name ?? url.pathComponents.dropFirst().first.map { "@\($0)" } ?? "X"
        let header = makePreviewHeader(title: "X · \(author)", url: url)

        card.addArrangedSubview(header)
        if let snapshot = TweetPreviewLoader.cachedSnapshot(for: url) {
            let mediaView = UIView()
            mediaView.translatesAutoresizingMaskIntoConstraints = false
            mediaView.clipsToBounds = true
            mediaView.layer.cornerRadius = 10

            let imageView = UIImageView(image: snapshot)
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            mediaView.addSubview(imageView)

            let openMediaButton = UIButton(type: .system)
            openMediaButton.translatesAutoresizingMaskIntoConstraints = false
            openMediaButton.setImage(UIImage(systemName: "play.circle.fill"), for: .normal)
            openMediaButton.tintColor = UIColor.white.withAlphaComponent(0.92)
            openMediaButton.backgroundColor = UIColor.black.withAlphaComponent(0.18)
            openMediaButton.addAction(UIAction { [weak self, weak mediaView] _ in
                guard let self, let mediaView, let html = payload?.html else {
                    UIApplication.shared.open(url)
                    return
                }
                mediaView.subviews.forEach { $0.removeFromSuperview() }
                let webView = self.makeTweetWebView(html: html, url: url, cachesSnapshot: false)
                mediaView.addSubview(webView)
                NSLayoutConstraint.activate([
                    webView.topAnchor.constraint(equalTo: mediaView.topAnchor),
                    webView.bottomAnchor.constraint(equalTo: mediaView.bottomAnchor),
                    webView.leadingAnchor.constraint(equalTo: mediaView.leadingAnchor),
                    webView.trailingAnchor.constraint(equalTo: mediaView.trailingAnchor)
                ])
            }, for: .touchUpInside)
            openMediaButton.accessibilityLabel = "打开推文媒体"
            mediaView.addSubview(openMediaButton)

            card.addArrangedSubview(mediaView)
            mediaView.heightAnchor.constraint(equalToConstant: 360).isActive = true
            NSLayoutConstraint.activate([
                imageView.topAnchor.constraint(equalTo: mediaView.topAnchor),
                imageView.bottomAnchor.constraint(equalTo: mediaView.bottomAnchor),
                imageView.leadingAnchor.constraint(equalTo: mediaView.leadingAnchor),
                imageView.trailingAnchor.constraint(equalTo: mediaView.trailingAnchor),
                openMediaButton.topAnchor.constraint(equalTo: mediaView.topAnchor),
                openMediaButton.bottomAnchor.constraint(equalTo: mediaView.bottomAnchor),
                openMediaButton.leadingAnchor.constraint(equalTo: mediaView.leadingAnchor),
                openMediaButton.trailingAnchor.constraint(equalTo: mediaView.trailingAnchor)
            ])
        } else if let html = payload?.html {
            let loadingView = makeTweetLoadingView()
            let webView = makeTweetWebView(html: html, url: url, cachesSnapshot: true)
            loadingView.insertSubview(webView, at: 0)
            NSLayoutConstraint.activate([
                webView.topAnchor.constraint(equalTo: loadingView.topAnchor),
                webView.bottomAnchor.constraint(equalTo: loadingView.bottomAnchor),
                webView.leadingAnchor.constraint(equalTo: loadingView.leadingAnchor),
                webView.trailingAnchor.constraint(equalTo: loadingView.trailingAnchor)
            ])
            card.addArrangedSubview(loadingView)
            loadingView.heightAnchor.constraint(equalToConstant: 360).isActive = true
        } else {
            let loadingView = makeTweetLoadingView()
            card.addArrangedSubview(loadingView)
            loadingView.heightAnchor.constraint(equalToConstant: 360).isActive = true
        }

        return card
    }

    private func makeTweetWebView(html: String, url: URL, cachesSnapshot: Bool) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        if cachesSnapshot {
            tweetPreviewWebViews[ObjectIdentifier(webView)] = url
        }
        webView.loadHTMLString(wrappedTweetHTML(html), baseURL: URL(string: "https://x.com"))
        return webView
    }

    private func makePreviewHeader(title: String, url: URL) -> UIView {
        let header = UIStackView()
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 8

        let titleLabel = UILabel()
        titleLabel.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.text = title
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let openButton = UIButton(type: .system)
        openButton.setImage(UIImage(systemName: "arrow.up.right"), for: .normal)
        openButton.tintColor = .secondaryLabel
        openButton.addAction(UIAction { _ in
            UIApplication.shared.open(url)
        }, for: .touchUpInside)
        openButton.setContentHuggingPriority(.required, for: .horizontal)

        header.addArrangedSubview(titleLabel)
        header.addArrangedSubview(openButton)
        return header
    }

    private func makeTweetLoadingView() -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.36)
        container.layer.cornerRadius = 10
        container.clipsToBounds = true

        let cover = UIView()
        cover.translatesAutoresizingMaskIntoConstraints = false
        cover.backgroundColor = .secondarySystemBackground
        container.addSubview(cover)

        let topLine = makeTweetLoadingLine(alpha: 0.68)
        let midLine = makeTweetLoadingLine(alpha: 0.42)
        let lowLine = makeTweetLoadingLine(alpha: 0.32)
        [topLine, midLine, lowLine].forEach { cover.addSubview($0) }

        NSLayoutConstraint.activate([
            cover.topAnchor.constraint(equalTo: container.topAnchor),
            cover.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            cover.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            cover.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            topLine.leadingAnchor.constraint(equalTo: cover.leadingAnchor, constant: 18),
            topLine.topAnchor.constraint(equalTo: cover.topAnchor, constant: 24),
            topLine.widthAnchor.constraint(equalTo: cover.widthAnchor, multiplier: 0.58),
            topLine.heightAnchor.constraint(equalToConstant: 10),
            midLine.leadingAnchor.constraint(equalTo: topLine.leadingAnchor),
            midLine.topAnchor.constraint(equalTo: topLine.bottomAnchor, constant: 14),
            midLine.widthAnchor.constraint(equalTo: cover.widthAnchor, multiplier: 0.78),
            midLine.heightAnchor.constraint(equalToConstant: 10),
            lowLine.leadingAnchor.constraint(equalTo: topLine.leadingAnchor),
            lowLine.topAnchor.constraint(equalTo: midLine.bottomAnchor, constant: 14),
            lowLine.widthAnchor.constraint(equalTo: cover.widthAnchor, multiplier: 0.46),
            lowLine.heightAnchor.constraint(equalToConstant: 10)
        ])

        UIView.animate(withDuration: 1.1, delay: 0, options: [.autoreverse, .repeat, .allowUserInteraction]) {
            [topLine, midLine, lowLine].forEach { $0.alpha *= 0.45 }
        }
        return container
    }

    private func makeTweetLoadingLine(alpha: CGFloat) -> UIView {
        let line = UIView()
        line.translatesAutoresizingMaskIntoConstraints = false
        line.backgroundColor = UIColor.separator.withAlphaComponent(0.55)
        line.layer.cornerRadius = 5
        line.alpha = alpha
        return line
    }

    private func wrappedTweetHTML(_ html: String) -> String {
        """
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <style>
            body { margin: 0; background: transparent; }
            .twitter-tweet { margin: 0 !important; }
          </style>
        </head>
        <body>\(html)</body>
        </html>
        """
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = tweetPreviewWebViews[ObjectIdentifier(webView)] else { return }
        Task { @MainActor [weak self, weak webView] in
            // ponytail: X embed media settles late; disk cache only if restart speed matters.
            try? await Task.sleep(nanoseconds: 6_500_000_000)
            guard let webView else { return }
            webView.takeSnapshot(with: nil) { image, _ in
                guard let image else { return }
                TweetPreviewLoader.storeSnapshot(image, for: url)
                guard let self, self.tweetPreviewURL == url else { return }
                self.renderTweetPreview(url: url, payload: nil)
            }
        }
    }

    private func clearTweetPreview() {
        tweetPreviewTask?.cancel()
        tweetPreviewTask = nil
        tweetPreviewURL = nil
        tweetPreviewWebViews.removeAll()
        tweetPreviewContainer.isHidden = true
        removeTweetPreviewSubviews()
    }

    private func removeTweetPreviewSubviews() {
        tweetPreviewContainer.subviews.forEach { $0.removeFromSuperview() }
    }
    
    private func containsInlineMarkdown(_ text: String) -> Bool {
        // Check for complete markdown patterns
        let patterns = [
            "\\*\\*[^*]+\\*\\*",  // **bold**
            "(?<!\\*)\\*[^*]+\\*(?!\\*)",  // *italic*
            "`[^`]+`",  // `code`
            "==\\w+:[^=]+=="  // ==color:text== highlight
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)) != nil {
                return true
            }
        }
        return false
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        let range = textView.selectedRange
        if range.length > 0, let textRange = Range(range, in: textView.text) {
            delegate?.textBlockCellSelectionDidChange(self, selectedText: String(textView.text[textRange]), range: range)
        } else {
            delegate?.textBlockCellSelectionDidChange(self, selectedText: "", range: range)
        }
    }

    @available(iOS 16.0, *)
    func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
        guard range.length > 0 else { return UIMenu(children: suggestedActions) }
        guard presentationMode.isEditing else { return UIMenu(children: suggestedActions) }
        
        // 高亮颜色子菜单
        let highlightColors: [(String, String, UIColor)] = [
            ("黄色", "yellow", UIColor(red: 1.0, green: 0.95, blue: 0.4, alpha: 1.0)),
            ("绿色", "green", UIColor(red: 0.6, green: 0.95, blue: 0.6, alpha: 1.0)),
            ("蓝色", "blue", UIColor(red: 0.6, green: 0.85, blue: 1.0, alpha: 1.0)),
            ("粉色", "pink", UIColor(red: 1.0, green: 0.75, blue: 0.85, alpha: 1.0)),
            ("橙色", "orange", UIColor(red: 1.0, green: 0.85, blue: 0.5, alpha: 1.0)),
            ("紫色", "purple", UIColor(red: 0.85, green: 0.75, blue: 1.0, alpha: 1.0))
        ]
        
        let highlightActions = highlightColors.map { (title, colorKey, color) in
            let image = UIImage(systemName: "circle.fill")?.withTintColor(color, renderingMode: .alwaysOriginal)
            return UIAction(title: title, image: image) { [weak self] _ in
                self?.insertHighlight(colorKey: colorKey, selectedRange: range)
            }
        }
        
        let highlightMenu = UIMenu(title: "高亮", image: UIImage(systemName: "highlighter"), children: highlightActions)
        
        // 按顺序排列：标题2、标题3、加粗、符号、编号、待办、引用、代码
        let formatActions: [UIMenuElement] = [
            UIAction(title: "标题 2", image: UIImage(systemName: "textformat.size.larger")) { [weak self] _ in
                guard let self else { return }
                self.delegate?.textBlockCellDidRequestCommand(self, command: .heading(level: 2))
            },
            UIAction(title: "标题 3", image: UIImage(systemName: "textformat.size")) { [weak self] _ in
                guard let self else { return }
                self.delegate?.textBlockCellDidRequestCommand(self, command: .heading(level: 3))
            },
            UIAction(title: "加粗", image: UIImage(systemName: "bold")) { [weak self] _ in
                self?.insertInlineFormat(prefix: "**", suffix: "**", selectedRange: range)
            },
            highlightMenu,
            UIAction(title: "符号", image: UIImage(systemName: "list.bullet")) { [weak self] _ in
                guard let self else { return }
                self.delegate?.textBlockCellDidRequestCommand(self, command: .bullet)
            },
            UIAction(title: "编号", image: UIImage(systemName: "list.number")) { [weak self] _ in
                guard let self else { return }
                self.delegate?.textBlockCellDidRequestCommand(self, command: .numbered)
            },
            UIAction(title: "待办", image: UIImage(systemName: "checkmark.circle")) { [weak self] _ in
                guard let self else { return }
                self.delegate?.textBlockCellDidRequestCommand(self, command: .todo)
            },
            UIAction(title: "引用", image: UIImage(systemName: "text.quote")) { [weak self] _ in
                guard let self else { return }
                self.delegate?.textBlockCellDidRequestCommand(self, command: .quote)
            },
            UIAction(title: "代码", image: UIImage(systemName: "chevron.left.forwardslash.chevron.right")) { [weak self] _ in
                guard let self else { return }
                self.delegate?.textBlockCellDidRequestCommand(self, command: .code)
            }
        ]

        let formatMenu = UIMenu(title: "格式", options: .displayInline, children: formatActions)
        let systemMenu = UIMenu(title: "", options: .displayInline, children: suggestedActions)
        return UIMenu(children: [formatMenu, systemMenu])
    }
    
    private func insertHighlight(colorKey: String, selectedRange: NSRange) {
        let currentText = textView.text ?? ""
        let nsString = currentText as NSString
        let selectedText = nsString.substring(with: selectedRange)
        let replacement = "==\(colorKey):\(selectedText)=="
        
        textView.textStorage.replaceCharacters(in: selectedRange, with: replacement)
        textView.selectedRange = NSRange(location: selectedRange.location + colorKey.count + 3, length: selectedText.count)
        delegate?.textBlockCellDidChange(self, text: textView.text)
        applyStyle(animated: true)
    }

    func selectionRectInView(_ view: UIView) -> CGRect? {
        let range = textView.selectedRange
        guard range.length > 0 else { return nil }
        guard let start = textView.position(from: textView.beginningOfDocument, offset: range.location),
              let end = textView.position(from: start, offset: range.length),
              let textRange = textView.textRange(from: start, to: end) else {
            return nil
        }
        let rect = textView.firstRect(for: textRange)
        if rect.isNull || rect.isEmpty { return nil }
        return textView.convert(rect, to: view)
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        // Handle backspace at start
        if text.isEmpty && range.location == 0 && range.length == 0 && textView.selectedRange.location == 0 {
            delegate?.textBlockCellDidRequestBackspaceAtStart(self)
            return false
        }
        
        if text == "\n" && textView.text == "```" {
            delegate?.textBlockCellDidTrigger(self, trigger: .codeBlock)
            return false
        }

        if text == "\n" && textView.text == "/table" {
            delegate?.textBlockCellDidTrigger(self, trigger: .table)
            return false
        }

        if text == "\n" {
            if kind == .code {
                return true
            }
            // Pass the cursor location so the text can be split correctly
            delegate?.textBlockCellDidRequestNewBlock(self, splitAtLocation: range.location)
            return false
        }

        let currentTextLength = (textView.text as NSString).length
        if text == " " && range.location == currentTextLength {
            let candidate = textView.text + " "
            if candidate == "# " {
                delegate?.textBlockCellDidTrigger(self, trigger: .heading(level: 1))
                return false
            }
            if candidate == "## " {
                delegate?.textBlockCellDidTrigger(self, trigger: .heading(level: 2))
                return false
            }
            if candidate == "### " {
                delegate?.textBlockCellDidTrigger(self, trigger: .heading(level: 3))
                return false
            }
            if candidate == "- " {
                delegate?.textBlockCellDidTrigger(self, trigger: .bullet)
                return false
            }
            if candidate == "1. " {
                delegate?.textBlockCellDidTrigger(self, trigger: .numbered)
                return false
            }
            if candidate == "- [ ] " {
                delegate?.textBlockCellDidTrigger(self, trigger: .todo)
                return false
            }
            if candidate == "> " {
                delegate?.textBlockCellDidTrigger(self, trigger: .quote)
                return false
            }
        }

        return true
    }

    func beginEditing(atEnd: Bool = false) {
        beginEditing(atUTF16Location: atEnd ? textView.text.utf16.count : 0)
    }

    func beginEditing(atUTF16Location location: Int) {
        textView.becomeFirstResponder()
        let clamped = min(max(0, location), textView.text.utf16.count)
        textView.selectedRange = NSRange(location: clamped, length: 0)
    }
}

enum MarkdownTrigger: Equatable {
    case heading(level: Int)
    case bullet
    case numbered
    case todo
    case quote
    case codeBlock
    case table
    case attachment(type: AttachmentType, data: Data, fileName: String)
}
#endif
