import SwiftUI
import Combine

struct SidebarView: View {
    @Binding var selection: AppTab
    @EnvironmentObject var store: NotebookStore
    @EnvironmentObject var router: AppRouter
    
    // Use a simpler selection state for the List to avoid conflicts
    @State private var selectedPanel: SidebarPanel? = .library
    
    enum SidebarPanel: Hashable {
        case library
        case list
        case whiteboard
        case plan
        case search
        case settings
        case notebook(UUID)
    }
    
    var body: some View {
        List(selection: $selectedPanel) {
            Section {
                NavigationLink(value: SidebarPanel.search) {
                    Label("搜索", systemImage: "magnifyingglass")
                }
                .listRowSeparator(.hidden)
                
                NavigationLink(value: SidebarPanel.list) {
                    Label("列表", systemImage: "list.bullet")
                }
                .listRowSeparator(.hidden)

                NavigationLink(value: SidebarPanel.plan) {
                    Label("计划", systemImage: "calendar")
                }
                .listRowSeparator(.hidden)
                
                NavigationLink(value: SidebarPanel.whiteboard) {
                    Label("白板", systemImage: "pencil.and.outline")
                }
                .listRowSeparator(.hidden)
            }
            
            Section("笔记本") {
                ForEach(store.notebooks) { notebook in
                    NavigationLink(value: SidebarPanel.notebook(notebook.id)) {
                        HStack {
                            Image(systemName: notebook.iconName)
                                .foregroundStyle(Color.notebook(notebook.color))
                            Text(notebook.title)
                        }
                    }
                    .listRowSeparator(.hidden)
                }
            }
            
            Section {
                NavigationLink(value: SidebarPanel.settings) {
                    Label("设置", systemImage: "gearshape")
                }
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("NoteLab")
        .onChange(of: selectedPanel) { _, newValue in
            guard let newValue else { return }
            switch newValue {
            case .library:
                selection = .library
                router.path.removeLast(router.path.count)
            case .list:
                selection = .list
                router.path.removeLast(router.path.count)
            case .whiteboard:
                selection = .whiteboard
                router.path.removeLast(router.path.count)
            case .plan:
                selection = .plan
                router.path.removeLast(router.path.count)
            case .search:
                selection = .search
                router.path.removeLast(router.path.count)
            case .settings:
                selection = .settings
                router.path.removeLast(router.path.count)
            case .notebook(let id):
                selection = .library
                // Push notebook to stack if not already there
                if router.path.isEmpty {
                    router.push(.notebook(id))
                } else {
                    // Reset and push
                    router.path.removeLast(router.path.count)
                    router.push(.notebook(id))
                }
            }
        }
    }
}
