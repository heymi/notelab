import SwiftUI
import Foundation
#if canImport(UIKit)
import WebKit

// MARK: - Editor Bridge Protocol

enum TipTapCommand: String {
    case bold
    case italic
    case code
    case strike
    case heading1
    case heading2
    case heading3
    case bulletList
    case orderedList
    case taskList
    case blockquote
    case codeBlock
    case horizontalRule
    case table
    case undo
    case redo
    case clearFormat
}

// MARK: - TipTap Editor View

struct TipTapEditorView: UIViewRepresentable {
    @Binding var markdown: String
    @Binding var selectedText: String
    @Binding var selectedRange: NSRange
    @Binding var pendingCommand: TipTapCommand?
    let title: String
    let showsTitle: Bool
    let topInset: CGFloat
    let bottomInset: CGFloat
    let onMarkdownChange: (String) -> Void
    let onTitleChange: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "editor")
        config.userContentController = contentController
        config.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.contentInset = UIEdgeInsets(top: topInset, left: 0, bottom: bottomInset, right: 0)
        webView.scrollView.keyboardDismissMode = .interactive
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        webView.loadHTMLString(Self.editorHTML(hideTitle: !showsTitle), baseURL: nil)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        uiView.scrollView.contentInset = UIEdgeInsets(top: topInset, left: 0, bottom: bottomInset, right: 0)
        
        if let command = pendingCommand {
            context.coordinator.executeCommand(command)
            DispatchQueue.main.async {
                self.pendingCommand = nil
            }
        }
        
        if context.coordinator.lastSentMarkdown != markdown && !context.coordinator.isUpdatingFromWeb {
            context.coordinator.setMarkdown(markdown)
        }
        
        if context.coordinator.lastSentTitle != title {
            context.coordinator.setTitle(title)
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        private let parent: TipTapEditorView
        weak var webView: WKWebView?
        var lastSentMarkdown: String = ""
        var lastSentTitle: String = ""
        var isReady = false
        
        /// Tracks whether we're currently processing a content change from the web view.
        /// Uses a counter instead of a boolean to handle nested/rapid updates correctly.
        private var webUpdateDepth = 0
        var isUpdatingFromWeb: Bool { webUpdateDepth > 0 }
        
        /// Task for resolving attachment URLs - stored so we can cancel on new requests
        private var attachmentResolutionTask: Task<Void, Never>?

        init(parent: TipTapEditorView) {
            self.parent = parent
        }
        
        deinit {
            attachmentResolutionTask?.cancel()
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            // Ensure we're on main thread for all UI updates
            guard Thread.isMainThread else {
                DispatchQueue.main.async { [weak self] in
                    self?.handleMessage(message)
                }
                return
            }
            handleMessage(message)
        }
        
        private func handleMessage(_ message: WKScriptMessage) {
            guard message.name == "editor" else { return }
            guard let body = message.body as? [String: Any],
                  let type = body["type"] as? String else { return }

            switch type {
            case "ready":
                isReady = true
                setTitle(parent.title)
                setMarkdown(parent.markdown)
                
            case "contentChanged":
                // Use depth counter for proper nested update handling
                webUpdateDepth += 1
                defer { 
                    // Reset immediately on main thread after this run loop
                    DispatchQueue.main.async { [weak self] in
                        self?.webUpdateDepth = max(0, (self?.webUpdateDepth ?? 1) - 1)
                    }
                }
                
                if let markdown = body["markdown"] as? String {
                    lastSentMarkdown = markdown
                    parent.onMarkdownChange(markdown)
                }
                
            case "titleChanged":
                if let title = body["title"] as? String {
                    lastSentTitle = title
                    parent.onTitleChange(title)
                }
                
            case "selectionChanged":
                // Now receiving actual positions calculated in JS
                let from = (body["from"] as? Int) ?? 0
                let to = (body["to"] as? Int) ?? 0
                let text = (body["text"] as? String) ?? ""
                parent.selectedText = text
                parent.selectedRange = NSRange(location: from, length: max(0, to - from))
                
            case "resolveAttachments":
                guard let paths = body["paths"] as? [String], !paths.isEmpty else { return }
                resolveAttachmentURLs(paths)
                
            case "jsError":
                // Log JS errors for debugging
                let errorMsg = body["message"] as? String ?? "Unknown JS error"
                let source = body["source"] as? String ?? ""
                let line = body["line"] as? Int ?? 0
                print("[WebEditor JS Error] \(errorMsg) at \(source):\(line)")
                
            default:
                break
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {}

        func setMarkdown(_ markdown: String) {
            guard isReady, let webView else { return }
            lastSentMarkdown = markdown
            let escaped = escapeForJS(markdown)
            webView.evaluateJavaScript("window.__setMarkdown('\(escaped)');") { [weak self] _, error in
                if let error = error {
                    print("[WebEditor] setMarkdown error: \(error.localizedDescription)")
                }
            }
        }
        
        func setTitle(_ title: String) {
            guard isReady, let webView else { return }
            lastSentTitle = title
            let escaped = escapeForJS(title)
            webView.evaluateJavaScript("window.__setTitle('\(escaped)');") { _, error in
                if let error = error {
                    print("[WebEditor] setTitle error: \(error.localizedDescription)")
                }
            }
        }
        
        func executeCommand(_ command: TipTapCommand) {
            guard isReady, let webView else { return }
            webView.evaluateJavaScript("window.__executeCommand('\(command.rawValue)');") { _, error in
                if let error = error {
                    print("[WebEditor] executeCommand error: \(error.localizedDescription)")
                }
            }
        }
        
        private func resolveAttachmentURLs(_ paths: [String]) {
            guard isReady, let webView else { return }
            
            // Cancel any previous resolution task
            attachmentResolutionTask?.cancel()
            
            let uniquePaths = Array(Set(paths))
            attachmentResolutionTask = Task { @MainActor [weak self, weak webView] in
                guard let self = self, let webView = webView else { return }
                
                var resolved: [String: String] = [:]
                for path in uniquePaths {
                    // Check for cancellation
                    if Task.isCancelled { return }
                    
                    // Try signed URL first
                    if let url = try? await AttachmentStorage.shared.getSignedURL(storagePath: path) {
                        resolved[path] = url.absoluteString
                        continue
                    }
                    // Fallback to local cache
                    if let dataURL = self.dataURLFromCache(storagePath: path) {
                        resolved[path] = dataURL
                    }
                }
                
                guard !Task.isCancelled, !resolved.isEmpty,
                      let data = try? JSONSerialization.data(withJSONObject: resolved, options: []),
                      let json = String(data: data, encoding: .utf8) else { return }
                
                // Escape for safe injection
                let safeJson = json.replacingOccurrences(of: "</", with: "<\\/")
                webView.evaluateJavaScript("window.__setAttachmentURLs(\(safeJson));") { _, error in
                    if let error = error {
                        print("[WebEditor] setAttachmentURLs error: \(error.localizedDescription)")
                    }
                }
            }
        }
        
        private func dataURLFromCache(storagePath: String) -> String? {
            let fileName = (storagePath as NSString).lastPathComponent
            let base = (fileName as NSString).deletingPathExtension
            guard let attachmentId = UUID(uuidString: base) else { return nil }
            guard let data = AttachmentCache.load(attachmentId: attachmentId, fileName: fileName) else { return nil }
            let mimeType = AttachmentStorage.mimeType(for: fileName)
            let base64 = data.base64EncodedString()
            return "data:\(mimeType);base64,\(base64)"
        }
        
        private func escapeForJS(_ string: String) -> String {
            var result = string
            result = result.replacingOccurrences(of: "\\", with: "\\\\")
            result = result.replacingOccurrences(of: "'", with: "\\'")
            result = result.replacingOccurrences(of: "\"", with: "\\\"")
            result = result.replacingOccurrences(of: "\n", with: "\\n")
            result = result.replacingOccurrences(of: "\r", with: "\\r")
            result = result.replacingOccurrences(of: "\t", with: "\\t")
            result = result.replacingOccurrences(of: "\0", with: "")
            // Prevent script injection
            result = result.replacingOccurrences(of: "</script>", with: "<\\/script>")
            result = result.replacingOccurrences(of: "</", with: "<\\/")
            return result
        }
    }

    // MARK: - Editor HTML

    private static func editorHTML(hideTitle: Bool) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover">
          <title>Editor</title>
          <style>\(editorCSS(hideTitle: hideTitle))</style>
        </head>
        <body\(hideTitle ? " data-hide-title=\\\"1\\\"" : "")>
          <div id="title-container">
            <input type="text" id="title-input" placeholder="标题" autocomplete="off" autocorrect="off" spellcheck="false">
          </div>
          <div id="editor" contenteditable="true" data-placeholder="开始记录你的想法..."></div>
          <div id="slash-menu" class="hidden">
            <div class="slash-menu-header">格式</div>
            <div class="slash-menu-items"></div>
          </div>
          <script>\(editorJS())</script>
        </body>
        </html>
        """
    }

    private static func editorCSS(hideTitle: Bool) -> String {
        """
        :root {
          --ink: #1A1A1F;
          --ink-secondary: #8E8E93;
          --ink-tertiary: #C4C4C6;
          --bg: #F8F8FA;
          --bg-hover: #F2F2F7;
          --accent: #007AFF;
          --border: #E8E8EA;
        }
        @media (prefers-color-scheme: dark) {
          :root {
            --ink: #F5F5F7;
            --ink-secondary: #98989D;
            --ink-tertiary: #636366;
            --bg: #1C1C1E;
            --bg-hover: #2C2C2E;
            --accent: #0A84FF;
            --border: #38383A;
          }
        }
        * { box-sizing: border-box; -webkit-tap-highlight-color: transparent; }
        html, body {
          margin: 0; padding: 0; height: 100%;
          background: var(--bg);
          font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', 'PingFang SC', sans-serif;
          color: var(--ink);
          -webkit-font-smoothing: antialiased;
        }
        
        #title-container { padding: 20px 18px 8px 18px; }
        #title-input {
          width: 100%; border: none; outline: none; background: transparent;
          font-size: 28px; font-weight: 700; color: var(--ink);
          padding: 0; margin: 0; letter-spacing: -0.3px;
        }
        #title-input::placeholder { color: var(--ink-tertiary); }
        
        #editor {
          min-height: calc(100% - 80px);
          padding: 8px 18px 120px 18px;
          outline: none;
          line-height: 1.65;
          font-size: 16px;
          caret-color: var(--accent);
          white-space: pre-wrap;
          word-wrap: break-word;
        }
        #editor:empty::before {
          content: attr(data-placeholder);
          color: var(--ink-tertiary);
          pointer-events: none;
        }
        #editor > * + * { margin-top: 0.4em; }
        
        #editor h1 { font-size: 26px; font-weight: 700; margin: 24px 0 8px 0; line-height: 1.25; }
        #editor h2 { font-size: 22px; font-weight: 600; margin: 20px 0 6px 0; line-height: 1.3; }
        #editor h3 { font-size: 18px; font-weight: 600; margin: 16px 0 4px 0; line-height: 1.35; }
        #editor p { margin: 0 0 2px 0; }
        #editor strong { font-weight: 600; }
        #editor em { font-style: italic; }
        #editor code {
          background: rgba(128,128,128,0.12); border-radius: 4px; padding: 2px 5px;
          font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 0.88em;
        }
        #editor s { text-decoration: line-through; opacity: 0.6; }
        #editor blockquote {
          border-left: 3px solid var(--border); padding-left: 16px;
          margin: 12px 0; color: var(--ink-secondary);
        }
        #editor pre {
          background: rgba(128,128,128,0.08); border-radius: 8px; padding: 16px 18px;
          font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 14px;
          line-height: 1.55; overflow-x: auto; margin: 12px 0; white-space: pre-wrap;
        }
        #editor pre code { background: none; padding: 0; font-size: inherit; }
        #editor ul, #editor ol { padding-left: 24px; margin: 4px 0; }
        #editor li { margin: 3px 0; }
        #editor li p { margin: 0; }
        #editor hr { border: none; border-top: 1px solid var(--border); margin: 20px 0; }
        #editor img.attachment-image {
          max-width: 100%;
          border-radius: 12px;
          display: block;
          margin: 12px 0;
          background: var(--bg-hover);
        }
        #editor img.attachment-image.loading {
          min-height: 160px;
        }
        #editor table { border-collapse: collapse; width: 100%; margin: 16px 0; }
        #editor th, #editor td {
          border: 1px solid var(--border); padding: 10px 14px;
          text-align: left; vertical-align: top;
        }
        #editor th { background: var(--bg-hover); font-weight: 600; }
        #editor ::selection { background: rgba(0, 122, 255, 0.2); }
        
        /* Task list styles */
        #editor .task-item {
          display: flex; align-items: flex-start; gap: 10px;
          margin: 6px 0; padding: 4px 0;
        }
        #editor .task-item input[type="checkbox"] {
          width: 18px; height: 18px; margin-top: 2px;
          accent-color: var(--accent); cursor: pointer; flex-shrink: 0;
        }
        #editor .task-item span { flex: 1; }
        #editor .task-item.checked span {
          color: var(--ink-secondary); text-decoration: line-through;
        }
        
        #slash-menu {
          position: fixed; background: #FFFFFF; border-radius: 12px;
          box-shadow: 0 4px 24px rgba(0,0,0,0.12), 0 0 0 1px rgba(0,0,0,0.04);
          padding: 8px 0; min-width: 260px; max-width: 320px; max-height: 340px;
          overflow-y: auto; z-index: 1000;
        }
        @media (prefers-color-scheme: dark) {
          #slash-menu { background: #2C2C2E; box-shadow: 0 4px 24px rgba(0,0,0,0.4), 0 0 0 1px rgba(255,255,255,0.08); }
        }
        #slash-menu.hidden { display: none; }
        .slash-menu-header {
          font-size: 11px; font-weight: 600; color: var(--ink-secondary);
          text-transform: uppercase; letter-spacing: 0.5px; padding: 10px 16px 8px;
        }
        .slash-menu-item {
          display: flex; align-items: center; gap: 12px; padding: 10px 16px;
          cursor: pointer; transition: background 0.1s;
        }
        .slash-menu-item:hover, .slash-menu-item.selected { background: var(--bg-hover); }
        .slash-menu-item .icon {
          width: 36px; height: 36px; display: flex; align-items: center; justify-content: center;
          border-radius: 8px; background: var(--bg-hover); font-size: 15px; font-weight: 600;
          color: var(--ink-secondary);
        }
        .slash-menu-item .info { flex: 1; }
        .slash-menu-item .title { font-size: 14px; font-weight: 500; color: var(--ink); }
        .slash-menu-item .desc { font-size: 12px; color: var(--ink-secondary); margin-top: 2px; }
        .slash-menu-empty { padding: 20px; text-align: center; color: var(--ink-secondary); font-size: 13px; }

        /* Hide title for whiteboard / simple mode */
        body[data-hide-title="1"] #title-container { display: none; }
        body[data-hide-title="1"] #editor {
          min-height: 100%;
          padding-top: 20px;
        }
        """
    }

    private static func editorJS() -> String {
        """
        (function() {
          'use strict';
          
          var post = function(payload) {
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.editor) {
              window.webkit.messageHandlers.editor.postMessage(payload);
            }
          };
          
          // Forward JS errors to Swift for debugging
          window.onerror = function(message, source, lineno) {
            post({ type: 'jsError', message: message, source: source, line: lineno });
            return false;
          };

          var editor = document.getElementById('editor');
          var titleInput = document.getElementById('title-input');
          var slashMenu = document.getElementById('slash-menu');
          var slashMenuItems = slashMenu.querySelector('.slash-menu-items');
          
          var slashMenuVisible = false;
          var slashSelectedIndex = 0;
          // Store a Range clone instead of raw DOM node to be more robust
          var slashStartRange = null;
          var slashQuery = '';

          var slashItems = [
            { id: 'heading1', icon: 'H1', title: '标题 1', desc: '大标题', keywords: ['h1', 'heading', '标题'] },
            { id: 'heading2', icon: 'H2', title: '标题 2', desc: '中标题', keywords: ['h2', 'heading', '标题'] },
            { id: 'heading3', icon: 'H3', title: '标题 3', desc: '小标题', keywords: ['h3', 'heading', '标题'] },
            { id: 'bulletList', icon: '•', title: '无序列表', desc: '项目符号列表', keywords: ['bullet', 'list', '列表'] },
            { id: 'orderedList', icon: '1.', title: '有序列表', desc: '编号列表', keywords: ['number', 'list', '编号'] },
            { id: 'taskList', icon: '☑', title: '待办事项', desc: '可勾选任务', keywords: ['todo', 'task', 'checkbox', '待办'] },
            { id: 'blockquote', icon: '"', title: '引用', desc: '引用文字块', keywords: ['quote', '引用'] },
            { id: 'codeBlock', icon: '</>', title: '代码块', desc: '多行代码', keywords: ['code', '代码'] },
            { id: 'horizontalRule', icon: '—', title: '分割线', desc: '水平分割', keywords: ['hr', 'divider', '分割'] },
            { id: 'bold', icon: 'B', title: '加粗', desc: '粗体文字', keywords: ['bold', '加粗'] },
            { id: 'italic', icon: 'I', title: '斜体', desc: '斜体文字', keywords: ['italic', '斜体'] }
          ];
          var slashFilteredItems = slashItems.slice();

          function showSlashMenu(x, y) {
            slashMenuVisible = true;
            slashQuery = '';
            slashSelectedIndex = 0;
            slashFilteredItems = slashItems.slice();
            
            // Save the position where / was typed using a Range clone
            var sel = window.getSelection();
            if (sel.rangeCount > 0) {
              var range = sel.getRangeAt(0);
              // Create a range pointing to just before the /
              slashStartRange = document.createRange();
              try {
                var node = range.startContainer;
                var offset = Math.max(0, range.startOffset - 1);
                slashStartRange.setStart(node, offset);
                slashStartRange.setEnd(node, offset);
              } catch(e) {
                slashStartRange = null;
              }
            }
            
            var viewportWidth = window.innerWidth;
            var viewportHeight = window.innerHeight;
            var posX = Math.max(12, Math.min(x, viewportWidth - 280));
            var posY = y + 26;
            if (posY + 340 > viewportHeight) posY = y - 340 - 8;
            
            slashMenu.style.left = posX + 'px';
            slashMenu.style.top = posY + 'px';
            slashMenu.classList.remove('hidden');
            renderSlashMenu();
          }

          function hideSlashMenu() {
            slashMenuVisible = false;
            slashMenu.classList.add('hidden');
            slashStartRange = null;
            slashQuery = '';
          }
          
          // Check if the slash menu start position is still valid
          function isSlashRangeValid() {
            if (!slashStartRange) return false;
            try {
              // Check if the range is still attached to the document
              var container = slashStartRange.startContainer;
              return container && editor.contains(container);
            } catch(e) {
              return false;
            }
          }

          function filterSlashItems(query) {
            slashQuery = query.toLowerCase();
            if (!slashQuery) {
              slashFilteredItems = slashItems.slice();
            } else {
              slashFilteredItems = slashItems.filter(function(item) {
                return item.title.toLowerCase().indexOf(slashQuery) !== -1 ||
                       item.desc.toLowerCase().indexOf(slashQuery) !== -1 ||
                       item.keywords.some(function(k) { return k.toLowerCase().indexOf(slashQuery) !== -1; });
              });
            }
            slashSelectedIndex = Math.min(slashSelectedIndex, Math.max(0, slashFilteredItems.length - 1));
            renderSlashMenu();
          }

          function renderSlashMenu() {
            if (slashFilteredItems.length === 0) {
              slashMenuItems.innerHTML = '<div class="slash-menu-empty">无匹配项</div>';
              return;
            }
            var html = '';
            for (var i = 0; i < slashFilteredItems.length; i++) {
              var item = slashFilteredItems[i];
              var selected = i === slashSelectedIndex ? ' selected' : '';
              html += '<div class="slash-menu-item' + selected + '" data-id="' + item.id + '">' +
                '<div class="icon">' + item.icon + '</div>' +
                '<div class="info"><div class="title">' + item.title + '</div>' +
                '<div class="desc">' + item.desc + '</div></div></div>';
            }
            slashMenuItems.innerHTML = html;
            
            var items = slashMenuItems.querySelectorAll('.slash-menu-item');
            for (var j = 0; j < items.length; j++) {
              (function(el) {
                el.addEventListener('click', function() {
                  executeSlashCommand(el.getAttribute('data-id'));
                });
              })(items[j]);
            }
          }

          function deleteSlashText() {
            // Delete the "/" and any query text that was typed
            if (!isSlashRangeValid()) return;
            
            try {
              var sel = window.getSelection();
              if (!sel || sel.rangeCount === 0) return;
              
              var blockElement = findBlockParent(slashStartRange.startContainer);
              // Get current cursor position
              var currentRange = sel.getRangeAt(0);
              
              // Create range from slash start to current cursor
              var deleteRange = document.createRange();
              deleteRange.setStart(slashStartRange.startContainer, slashStartRange.startOffset);
              deleteRange.setEnd(currentRange.endContainer, currentRange.endOffset);
              
              // Delete the content
              deleteRange.deleteContents();
              
              // Ensure the block keeps its structure to prevent line merge
              if (blockElement && isElementEmpty(blockElement)) {
                blockElement.innerHTML = '<br>';
              }
              
              // Place cursor at the deletion point
              sel.removeAllRanges();
              placeCursorInBlock(blockElement);
            } catch(e) {
              // Fallback: try to delete using execCommand
              try {
                var sel = window.getSelection();
                if (sel.rangeCount > 0) {
                  // Select from current position backwards and delete
                  document.execCommand('delete');
                }
              } catch(e2) {
                // Last resort - do nothing
              }
            }
          }

          function findBlockParent(node) {
            var current = node;
            while (current && current !== editor) {
              if (current.nodeType === 1) {
                var tag = current.tagName.toLowerCase();
                if (['p', 'div', 'h1', 'h2', 'h3', 'li', 'blockquote', 'pre'].indexOf(tag) !== -1) {
                  return current;
                }
              }
              current = current.parentNode;
            }
            return null;
          }

          function isElementEmpty(el) {
            if (!el) return true;
            var text = el.textContent || '';
            return text.trim() === '';
          }

          function placeCursorInBlock(block) {
            if (!block) return;
            var sel = window.getSelection();
            var range = document.createRange();
            if (block.firstChild) {
              range.setStart(block.firstChild, 0);
            } else {
              range.setStart(block, 0);
            }
            range.collapse(true);
            sel.removeAllRanges();
            sel.addRange(range);
          }

          function insertTaskItem() {
            var taskHtml = '<div class="task-item"><input type="checkbox"><span><br></span></div>';
            document.execCommand('insertHTML', false, taskHtml);
            // Focus on the span
            setTimeout(function() {
              var tasks = editor.querySelectorAll('.task-item span');
              if (tasks.length > 0) {
                var lastTask = tasks[tasks.length - 1];
                var range = document.createRange();
                range.selectNodeContents(lastTask);
                range.collapse(true);
                var sel = window.getSelection();
                sel.removeAllRanges();
                sel.addRange(range);
              }
            }, 10);
          }

          function executeSlashCommand(id) {
            // First focus the editor to ensure commands work
            editor.focus();
            
            // Delete the slash text
            deleteSlashText();
            
            // Hide the menu
            hideSlashMenu();
            
            // Apply format synchronously to avoid cursor jumping
            applySlashFormat(id);
            notifyContentChanged();
          }

          function applySlashFormat(id) {
            switch (id) {
              case 'heading1': 
                document.execCommand('formatBlock', false, 'h1'); 
                break;
              case 'heading2': 
                document.execCommand('formatBlock', false, 'h2'); 
                break;
              case 'heading3': 
                document.execCommand('formatBlock', false, 'h3'); 
                break;
              case 'bulletList': 
                document.execCommand('insertUnorderedList'); 
                break;
              case 'orderedList': 
                document.execCommand('insertOrderedList'); 
                break;
              case 'taskList': 
                insertTaskItem(); 
                break;
              case 'blockquote': 
                document.execCommand('formatBlock', false, 'blockquote'); 
                break;
              case 'codeBlock': 
                document.execCommand('formatBlock', false, 'pre'); 
                break;
              case 'horizontalRule': 
                document.execCommand('insertHorizontalRule'); 
                break;
              case 'bold': 
                document.execCommand('bold'); 
                break;
              case 'italic': 
                document.execCommand('italic'); 
                break;
            }
          }

          function notifyContentChanged() {
            var markdown = htmlToMarkdown(editor.innerHTML);
            post({ type: 'contentChanged', markdown: markdown });
          }

          function htmlToMarkdown(html) {
            var div = document.createElement('div');
            div.innerHTML = html;
            return convertNode(div).trim();
          }

          function convertNode(node) {
            if (node.nodeType === 3) return node.textContent;
            if (node.nodeType !== 1) return '';
            
            var tag = node.tagName.toLowerCase();
            var children = '';
            for (var i = 0; i < node.childNodes.length; i++) {
              children += convertNode(node.childNodes[i]);
            }
            
            switch (tag) {
              case 'h1': return '# ' + children.trim() + '\\n\\n';
              case 'h2': return '## ' + children.trim() + '\\n\\n';
              case 'h3': return '### ' + children.trim() + '\\n\\n';
              case 'p': return children + '\\n\\n';
              case 'div':
                if (node.classList.contains('task-item')) {
                  var checkbox = node.querySelector('input[type="checkbox"]');
                  var span = node.querySelector('span');
                  var text = span ? span.textContent.trim() : '';
                  var checked = checkbox && checkbox.checked;
                  return (checked ? '- [x] ' : '- [ ] ') + text + '\\n';
                }
                return children + '\\n';
              case 'img':
                // CRITICAL: Always prefer data-storage-path over src
                // src may contain signed URLs or data URLs which should NOT be saved to markdown
                var storagePath = node.getAttribute('data-storage-path') || '';
                var alt = node.getAttribute('alt') || 'Attachment';
                
                // Only use storagePath if available; otherwise skip this image
                // We never want to persist signed URLs or data URLs to markdown
                if (storagePath) {
                  return '![' + alt + '](' + storagePath + ')\\n\\n';
                }
                
                // Fallback: check if src looks like a storage path (not a URL)
                var src = node.getAttribute('src') || '';
                if (src && !src.startsWith('http') && !src.startsWith('data:') && !src.startsWith('blob:')) {
                  return '![' + alt + '](' + src + ')\\n\\n';
                }
                
                // If we can't determine a proper path, skip the image
                return '';
              case 'br': return '\\n';
              case 'strong': case 'b': return '**' + children + '**';
              case 'em': case 'i': return '*' + children + '*';
              case 'code': 
                // Don't wrap if already inside pre
                var parent = node.parentNode;
                if (parent && parent.tagName && parent.tagName.toLowerCase() === 'pre') {
                  return children;
                }
                return '`' + children + '`';
              case 's': case 'strike': return '~~' + children + '~~';
              case 'blockquote': 
                var lines = children.trim().split('\\n');
                return lines.map(function(l) { return '> ' + l; }).join('\\n') + '\\n\\n';
              case 'pre': 
                // Get raw text content to preserve code
                var codeContent = node.textContent || '';
                return '```\\n' + codeContent + '\\n```\\n\\n';
              case 'ul':
                var lis = node.querySelectorAll(':scope > li');
                var ul = '';
                for (var j = 0; j < lis.length; j++) {
                  ul += '- ' + convertNode(lis[j]).trim() + '\\n';
                }
                return ul + '\\n';
              case 'ol':
                var olis = node.querySelectorAll(':scope > li');
                var ol = '';
                for (var k = 0; k < olis.length; k++) {
                  ol += (k + 1) + '. ' + convertNode(olis[k]).trim() + '\\n';
                }
                return ol + '\\n';
              case 'li': return children;
              case 'hr': return '---\\n\\n';
              case 'input': return '';
              case 'span': return children;
              default: return children;
            }
          }

          function markdownToHtml(md) {
            var placeholder = 'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==';
            
            // Step 1: Extract and protect code blocks first
            var codeBlocks = [];
            var html = md.replace(/```([\\s\\S]*?)```/g, function(match, code) {
              var idx = codeBlocks.length;
              codeBlocks.push('<pre><code>' + escapeHtml(code) + '</code></pre>');
              return '%%CODEBLOCK' + idx + '%%';
            });
            
            // Step 2: Extract and protect inline code
            var inlineCodes = [];
            html = html.replace(/`([^`\\n]+)`/g, function(match, code) {
              var idx = inlineCodes.length;
              inlineCodes.push('<code>' + escapeHtml(code) + '</code>');
              return '%%INLINECODE' + idx + '%%';
            });
            
            // Step 3: Process images/attachments
            html = html.replace(/!\\[([^\\]]*)\\]\\(([^)]+)\\)/g, function(match, alt, target) {
              var t = (target || '').trim();
              var a = escapeHtml((alt || 'Attachment').trim());
              if (/^(https?:|data:|file:)/i.test(t)) {
                return '<img class="attachment-image" src="' + t + '" alt="' + a + '">';
              }
              // Store storagePath in data attribute for round-trip
              return '<img class="attachment-image loading" data-storage-path="' + escapeHtml(t) + '" src="' + placeholder + '" alt="' + a + '">';
            });
            
            // Step 4: Process block-level elements (order matters!)
            html = html.replace(/^### (.+)$/gm, '<h3>$1</h3>');
            html = html.replace(/^## (.+)$/gm, '<h2>$1</h2>');
            html = html.replace(/^# (.+)$/gm, '<h1>$1</h1>');
            html = html.replace(/^---$/gm, '<hr>');
            
            // Task items MUST be processed before bullet lists
            html = html.replace(/^- \\[x\\] (.+)$/gim, '<div class="task-item checked"><input type="checkbox" checked><span>$1</span></div>');
            html = html.replace(/^- \\[ \\] (.+)$/gm, '<div class="task-item"><input type="checkbox"><span>$1</span></div>');
            
            // Blockquotes
            html = html.replace(/^> (.+)$/gm, '<blockquote>$1</blockquote>');
            
            // Lists (after task items)
            html = html.replace(/^- (.+)$/gm, '<ul><li>$1</li></ul>');
            html = html.replace(/^\\d+\\. (.+)$/gm, '<ol><li>$1</li></ol>');
            
            // Step 5: Process inline formatting
            html = html.replace(/\\*\\*([^*]+)\\*\\*/g, '<strong>$1</strong>');
            html = html.replace(/(?:^|[^*])\\*([^*\\n]+)\\*(?:[^*]|$)/g, function(match, content) {
              // Preserve surrounding characters
              var prefix = match.charAt(0) === '*' ? '' : match.charAt(0);
              var suffix = match.charAt(match.length - 1) === '*' ? '' : match.charAt(match.length - 1);
              return prefix + '<em>' + content + '</em>' + suffix;
            });
            html = html.replace(/~~([^~]+)~~/g, '<s>$1</s>');
            
            // Merge adjacent lists
            html = html.replace(/<\\/ul>\\s*<ul>/g, '');
            html = html.replace(/<\\/ol>\\s*<ol>/g, '');
            
            // Step 6: Restore protected content
            for (var i = 0; i < inlineCodes.length; i++) {
              html = html.replace('%%INLINECODE' + i + '%%', inlineCodes[i]);
            }
            for (var j = 0; j < codeBlocks.length; j++) {
              html = html.replace('%%CODEBLOCK' + j + '%%', codeBlocks[j]);
            }
            
            // Step 7: Wrap remaining text in paragraphs
            var blocks = html.split('\\n\\n');
            var result = '';
            for (var k = 0; k < blocks.length; k++) {
              var b = blocks[k].trim();
              if (!b) continue;
              if (b.charAt(0) === '<' || b.indexOf('%%') !== -1) {
                result += b;
              } else {
                result += '<p>' + b.replace(/\\n/g, '<br>') + '</p>';
              }
            }
            return result || '<p><br></p>';
          }
          
          function escapeHtml(text) {
            var div = document.createElement('div');
            div.textContent = text;
            return div.innerHTML;
          }

          // Title handling
          titleInput.addEventListener('input', function() {
            post({ type: 'titleChanged', title: titleInput.value });
          });
          titleInput.addEventListener('keydown', function(e) {
            if (e.key === 'Enter') {
              e.preventDefault();
              editor.focus();
              // Place cursor at beginning and scroll into view
              if (editor.firstChild) {
                var range = document.createRange();
                range.selectNodeContents(editor.firstChild);
                range.collapse(true);
                var sel = window.getSelection();
                sel.removeAllRanges();
                sel.addRange(range);
              }
              // Scroll to make sure editor is visible
              setTimeout(function() {
                editor.scrollIntoView({ behavior: 'smooth', block: 'start' });
              }, 100);
            }
          });

          // Editor input handling
          editor.addEventListener('input', function(e) {
            // Handle checkbox changes
            if (e.target && e.target.type === 'checkbox') {
              var taskItem = e.target.closest('.task-item');
              if (taskItem) {
                if (e.target.checked) {
                  taskItem.classList.add('checked');
                } else {
                  taskItem.classList.remove('checked');
                }
              }
            }
            notifyContentChanged();
          });

          // Handle checkbox clicks
          editor.addEventListener('change', function(e) {
            if (e.target && e.target.type === 'checkbox') {
              var taskItem = e.target.closest('.task-item');
              if (taskItem) {
                if (e.target.checked) {
                  taskItem.classList.add('checked');
                } else {
                  taskItem.classList.remove('checked');
                }
                notifyContentChanged();
              }
            }
          });

          editor.addEventListener('keydown', function(e) {
            if (slashMenuVisible) {
              if (e.key === 'ArrowDown') {
                e.preventDefault();
                slashSelectedIndex = (slashSelectedIndex + 1) % slashFilteredItems.length;
                renderSlashMenu();
                return;
              }
              if (e.key === 'ArrowUp') {
                e.preventDefault();
                slashSelectedIndex = (slashSelectedIndex - 1 + slashFilteredItems.length) % slashFilteredItems.length;
                renderSlashMenu();
                return;
              }
              if (e.key === 'Enter') {
                e.preventDefault();
                if (slashFilteredItems.length > 0) {
                  executeSlashCommand(slashFilteredItems[slashSelectedIndex].id);
                }
                return;
              }
              if (e.key === 'Escape') {
                e.preventDefault();
                hideSlashMenu();
                return;
              }
              if (e.key === 'Backspace') {
                // Check if we're about to delete the / or have deleted past it
                setTimeout(function() {
                  if (!isSlashRangeValid()) {
                    hideSlashMenu();
                    return;
                  }
                  var sel = window.getSelection();
                  if (sel.rangeCount > 0) {
                    var range = sel.getRangeAt(0);
                    // Compare positions - if cursor is at or before slash start, close menu
                    var comparison = range.compareBoundaryPoints(Range.START_TO_START, slashStartRange);
                    if (comparison <= 0) {
                      hideSlashMenu();
                    }
                  }
                }, 0);
              }
            }
            
            // Markdown shortcuts on space
            if (e.key === ' ') {
              var sel = window.getSelection();
              if (sel.rangeCount > 0) {
                var range = sel.getRangeAt(0);
                var node = range.startContainer;
                if (node.nodeType === 3) {
                  var text = node.textContent.substring(0, range.startOffset);
                  var patterns = [
                    { regex: /^#$/, cmd: function() { document.execCommand('formatBlock', false, 'h1'); } },
                    { regex: /^##$/, cmd: function() { document.execCommand('formatBlock', false, 'h2'); } },
                    { regex: /^###$/, cmd: function() { document.execCommand('formatBlock', false, 'h3'); } },
                    { regex: /^-$/, cmd: function() { document.execCommand('insertUnorderedList'); } },
                    { regex: /^\\*$/, cmd: function() { document.execCommand('insertUnorderedList'); } },
                    { regex: /^1\\.$/, cmd: function() { document.execCommand('insertOrderedList'); } },
                    { regex: /^>$/, cmd: function() { document.execCommand('formatBlock', false, 'blockquote'); } },
                    { regex: /^\\[\\]$/, cmd: function() { insertTaskItem(); } }
                  ];
                  for (var i = 0; i < patterns.length; i++) {
                    if (patterns[i].regex.test(text)) {
                      e.preventDefault();
                      node.textContent = '';
                      patterns[i].cmd();
                      notifyContentChanged();
                      return;
                    }
                  }
                }
              }
            }
            
            // Enter in task item creates new task
            if (e.key === 'Enter') {
              var sel = window.getSelection();
              if (sel.rangeCount > 0) {
                var node = sel.getRangeAt(0).startContainer;
                var taskItem = node.nodeType === 1 ? node.closest('.task-item') : node.parentElement.closest('.task-item');
                if (taskItem) {
                  e.preventDefault();
                  var span = taskItem.querySelector('span');
                  if (span && span.textContent.trim() === '') {
                    // Empty task, convert to paragraph
                    var p = document.createElement('p');
                    p.innerHTML = '<br>';
                    taskItem.parentNode.replaceChild(p, taskItem);
                    var range = document.createRange();
                    range.selectNodeContents(p);
                    range.collapse(true);
                    sel.removeAllRanges();
                    sel.addRange(range);
                  } else {
                    // Create new task item
                    var newTask = document.createElement('div');
                    newTask.className = 'task-item';
                    newTask.innerHTML = '<input type="checkbox"><span><br></span>';
                    taskItem.parentNode.insertBefore(newTask, taskItem.nextSibling);
                    var newSpan = newTask.querySelector('span');
                    var range = document.createRange();
                    range.selectNodeContents(newSpan);
                    range.collapse(true);
                    sel.removeAllRanges();
                    sel.addRange(range);
                  }
                  notifyContentChanged();
                  return;
                }
              }
            }
          });

          // Slash command detection
          editor.addEventListener('keyup', function(e) {
            // Ignore navigation and control keys
            if (['ArrowDown', 'ArrowUp', 'ArrowLeft', 'ArrowRight', 'Enter', 'Escape', 'Shift', 'Control', 'Alt', 'Meta'].indexOf(e.key) !== -1) {
              return;
            }
            
            if (e.key === '/') {
              var sel = window.getSelection();
              if (sel.rangeCount > 0) {
                var range = sel.getRangeAt(0);
                var rect = range.getBoundingClientRect();
                // Only show if we have valid coordinates
                if (rect.left > 0 || rect.top > 0) {
                  showSlashMenu(rect.left, rect.top);
                } else {
                  // Fallback: use editor position
                  var editorRect = editor.getBoundingClientRect();
                  showSlashMenu(editorRect.left + 20, editorRect.top + 20);
                }
              }
            } else if (slashMenuVisible) {
              // Update filter based on typed text after /
              if (!isSlashRangeValid()) {
                hideSlashMenu();
                return;
              }
              
              var sel = window.getSelection();
              if (sel.rangeCount > 0) {
                try {
                  var currentRange = sel.getRangeAt(0);
                  var startNode = slashStartRange.startContainer;
                  var startOffset = slashStartRange.startOffset;
                  
                  // Check if we're still in the same text node
                  if (currentRange.startContainer === startNode && startNode.nodeType === 3) {
                    var text = startNode.textContent || '';
                    var currentOffset = currentRange.startOffset;
                    // Query is everything after the slash position (offset + 1 for the / character)
                    var query = text.substring(startOffset + 1, currentOffset);
                    
                    // If query contains another slash or is too long, close menu
                    if (query.indexOf('/') !== -1 || query.length > 20) {
                      hideSlashMenu();
                    } else {
                      filterSlashItems(query.trim());
                    }
                  } else {
                    // Cursor moved to different node, close menu
                    hideSlashMenu();
                  }
                } catch(e) {
                  hideSlashMenu();
                }
              } else {
                hideSlashMenu();
              }
            }
          });

          // Click outside slash menu
          document.addEventListener('click', function(e) {
            if (slashMenuVisible && !slashMenu.contains(e.target)) {
              hideSlashMenu();
            }
          });

          // Selection change - calculate actual position within editor
          document.addEventListener('selectionchange', function() {
            var sel = window.getSelection();
            if (!sel || sel.rangeCount === 0) return;
            
            var range = sel.getRangeAt(0);
            var text = sel.toString();
            
            // Calculate actual character offset from start of editor
            var from = 0;
            var to = 0;
            
            try {
              // Create a range from editor start to selection start
              var preRange = document.createRange();
              preRange.selectNodeContents(editor);
              preRange.setEnd(range.startContainer, range.startOffset);
              from = preRange.toString().length;
              
              // For "to", add the selection length
              to = from + text.length;
            } catch(e) {
              // Fallback to simple calculation
              from = 0;
              to = text.length;
            }
            
            post({ type: 'selectionChanged', from: from, to: to, text: text });
          });

          // Global bridge functions
          window.__setMarkdown = function(md) {
            editor.innerHTML = markdownToHtml(md);
            bindTaskCheckboxes();
            resolveAttachmentImages();
          };

          window.__setTitle = function(t) {
            titleInput.value = t || '';
          };

          window.__executeCommand = function(cmd) {
            editor.focus();
            switch (cmd) {
              case 'bold': document.execCommand('bold'); break;
              case 'italic': document.execCommand('italic'); break;
              case 'code':
                var sel = window.getSelection();
                if (sel.toString()) {
                  document.execCommand('insertHTML', false, '<code>' + sel.toString() + '</code>');
                }
                break;
              case 'strike': document.execCommand('strikeThrough'); break;
              case 'heading1': document.execCommand('formatBlock', false, 'h1'); break;
              case 'heading2': document.execCommand('formatBlock', false, 'h2'); break;
              case 'heading3': document.execCommand('formatBlock', false, 'h3'); break;
              case 'bulletList': document.execCommand('insertUnorderedList'); break;
              case 'orderedList': document.execCommand('insertOrderedList'); break;
              case 'taskList': insertTaskItem(); break;
              case 'blockquote': document.execCommand('formatBlock', false, 'blockquote'); break;
              case 'codeBlock': document.execCommand('formatBlock', false, 'pre'); break;
              case 'horizontalRule': document.execCommand('insertHorizontalRule'); break;
              case 'undo': document.execCommand('undo'); break;
              case 'redo': document.execCommand('redo'); break;
              case 'clearFormat': document.execCommand('removeFormat'); break;
            }
            notifyContentChanged();
          };

          function bindTaskCheckboxes() {
            var checkboxes = editor.querySelectorAll('.task-item input[type="checkbox"]');
            for (var i = 0; i < checkboxes.length; i++) {
              var cb = checkboxes[i];
              var taskItem = cb.closest('.task-item');
              if (cb.checked) {
                taskItem.classList.add('checked');
              }
            }
          }

          function resolveAttachmentImages() {
            var imgs = editor.querySelectorAll('img[data-storage-path]');
            if (!imgs || imgs.length === 0) return;
            var seen = {};
            var paths = [];
            for (var i = 0; i < imgs.length; i++) {
              var img = imgs[i];
              var path = img.getAttribute('data-storage-path');
              if (!path || seen[path]) continue;
              seen[path] = true;
              paths.push(path);
              img.classList.add('loading');
            }
            if (paths.length > 0) {
              post({ type: 'resolveAttachments', paths: paths });
            }
          }

          window.__setAttachmentURLs = function(map) {
            if (!map) return;
            var imgs = editor.querySelectorAll('img[data-storage-path]');
            for (var i = 0; i < imgs.length; i++) {
              var img = imgs[i];
              var path = img.getAttribute('data-storage-path');
              if (!path || !map[path]) continue;
              img.src = map[path];
              img.classList.remove('loading');
            }
          };

          window.__focusEditor = function() { editor.focus(); };
          window.__focusTitle = function() { titleInput.focus(); };

          // Initialize
          post({ type: 'ready' });
        })();
        """
    }
}

// MARK: - Simplified TipTap View

struct TipTapEditorViewSimple: View {
    @Binding var markdown: String
    @Binding var selectedText: String
    @Binding var selectedRange: NSRange
    @State private var pendingCommand: TipTapCommand? = nil
    let topInset: CGFloat
    let bottomInset: CGFloat
    let onMarkdownChange: (String) -> Void
    
    var body: some View {
        TipTapEditorView(
            markdown: $markdown,
            selectedText: $selectedText,
            selectedRange: $selectedRange,
            pendingCommand: $pendingCommand,
            title: "",
            showsTitle: false,
            topInset: topInset,
            bottomInset: bottomInset,
            onMarkdownChange: onMarkdownChange,
            onTitleChange: { _ in }
        )
    }
}
#endif
