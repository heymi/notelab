import SwiftUI
import Combine
import os

struct NotebookDetailView: View {
    @EnvironmentObject private var store: NotebookStore
    @EnvironmentObject private var router: AppRouter
    let notebookId: UUID
    private let layoutLogger = Logger(subsystem: "NoteLab", category: "Layout")

    @State private var noteToDelete: Note?
    @State private var showDeleteConfirmation = false
    @State private var showNotebookSettings = false
    @State private var showDeleteNotebookConfirmation = false
    @State private var isContentVisible = false

    private var notebookIndex: Int? {
        store.notebooks.firstIndex { $0.id == notebookId }
    }

    var body: some View {
        #if os(macOS)
        Group {
            if let index = notebookIndex {
                macNotebookDetail(index: index)
            } else {
                ContentUnavailableView("未找到笔记本", systemImage: "book.closed")
            }
        }
        .background(Theme.background)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    if let newId = store.addNote(to: notebookId) {
                        router.push(.note(newId))
                    }
                }) {
                    Label("新建笔记", systemImage: "square.and.pencil")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showNotebookSettings = true
                    } label: {
                        Label("笔记本设置", systemImage: "gearshape")
                    }
                    Divider()
                    Button("删除笔记本", role: .destructive) {
                        showDeleteNotebookConfirmation = true
                    }
                } label: {
                    Label("更多", systemImage: "ellipsis.circle")
                }
            }
        }
        .alert("删除笔记", isPresented: $showDeleteConfirmation, presenting: noteToDelete) { note in
            Button("取消", role: .cancel) {
                noteToDelete = nil
            }
            Button("删除", role: .destructive) {
                Haptics.shared.play(.tap(.heavy))
                store.deleteNote(noteId: note.id, from: notebookId)
                noteToDelete = nil
            }
        } message: { note in
            Text("确定要删除「\(note.title)」吗？此操作无法撤销。")
        }
        .alert("删除笔记本", isPresented: $showDeleteNotebookConfirmation) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                Haptics.shared.play(.tap(.heavy))
                store.deleteNotebook(id: notebookId)
                router.pop()
            }
        } message: {
            if let notebook = notebookIndex.map({ store.notebooks[$0] }) {
                Text("确定要删除「\(notebook.title)」吗？笔记本内的所有笔记也将被删除，此操作无法撤销。")
            } else {
                Text("确定要删除此笔记本吗？此操作无法撤销。")
            }
        }
        .sheet(isPresented: $showNotebookSettings) {
            if let index = notebookIndex {
                NotebookSettingsView(notebookId: notebookId)
                    .environmentObject(store)
                    .frame(width: 500, height: 600)
            }
        }
        #else
        VStack(spacing: 0) {
            header
            
            if let index = notebookIndex {
                let notebook = store.notebooks[index]
                let images = store.previewImages(for: notebook.id, limit: 2)
                
                ScrollView {
                    VStack(spacing: 18) {
                        NotebookCardView(notebook: notebook, size: CGSize(width: 180, height: 250), previewImages: images)
                            .padding(.top, 20)
                            .scaleEffect(isContentVisible ? 1 : 0.92)
                            .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.05), value: isContentVisible)

                        infoRow(notebook: notebook)
                            .opacity(isContentVisible ? 1 : 0)
                            .offset(y: isContentVisible ? 0 : 20)

                        notesList(notebookIndex: index)
                            .opacity(isContentVisible ? 1 : 0)
                            .offset(y: isContentVisible ? 0 : 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 140)
                    .padding(.top, 8)
                }
                .scrollEdgeEffectStyle(.hard, for: .top)
                .onAppear {
                    withAnimation(.easeOut(duration: 0.4).delay(0.1)) {
                        isContentVisible = true
                    }
                }
            } else {
                Text("未找到笔记本")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.secondaryInk)
                    .padding(.top, 80)
            }
        }
        .background(Theme.background)
        .background(InteractivePopGestureEnabler())
        .safeAreaInset(edge: .bottom) {
            Button {
                if let newId = store.addNote(to: notebookId) {
                    router.push(.note(newId))
                }
            } label: {
                Text("+ 笔记")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
                .glassEffect(.regular, in: .capsule)
                .shadow(color: Theme.cardShadow, radius: 12, x: 0, y: 8)
            }
            .padding(.bottom, 12)
            .transition(.scale.combined(with: .opacity))
        }
        .navigationBarBackButtonHidden(true)
        .alert("删除笔记", isPresented: $showDeleteConfirmation, presenting: noteToDelete) { note in
            Button("取消", role: .cancel) {
                noteToDelete = nil
            }
            Button("删除", role: .destructive) {
                Haptics.shared.play(.tap(.heavy))
                store.deleteNote(noteId: note.id, from: notebookId)
                noteToDelete = nil
            }
        } message: { note in
            Text("确定要删除「\(note.title)」吗？此操作无法撤销。")
        }
        .alert("删除笔记本", isPresented: $showDeleteNotebookConfirmation) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                Haptics.shared.play(.tap(.heavy))
                store.deleteNotebook(id: notebookId)
                router.pop()
            }
        } message: {
            if let notebook = notebookIndex.map({ store.notebooks[$0] }) {
                Text("确定要删除「\(notebook.title)」吗？笔记本内的所有笔记也将被删除，此操作无法撤销。")
            } else {
                Text("确定要删除此笔记本吗？此操作无法撤销。")
            }
        }
        .sheet(isPresented: $showNotebookSettings) {
            if let index = notebookIndex {
                NotebookSettingsView(notebookId: notebookId)
                    .environmentObject(store)
            }
        }
        #endif
    }

    #if os(macOS)
    private func macNotebookDetail(index: Int) -> some View {
        let notebook = store.notebooks[index]
        return List {
            Section {
                macNotebookHeader(notebook: notebook)
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            
            Section {
                macNotebookNotes(index: index)
            } header: {
                Text("笔记列表")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryInk)
            }
        }
        .listStyle(.inset)
    }

    private func macNotebookHeader(notebook: Notebook) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: notebook.iconName)
                    .font(.system(size: 28))
                    .foregroundStyle(Color.notebook(notebook.color))
                    .frame(width: 40)
                
                Text(notebook.title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
            }
            
            if !notebook.notebookDescription.isEmpty {
                Text(notebook.notebookDescription)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondaryInk)
                    .lineLimit(3)
            }
            
            HStack(spacing: 16) {
                Label("\(notebook.notes.count) 条笔记", systemImage: "doc.text")
                Label(notebook.createdAt.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
            }
            .font(.caption)
            .foregroundStyle(Theme.secondaryInk)
            .padding(.top, 4)
        }
        .padding(.vertical, 16)
    }

    private func macNotebookNotes(index: Int) -> some View {
        ForEach(store.notebooks[index].notes) { note in
            Button {
                router.push(.note(note.id))
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(note.title.isEmpty ? "无标题" : note.title)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.ink)
                    
                    if !note.contextText.isEmpty {
                        Text(note.contextText)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.secondaryInk)
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("删除", role: .destructive) {
                    noteToDelete = note
                    showDeleteConfirmation = true
                }
                Button(note.isPinned ? "取消置顶" : "置顶") {
                    store.toggleNotePinned(noteId: note.id, in: notebookId)
                }
            }
        }
    }
    #endif

    private var header: some View {
        GlassEffectContainer(spacing: 12) {
            HStack {
                Button(action: { router.pop() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.glass)
                Spacer()
                Menu {
                    Button("新建笔记") {
                        if let newId = store.addNote(to: notebookId) {
                            router.push(.note(newId))
                        }
                    }
                    Button {
                        showNotebookSettings = true
                    } label: {
                        Label("笔记本设置", systemImage: "gearshape")
                    }
                    Divider()
                    Button("删除笔记本", role: .destructive) {
                        showDeleteNotebookConfirmation = true
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .rotationEffect(.degrees(90))
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.glass)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    private func infoRow(notebook: Notebook) -> some View {
        HStack(spacing: 18) {
            infoItem(title: "条目", value: "\(notebook.notes.count)")
            Divider()
            infoItem(title: "创建", value: notebook.createdAt.formatted(date: .abbreviated, time: .omitted))
            Divider()
            infoItem(title: "颜色", value: notebook.color.displayName)
        }
        .font(.system(size: 13, weight: .medium, design: .rounded))
        .foregroundStyle(Theme.secondaryInk)
        .padding(.horizontal, 10)
    }

    private func infoItem(title: String, value: String) -> some View {
        VStack(spacing: 6) {
            Text(title)
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.ink)
        }
        .frame(maxWidth: .infinity)
    }

    private func notesList(notebookIndex: Int) -> some View {
        List {
            ForEach(store.notebooks[notebookIndex].notes) { note in
                Button {
                    Haptics.shared.play(.selection)
                    router.push(.note(note.id))
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                if note.isPinned {
                                    Image(systemName: "pin.fill")
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundStyle(Theme.secondaryInk)
                                }
                                Text(note.title)
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Theme.ink)
                            }
                            Text(note.contextText)
                                .font(.system(size: 13, weight: .regular, design: .rounded))
                                .foregroundStyle(Theme.secondaryInk)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.secondaryInk)
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        Haptics.shared.play(.tap(.medium))
                        noteToDelete = note
                        showDeleteConfirmation = true
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                    
                    Button {
                        Haptics.shared.play(.selection)
                        store.toggleNotePinned(noteId: note.id, in: notebookId)
                    } label: {
                        Label(note.isPinned ? "取消置顶" : "置顶", systemImage: note.isPinned ? "pin.slash" : "pin")
                    }
                    .tint(.orange)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Theme.softShadow, radius: 14, x: 0, y: 8)
        .frame(minHeight: CGFloat(store.notebooks[notebookIndex].notes.count * 70))
    }
}

private struct NoteRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Theme.ink.opacity(configuration.isPressed ? 0.06 : 0))
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - 笔记本设置视图

struct NotebookSettingsView: View {
    @EnvironmentObject private var store: NotebookStore
    @Environment(\.dismiss) private var dismiss
    
    let notebookId: UUID
    
    @State private var title: String = ""
    @State private var selectedColor: NotebookColor = .lime
    @State private var notebookDescription: String = ""
    @FocusState private var isDescriptionFocused: Bool
    
    private var notebook: Notebook? {
        store.notebooks.first { $0.id == notebookId }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // 笔记本名称
                    VStack(alignment: .leading, spacing: 10) {
                        Text("笔记本名称")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.secondaryInk)
                        
                        TextField("输入笔记本名称", text: $title)
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .shadow(color: Theme.softShadow, radius: 8, x: 0, y: 4)
                    }
                    
                    // 颜色选择
                    VStack(alignment: .leading, spacing: 10) {
                        Text("笔记本配色")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.secondaryInk)
                        
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 60))], spacing: 12) {
                            ForEach(NotebookColor.allCases, id: \.self) { color in
                                colorButton(color)
                            }
                        }
                        .padding(16)
                        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: Theme.softShadow, radius: 8, x: 0, y: 4)
                    }
                    
                    // 背景介绍
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("背景介绍")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(Theme.secondaryInk)
                            
                            Text("AI分析笔记时将参考此信息，帮助理解笔记的背景和上下文")
                                .font(.system(size: 12, weight: .regular, design: .rounded))
                                .foregroundStyle(Theme.secondaryInk.opacity(0.7))
                        }
                        
                        TextEditor(text: $notebookDescription)
                            .font(.system(size: 15, weight: .regular, design: .rounded))
                            .foregroundStyle(Theme.ink)
                            .frame(minHeight: 120)
                            .padding(12)
                            .scrollContentBackground(.hidden)
                            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .shadow(color: Theme.softShadow, radius: 8, x: 0, y: 4)
                            .focused($isDescriptionFocused)
                            .overlay(alignment: .topLeading) {
                                if notebookDescription.isEmpty && !isDescriptionFocused {
                                    Text("例如：这是我的工作笔记本，主要记录项目进度、会议要点和待办事项...")
                                        .font(.system(size: 15, weight: .regular, design: .rounded))
                                        .foregroundStyle(Theme.secondaryInk.opacity(0.5))
                                        .padding(16)
                                        .allowsHitTesting(false)
                                }
                            }
                    }
                    
                    Spacer(minLength: 40)
                }
                .padding(20)
            }
            .background(Theme.background)
            .navigationTitle("笔记本设置")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveChanges()
                        Haptics.shared.play(.selection)
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
        .onAppear {
            loadCurrentValues()
        }
    }
    
    private func colorButton(_ color: NotebookColor) -> some View {
        Button {
            Haptics.shared.play(.selection)
            selectedColor = color
        } label: {
            VStack(spacing: 6) {
                Circle()
                    .fill(colorValue(for: color))
                    .frame(width: 40, height: 40)
                    .overlay {
                        if selectedColor == color {
                            Image(systemName: "checkmark")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .shadow(color: colorValue(for: color).opacity(0.4), radius: 4, x: 0, y: 2)
                
                Text(color.displayName)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(selectedColor == color ? Theme.ink : Theme.secondaryInk)
            }
        }
        .buttonStyle(.plain)
    }
    
    private func colorValue(for color: NotebookColor) -> Color {
        return Color.notebook(color)
    }
    
    private func loadCurrentValues() {
        guard let notebook = notebook else { return }
        title = notebook.title
        selectedColor = notebook.color
        notebookDescription = notebook.notebookDescription
    }
    
    private func saveChanges() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        
        store.updateNotebook(
            id: notebookId,
            title: trimmedTitle,
            color: selectedColor,
            description: notebookDescription
        )
    }
}
