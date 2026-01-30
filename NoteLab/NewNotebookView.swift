import SwiftUI
import Combine

struct NewNotebookView: View {
    @EnvironmentObject private var store: NotebookStore
    @Binding var isPresented: Bool
    
    @State private var title: String = ""
    @State private var selectedColor: NotebookColor = .lime
    @State private var selectedIcon: String = "scribble"
    
    @State private var isAnimating = false
    @FocusState private var isTitleFocused: Bool
    
    private let icons: [String] = [
        "scribble", "paperplane", "sparkles", "moon.stars.fill",
        "paperclip", "triangle.fill", "book.fill", "bookmark.fill",
        "folder.fill", "star.fill", "heart.fill", "flag.fill"
    ]
    
    private var previewNotebook: Notebook {
        Notebook(
            id: UUID(),
            title: title.isEmpty ? "未命名笔记本" : title,
            color: selectedColor,
            iconName: selectedIcon,
            createdAt: Date(),
            notes: []
        )
    }
    
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
                    // 1. Preview Section
                    VStack(spacing: 16) {
                        Text("新建笔记本")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.secondaryInk)
                            .opacity(isAnimating ? 1 : 0)
                            .offset(y: isAnimating ? 0 : -20)
                        
                        NotebookCardView(notebook: previewNotebook, size: CGSize(width: 200, height: 280))
                            .shadow(color: Theme.cardShadow, radius: 30, x: 0, y: 15)
                            .scaleEffect(isAnimating ? 1 : 0.8)
                            .opacity(isAnimating ? 1 : 0)
                            .rotation3DEffect(
                                .degrees(isAnimating ? 0 : 10),
                                axis: (x: 1, y: 0, z: 0)
                            )
                    }
                    .padding(.top, 20)
                    
                    // 2. Input Section
                    VStack(spacing: 24) {
                        // Title Input
                        VStack(alignment: .leading, spacing: 8) {
                            Text("名称")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(Theme.secondaryInk)
                                .padding(.leading, 4)
                            
                            TextField("输入笔记本名称", text: $title)
                                .font(.system(size: 20, weight: .semibold, design: .rounded))
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
                        
                        // Color Selection
                        VStack(alignment: .leading, spacing: 12) {
                            Text("颜色")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(Theme.secondaryInk)
                                .padding(.leading, 4)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 16) {
                                    ForEach(NotebookColor.allCases, id: \.self) { color in
                                        colorButton(color)
                                    }
                                }
                                .padding(.horizontal, 4)
                                .padding(.vertical, 8)
                            }
                        }
                        .offset(y: isAnimating ? 0 : 40)
                        .opacity(isAnimating ? 1 : 0)
                        
                        // Icon Selection
                        VStack(alignment: .leading, spacing: 12) {
                            Text("图标")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(Theme.secondaryInk)
                                .padding(.leading, 4)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 16) {
                                    ForEach(icons, id: \.self) { icon in
                                        iconButton(icon)
                                    }
                                }
                                .padding(.horizontal, 4)
                                .padding(.vertical, 8)
                            }
                        }
                        .offset(y: isAnimating ? 0 : 50)
                        .opacity(isAnimating ? 1 : 0)
                    }
                    .padding(.horizontal, 24)
                    
                    Spacer(minLength: 40)
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
                        createNotebook()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.system(size: 20, weight: .bold))
                            Text("创建笔记本")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(Color.systemBackgroundAdaptive)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Theme.ink, in: Capsule())
                        .shadow(color: Theme.ink.opacity(0.3), radius: 12, x: 0, y: 6)
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.6 : 1)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
                .offset(y: isAnimating ? 0 : 100)
                .opacity(isAnimating ? 1 : 0)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                isAnimating = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isTitleFocused = true
            }
        }
    }
    
    private func colorButton(_ color: NotebookColor) -> some View {
        let isSelected = selectedColor == color
        
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                selectedColor = color
                Haptics.shared.play(.selection)
            }
        } label: {
            Circle()
                .fill(Color.notebook(color))
                .frame(width: 44, height: 44)
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .overlay {
                    Circle()
                        .stroke(Theme.background, lineWidth: 2)
                }
                .shadow(color: Color.notebook(color).opacity(0.4), radius: isSelected ? 8 : 4, x: 0, y: isSelected ? 4 : 2)
                .scaleEffect(isSelected ? 1.1 : 1.0)
        }
        .buttonStyle(.plain)
    }
    
    private func iconButton(_ icon: String) -> some View {
        let isSelected = selectedIcon == icon
        
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                selectedIcon = icon
                Haptics.shared.play(.selection)
            }
        } label: {
            ZStack {
                if isSelected {
                    Circle()
                        .fill(Theme.ink)
                        .frame(width: 44, height: 44)
                        .transition(.scale)
                } else {
                    Circle()
                        .fill(Theme.cardBackground)
                        .frame(width: 44, height: 44)
                }
                
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? .white : Theme.secondaryInk)
            }
            .shadow(color: Theme.softShadow, radius: 4, x: 0, y: 2)
            .scaleEffect(isSelected ? 1.1 : 1.0)
        }
        .buttonStyle(.plain)
    }
    
    private func dismiss() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            isAnimating = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            isPresented = false
        }
    }
    
    private func createNotebook() {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        
        Haptics.shared.play(.success)
        
        if store.addNotebook(title: name, color: selectedColor, iconName: selectedIcon) == nil {
            // Fallback
            store.notebooks.insert(
                Notebook(
                    id: UUID(),
                    title: name,
                    color: selectedColor,
                    iconName: selectedIcon,
                    createdAt: Date(),
                    notes: []
                ),
                at: 0
            )
        }
        
        dismiss()
    }
}
