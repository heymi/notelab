import SwiftUI
import Combine
import Auth

enum LibraryMode: String, CaseIterable {
    case notes
    case materials
}

struct LibraryView: View {
    @EnvironmentObject private var store: NotebookStore
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var avatarStore: AvatarStore
    @Binding var tabSelection: AppTab
    @State private var mode: LibraryMode = .notes
    @State private var showNewNotebook = false

    var body: some View {
        #if os(macOS)
        ScrollView {
            content
                .padding()
        }
        .background(Theme.background)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showNewNotebook = true }) {
                    Label("新建笔记本", systemImage: "plus")
                }
            }
            ToolbarItemGroup(placement: .secondaryAction) {
                Picker("视图", selection: $mode) {
                    Text("笔记").tag(LibraryMode.notes)
                    Text("素材").tag(LibraryMode.materials)
                }
                .pickerStyle(.segmented)
            }
        }
        .sheet(isPresented: $showNewNotebook) {
            NewNotebookView(isPresented: $showNewNotebook)
                .environmentObject(store)
                .frame(width: 500, height: 650)
        }
        #else
        VStack(spacing: 0) {
            header
            
            ScrollView {
                content
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                    .padding(.top, 10)
            }
            .scrollEdgeEffectStyle(.hard, for: .top)
        }
        .background(Theme.background)
        .fullScreenCover(isPresented: $showNewNotebook) {
            NewNotebookView(isPresented: $showNewNotebook)
                .environmentObject(store)
        }
        #endif
    }

    private var header: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                // Left: Tab Picker
                customSegmentedPicker
                
                Spacer()
                
                // Right: Plus Button + Avatar
                HStack(spacing: 10) {
                    Button(action: {
                        Haptics.shared.play(.tap(.medium))
                        showNewNotebook = true
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .frame(width: actionButtonSize, height: actionButtonSize)
                    }
                    .buttonStyle(.glass)
                    
                    // Search (moved from bottom nav)
                    Button(action: {
                        Haptics.shared.play(.tap(.light))
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            tabSelection = .search
                        }
                    }) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .frame(width: actionButtonSize, height: actionButtonSize)
                    }
                    .buttonStyle(.glass)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 28)
    }
    
    private var userAvatar: some View {
        let emailFirst = auth.session?.user.email?.first
        let initial = String((emailFirst ?? "U").uppercased())
        return AvatarImageView(
            options: avatarStore.options,
            initial: initial,
            size: actionButtonSize
        )
    }

    private let actionButtonSize: CGFloat = 36

    private var customSegmentedPicker: some View {
        HStack(spacing: 0) {
            ForEach(LibraryMode.allCases, id: \.self) { item in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        mode = item
                        Haptics.shared.play(.selection)
                    }
                } label: {
                    Text(item == .notes ? "Notes" : "Assets")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(mode == item ? Theme.ink : Theme.secondaryInk)
                        .frame(width: 80, height: 38)
                        .background {
                            if mode == item {
                                Capsule()
                                    .fill(Color.white)
                                    .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                                    .matchedGeometryEffect(id: "picker_tab", in: pickerNamespace)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.black.opacity(0.05))
        .clipShape(Capsule())
    }

    @Namespace private var pickerNamespace

    @ViewBuilder
    private var content: some View {
        // #region agent log
        let _ = DebugReporter.log(
            hypothesisId: "H6",
            location: "LibraryView.swift:content",
            message: "LibraryView content rendering",
            data: ["notebooksCount": store.notebooks.count, "mode": mode.rawValue]
        )
        // #endregion
        switch mode {
        case .notes:
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 18), GridItem(.flexible(), spacing: 18)], spacing: 18) {
                ForEach(store.notebooks) { notebook in
                    notebookItem(notebook: notebook)
                }
            }
        case .materials:
            MaterialsLibraryView()
        }
    }
    
    @ViewBuilder
    private func notebookItem(notebook: Notebook) -> some View {
        let images = store.previewImagesCached(for: notebook.id)
        
        Button {
            Haptics.shared.play(.tap(.light))
            router.push(.notebook(notebook.id))
        } label: {
            NotebookCardView(notebook: notebook, previewImages: images)
        }
        .buttonStyle(.plain)
        .task(id: notebook.id) {
            await store.loadPreviewImagesIfNeeded(notebookId: notebook.id, limit: 2)
        }
        .contextMenu {
            Button {
                Haptics.shared.play(.selection)
                store.toggleNotebookPinned(notebookId: notebook.id)
            } label: {
                Label(notebook.isPinned ? "取消置顶" : "置顶", systemImage: notebook.isPinned ? "pin.slash" : "pin")
            }
        }
    }
}
