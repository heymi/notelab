import SwiftUI
import Combine

struct TasksOverviewView: View {
    @EnvironmentObject private var store: NotebookStore
    @EnvironmentObject private var router: AppRouter
    @State private var sections: [TodoSection] = []
    @State private var transientCompleted: [String: LocalTodoItem] = [:]
    @State private var refreshTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "checklist")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text("Tasks")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
            }
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
        refreshTask = Task.detached(priority: .utility) { [store] in
            let todos = store.collectOpenTodos()
            let sections = buildSections(
                from: todos,
                transient: transientSnapshot,
                notebooks: notebooksSnapshot
            )
            await MainActor.run {
                self.sections = sections
            }
        }
    }

    private func todoSectionCard(_ section: TodoSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(section.title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.secondaryInk)
                .textCase(.uppercase)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                    let done = transientCompleted[item.id] != nil
                    VStack(spacing: 0) {
                        HStack(spacing: 14) {
                            Button(action: { completeTodo(item) }) {
                                ZStack {
                                    Circle()
                                        .stroke(done ? Color.green : Theme.secondaryInk.opacity(0.3), lineWidth: 2)
                                        .frame(width: 22, height: 22)

                                    if done {
                                        Circle()
                                            .fill(Color.green)
                                            .frame(width: 14, height: 14)
                                    }
                                }
                            }
                            .buttonStyle(.plain)

                            Button(action: { openTodo(item) }) {
                                planRowContent(title: item.title, source: item.noteTitle)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                        .opacity(done ? 0.6 : 1.0)

                        if index < section.items.count - 1 || section.hasMore {
                            Divider()
                                .padding(.leading, 52)
                        }
                    }
                }

                if section.hasMore {
                    Button(action: { openTodoSection(section) }) {
                        HStack {
                            Text("View all \(section.moreCount) more")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(Theme.secondaryInk)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                    }
                }
            }
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: Theme.softShadow, radius: 8, x: 0, y: 4)
        }
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

    private func planRowContent(title: String, source: String) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Text("来自 \(source)")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(Theme.secondaryInk)
            }
            Spacer()
        }
    }

    private func completeTodo(_ item: LocalTodoItem) {
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
                moreCount: max(0, whiteboardItems.count - limitedItems.count)
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
                    moreCount: max(0, items.count - limitedItems.count)
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
}
