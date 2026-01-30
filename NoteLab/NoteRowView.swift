import SwiftUI

struct NoteRowView: View {
    let note: Note
    let notebookTitle: String?
    let notebookColor: NotebookColor?
    let notebookIconName: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: Title and Pin
            HStack(alignment: .top, spacing: 8) {
                Text(note.title.isEmpty ? "无标题" : note.title)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                if note.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryInk)
                        .padding(6)
                        .background(Theme.groupedBackground, in: Circle())
                }
            }
            
            // Content Snippet
            Text(snippetText(for: note))
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(Theme.secondaryInk)
                .lineLimit(2)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Footer: Notebook Pill and Date
            HStack {
                if let title = notebookTitle, let color = notebookColor {
                    HStack(spacing: 4) {
                        Image(systemName: notebookIconName ?? "book.closed")
                            .font(.system(size: 10, weight: .bold))
                        Text(title)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(Color.notebook(color))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.notebook(color).opacity(0.15), in: Capsule())
                }
                
                Spacer()
                
                Text(note.updatedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.secondaryInk.opacity(0.7))
            }
        }
        .padding(16)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Theme.softShadow, radius: 4, x: 0, y: 2)
    }
    
    private func snippetText(for note: Note) -> String {
        let cleaned = sanitizeContent(note.content)
        if cleaned.isEmpty { return "暂无内容" }
        return cleaned
    }
    
    private func sanitizeContent(_ content: String) -> String {
        let stripped = stripFencedCodeBlocks(in: content)
        let lines = stripped.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        var results: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") || trimmed.hasPrefix("#") {
                continue
            }
            results.append(String(trimmed))
        }
        return results.joined(separator: " ")
    }
    
    private func stripFencedCodeBlocks(in content: String) -> String {
        let lines = content.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        var output: [String] = []
        var insideCode = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                insideCode.toggle()
                continue
            }
            if insideCode { continue }
            output.append(String(line))
        }
        return output.joined(separator: "\n")
    }
}
