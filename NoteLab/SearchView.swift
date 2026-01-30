import SwiftUI
import Combine
import Foundation

import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var store: NotebookStore
    @EnvironmentObject private var router: AppRouter
    @State private var query: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // 自定义顶部搜索栏
            VStack(spacing: 12) {
                HStack {
                    Text("搜索")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Theme.secondaryInk)
                        .font(.system(size: 16, weight: .semibold))
                    
                    TextField("搜索笔记、任务或段落", text: $query)
                        .font(.system(size: 16, design: .rounded))
                    
                    if !query.isEmpty {
                        Button(action: { query = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Theme.secondaryInk)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
            }
            .background(Theme.background)

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(results) { result in
                        Button {
                            open(result)
                        } label: {
                            resultCard(title: result.title, snippet: result.snippet, tag: result.tag)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                .padding(.top, 10)
            }
        }
        .background(Theme.background)
    }

    private var results: [SearchResult] {
        let trimmed = query.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let keyword = trimmed.lowercased()

        var output: [SearchResult] = []

        for notebook in store.notebooks {
            let matches = trimmed.isEmpty || notebook.title.lowercased().contains(keyword)
            if matches {
                output.append(SearchResult(
                    id: notebook.id,
                    title: notebook.title,
                    snippet: "\(notebook.notes.count) 条笔记",
                    tag: "笔记本",
                    kind: .notebook(notebook.id)
                ))
            }

            for note in notebook.notes {
                let noteMatches = trimmed.isEmpty || note.title.lowercased().contains(keyword) || note.content.lowercased().contains(keyword)
                if noteMatches {
                    output.append(SearchResult(
                        id: note.id,
                        title: note.title,
                        snippet: snippet(from: note),
                        tag: "笔记",
                        kind: .note(note.id)
                    ))
                }
            }
        }

        if trimmed.isEmpty {
            return Array(output.prefix(8))
        }
        return output
    }

    private func snippet(from note: Note) -> String {
        if !note.summary.isEmpty {
            return note.summary
        }
        let line = note.content
            .split(whereSeparator: { $0.isNewline })
            .map { String($0) }
            .first(where: { !$0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty })
        return line ?? "暂无内容"
    }

    private func open(_ result: SearchResult) {
        switch result.kind {
        case .notebook(let id):
            router.push(.notebook(id))
        case .note(let noteId):
            router.push(.note(noteId))
        }
    }

    private func resultCard(title: String, snippet: String, tag: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text(tag)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.secondaryInk)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.8), in: Capsule())
            }
            Text(snippet)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(Theme.secondaryInk)
                .lineLimit(2)
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Theme.softShadow, radius: 12, x: 0, y: 8)
    }
}

struct SearchResult: Identifiable, Hashable {
    let id: UUID
    let title: String
    let snippet: String
    let tag: String
    let kind: SearchResultKind
}

enum SearchResultKind: Hashable {
    case notebook(UUID)
    case note(UUID)
}
