import SwiftUI
import Combine

struct SendSelectionView: View {
    @EnvironmentObject private var store: NotebookStore
    @Binding var isPresented: Bool
    
    let selectedText: String
    let onSend: (UUID, String) -> Void
    
    @State private var title: String = ""
    @State private var selectedNotebookId: UUID?
    @State private var isAnimating = false
    @FocusState private var isTitleFocused: Bool
    
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            
            // Background blur/dim
            Color.black.opacity(0.0)
                .ignoresSafeArea()
                .onTapGesture {
                    dismiss()
                }
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 32) {
                    // 1. Header & Preview
                    VStack(spacing: 16) {
                        Text("发送到笔记本")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.secondaryInk)
                            .opacity(isAnimating ? 1 : 0)
                            .offset(y: isAnimating ? 0 : -20)
                        
                        // Content Preview Card
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "quote.opening")
                                    .font(.system(size: 24))
                                    .foregroundStyle(Theme.secondaryInk.opacity(0.3))
                                Spacer()
                            }
                            
                            Text(selectedText)
                                .font(.system(size: 16, weight: .regular, design: .rounded))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(6)
                                .lineSpacing(4)
                            
                            HStack {
                                Spacer()
                                Image(systemName: "quote.closing")
                                    .font(.system(size: 24))
                                    .foregroundStyle(Theme.secondaryInk.opacity(0.3))
                            }
                        }
                        .padding(24)
                        .background(Theme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(color: Theme.cardShadow, radius: 20, x: 0, y: 10)
                        .scaleEffect(isAnimating ? 1 : 0.9)
                        .opacity(isAnimating ? 1 : 0)
                    }
                    .padding(.top, 20)
                    
                    // 2. Input Section
                    VStack(spacing: 24) {
                        // Title Input
                        VStack(alignment: .leading, spacing: 8) {
                            Text("笔记标题")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(Theme.secondaryInk)
                                .padding(.leading, 4)
                            
                            TextField("输入标题", text: $title)
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 16)
                                .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(isTitleFocused ? Theme.ink.opacity(0.2) : Color.clear, lineWidth: 1)
                                )
                                .shadow(color: Theme.softShadow, radius: 8, x: 0, y: 4)
                                .focused($isTitleFocused)
                                .submitLabel(.done)
                        }
                        .offset(y: isAnimating ? 0 : 30)
                        .opacity(isAnimating ? 1 : 0)
                        
                        // Notebook Selection
                        VStack(alignment: .leading, spacing: 12) {
                            Text("选择笔记本")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(Theme.secondaryInk)
                                .padding(.leading, 4)
                            
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 16) {
                                ForEach(store.notebooks) { notebook in
                                    NotebookSelectionCell(
                                        notebook: notebook,
                                        isSelected: selectedNotebookId == notebook.id,
                                        action: {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                selectedNotebookId = notebook.id
                                                Haptics.shared.play(.selection)
                                            }
                                        }
                                    )
                                }
                            }
                        }
                        .offset(y: isAnimating ? 0 : 40)
                        .opacity(isAnimating ? 1 : 0)
                    }
                    .padding(.horizontal, 24)
                    
                    Spacer(minLength: 100)
                }
            }
            
            // Floating Action Buttons
            VStack {
                Spacer()
                HStack(spacing: 16) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Theme.secondaryInk)
                            .frame(width: 56, height: 56)
                            .background(Theme.cardBackground, in: Circle())
                            .shadow(color: Theme.cardShadow, radius: 10, x: 0, y: 5)
                    }
                    
                    Button {
                        send()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 18, weight: .bold))
                            Text("发送")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(Color.systemBackgroundAdaptive)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Theme.ink, in: Capsule())
                        .shadow(color: Theme.ink.opacity(0.3), radius: 12, x: 0, y: 6)
                    }
                    .disabled(selectedNotebookId == nil)
                    .opacity(selectedNotebookId == nil ? 0.6 : 1)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
                .offset(y: isAnimating ? 0 : 100)
                .opacity(isAnimating ? 1 : 0)
            }
        }
        .onAppear {
            if title.isEmpty {
                title = defaultTitle(from: selectedText)
            }
            // Auto select first notebook if none selected
            if selectedNotebookId == nil, let first = store.notebooks.first {
                selectedNotebookId = first.id
            }
            
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                isAnimating = true
            }
        }
    }
    
    private func dismiss() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            isAnimating = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            isPresented = false
        }
    }
    
    private func send() {
        guard let notebookId = selectedNotebookId else { return }
        let finalTitle = title.isEmpty ? defaultTitle(from: selectedText) : title
        Haptics.shared.play(.success)
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onSend(notebookId, finalTitle)
        }
    }
    
    private func defaultTitle(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "新笔记" }
        return String(trimmed.prefix(20))
    }
}

struct NotebookSelectionCell: View {
    let notebook: Notebook
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.notebook(notebook.color).opacity(0.2))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: notebook.iconName)
                        .font(.system(size: 18))
                        .foregroundStyle(Color.notebook(notebook.color))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(notebook.title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    
                    Text("\(notebook.notes.count) 条笔记")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.secondaryInk)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.ink)
                        .transition(.scale)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Theme.cardBackground : Theme.cardBackground.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? Theme.ink : Color.clear, lineWidth: 2)
            )
            .shadow(color: isSelected ? Theme.softShadow : Color.clear, radius: 8, x: 0, y: 4)
            .scaleEffect(isSelected ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
    }
}
