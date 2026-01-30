import SwiftUI

struct AIMenuSheet: View {
    @Binding var isPresented: Bool
    let hasUndo: Bool
    let onAutoOrganize: () -> Void
    let onExtractTodos: () -> Void
    let onRewrite: (AIRewriteMode) -> Void
    let onUndo: () -> Void
    
    @State private var navigationPath: [MenuPage] = []
    
    enum MenuPage {
        case commandSelection
    }
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            mainMenu
                .navigationDestination(for: MenuPage.self) { page in
                    switch page {
                    case .commandSelection:
                        commandSelectionMenu
                    }
                }
        }
        .presentationDetents([.height(320), .medium])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(24)
    }
    
    private var mainMenu: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("AI 助手")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Spacer()
                if hasUndo {
                    Button(action: {
                        onUndo()
                        isPresented = false
                    }) {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            
            // Cards
            HStack(spacing: 16) {
                // Auto Organize Card
                Button {
                    onAutoOrganize()
                    isPresented = false
                } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        Circle()
                            .fill(LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 44, height: 44)
                            .overlay(
                                Image(systemName: "sparkles")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(.white)
                            )
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("自动整理")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(.primary)
                            Text("一键优化排版")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
                }
                
                // Commands Card
                Button {
                    navigationPath.append(.commandSelection)
                } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        Circle()
                            .fill(LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 44, height: 44)
                            .overlay(
                                Image(systemName: "command")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.white)
                            )
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("指定命令")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(.primary)
                            Text("提取、扩写等")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
                }
            }
            .padding(.horizontal, 20)
            
            Spacer()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationBarHidden(true)
    }
    
    private var commandSelectionMenu: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: { navigationPath.removeLast() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: Circle())
                }
                
                Spacer()
                
                Text("选择命令")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                
                Spacer()
                
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            
            ScrollView {
                VStack(spacing: 12) {
                    commandRow(title: "提取待办事情", icon: "checklist", color: .orange) {
                        onExtractTodos()
                        isPresented = false
                    }
                    
                    commandRow(title: "优化排版与书写", icon: "text.quote", color: .blue) {
                        onRewrite(.optimize)
                        isPresented = false
                    }
                    
                    commandRow(title: "内容去重与精炼", icon: "scissors", color: .pink) {
                        onRewrite(.dedupe)
                        isPresented = false
                    }
                    
                    commandRow(title: "笔记扩写", icon: "wand.and.stars", color: .purple) {
                        onRewrite(.expand)
                        isPresented = false
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationBarHidden(true)
    }
    
    private func commandRow(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(color)
                    .frame(width: 36, height: 36)
                    .background(color.opacity(0.1), in: Circle())
                
                Text(title)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}
