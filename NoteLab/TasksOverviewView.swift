import SwiftUI
import Combine

struct TasksOverviewView: View {
    @EnvironmentObject private var store: NotebookStore
    @EnvironmentObject private var router: AppRouter
    @State private var sections: [TodoSection] = []
    @State private var transientCompleted: [String: LocalTodoItem] = [:]
    @State private var refreshTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("待办事项")
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 4)

            if sections.isEmpty {
                emptyTodos
            } else {
                ForEach(sections) { section in
                    todoSectionCard(section)
                }
            }
        }
        .padding(.bottom, 80)
        .onAppear { refresh() }
        .onReceive(
            store.$notebooks.debounce(for: .milliseconds(250), scheduler: RunLoop.main)
        ) { _ in
            refresh()
        }
        .onReceive(
            store.$whiteboard.debounce(for: .milliseconds(250), scheduler: RunLoop.main)
        ) { _ in
            refresh()
        }
    }

    private func refresh() {
        refreshTask?.cancel()
        let transientSnapshot = transientCompleted
        let notebooksSnapshot = store.notebooks
        refreshTask = Task { @MainActor in
            let todos = store.collectTodos(includeCompleted: true)
            let sections = buildSections(
                from: todos,
                transient: transientSnapshot,
                notebooks: notebooksSnapshot
            )
            guard !Task.isCancelled else { return }
            self.sections = sections
        }
    }

    private func todoSectionCard(_ section: TodoSection) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            let completedCount = section.completedCount + section.items.filter { !$0.isCompleted && transientCompleted[$0.id] != nil }.count
            HStack(alignment: .firstTextBaseline) {
                Text(section.title)
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Spacer()
                Text("\(completedCount) / \(section.totalCount) 完成")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.editorAccentDeep)
            }
            .padding(.horizontal, 2)

            VStack(spacing: 12) {
                ForEach(section.items) { item in
                    let done = item.isCompleted || transientCompleted[item.id] != nil
                    HStack(spacing: 16) {
                        Button(action: { completeTodo(item) }) {
                            todoCheckmark(done: done)
                        }
                        .buttonStyle(.plain)
                        .disabled(done)

                        Button(action: { openTodo(item) }) {
                            Text(item.title)
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundStyle(done ? Theme.secondaryInk : Theme.ink)
                                .lineSpacing(4)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .background(Theme.editorPaper.opacity(done ? 0.72 : 0.95), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .opacity(done ? 0.82 : 1.0)
                }

                if section.hasMore {
                    Button(action: { openTodoSection(section) }) {
                        HStack {
                            Text("查看其余 \(section.moreCount) 项")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(Theme.secondaryInk)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 14)
                        .background(Theme.editorPaper.opacity(0.62), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
            }
        }
        .padding(18)
        .background(Theme.editorPaperSoft.opacity(0.72), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .shadow(color: Theme.softShadow.opacity(0.5), radius: 18, x: 0, y: 10)
    }

    private func todoCheckmark(done: Bool) -> some View {
        ZStack {
            Circle()
                .fill(done ? Theme.editorAccentDeep : Theme.editorPaper.opacity(0.8))
                .frame(width: 42, height: 42)
            if done {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            } else {
                Circle()
                    .stroke(Theme.editorLine.opacity(0.55), lineWidth: 1)
                    .frame(width: 40, height: 40)
            }
        }
        .frame(width: 48, height: 48)
    }

    private var emptyTodos: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.secondaryInk)
            Text("暂无待办")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.secondaryInk)
        }
        .padding(.vertical, 8)
    }

    private func completeTodo(_ item: LocalTodoItem) {
        if item.isCompleted { return }
        if transientCompleted[item.id] != nil { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            transientCompleted[item.id] = item
        }
        store.completeTodo(item)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.easeInOut(duration: 0.2)) {
                _ = self.transientCompleted.removeValue(forKey: item.id)
            }
        }
    }

    private func openTodo(_ item: LocalTodoItem) {
        if item.isWhiteboard {
            router.push(.whiteboard)
        } else {
            router.push(.note(item.noteId))
        }
    }

    private func openTodoSection(_ section: TodoSection) {
        if section.isWhiteboard {
            router.push(.whiteboard)
        } else {
            router.push(.notebook(section.id))
        }
    }
}

private func buildSections(
    from todos: [LocalTodoItem],
    transient: [String: LocalTodoItem],
    notebooks: [Notebook]
) -> [TodoSection] {
    var combined = todos
    for item in transient.values {
        if !combined.contains(where: { $0.id == item.id }) {
            combined.append(item)
        }
    }
    var sections: [TodoSection] = []

    let whiteboardItems = combined.filter { $0.isWhiteboard }
    if !whiteboardItems.isEmpty {
        let limitedItems = Array(whiteboardItems.prefix(10))
        sections.append(
            TodoSection(
                id: whiteboardItems[0].notebookId,
                title: whiteboardItems[0].notebookTitle,
                items: limitedItems,
                isWhiteboard: true,
                hasMore: whiteboardItems.count > limitedItems.count,
                moreCount: max(0, whiteboardItems.count - limitedItems.count),
                completedCount: whiteboardItems.filter(\.isCompleted).count
            )
        )
    }

    for notebook in notebooks {
        let items = combined.filter { $0.notebookId == notebook.id && !$0.isWhiteboard }
        if !items.isEmpty {
            let limitedItems = Array(items.prefix(10))
            sections.append(
                TodoSection(
                    id: notebook.id,
                    title: notebook.title,
                    items: limitedItems,
                    isWhiteboard: false,
                    hasMore: items.count > limitedItems.count,
                    moreCount: max(0, items.count - limitedItems.count),
                    completedCount: items.filter(\.isCompleted).count
                )
            )
        }
    }

    return sections
}

private struct TodoSection: Identifiable {
    let id: UUID
    let title: String
    let items: [LocalTodoItem]
    let isWhiteboard: Bool
    let hasMore: Bool
    let moreCount: Int
    let completedCount: Int

    var totalCount: Int {
        items.count + moreCount
    }
}
