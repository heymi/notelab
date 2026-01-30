import SwiftUI
import Combine

struct AllNotesListView: View {
    @EnvironmentObject private var store: NotebookStore
    @EnvironmentObject private var router: AppRouter
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            header

            List {
                // 1. Pinned Section
                if !pinnedRows.isEmpty {
                    Section {
                        ForEach(pinnedRows) { row in
                            noteRow(row)
                        }
                    } header: {
                        Text("置顶")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.secondaryInk)
                            .textCase(nil)
                    }
                }

                // 2. Time-based Sections
                ForEach(timeSections, id: \.title) { section in
                    if !section.rows.isEmpty {
                        Section {
                            ForEach(section.rows) { row in
                                noteRow(row)
                            }
                        } header: {
                            Text(section.title)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(Theme.secondaryInk)
                                .textCase(nil)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .overlay {
                if filteredRows.isEmpty {
                    if searchText.isEmpty {
                        ContentUnavailableView("暂无笔记", systemImage: "doc.text")
                    } else {
                        ContentUnavailableView.search(text: searchText)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 90)
            }
        }
        .background(Theme.background)
    }

    // MARK: - Data Source

    private var allRows: [AllNotesRow] {
        store.notebooks.flatMap { notebook in
            notebook.notes.map { note in
                AllNotesRow(
                    note: note,
                    notebookId: notebook.id,
                    notebookTitle: notebook.title,
                    notebookIconName: notebook.iconName,
                    notebookColor: notebook.color
                )
            }
        }
    }

    private var filteredRows: [AllNotesRow] {
        let rows = allRows
        if searchText.isEmpty {
            return rows
        } else {
            return rows.filter { row in
                row.note.title.localizedCaseInsensitiveContains(searchText) ||
                row.note.content.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    private var pinnedRows: [AllNotesRow] {
        filteredRows
            .filter { $0.note.isPinned }
            .sorted { $0.note.updatedAt > $1.note.updatedAt }
    }

    private var unpinnedRows: [AllNotesRow] {
        filteredRows
            .filter { !$0.note.isPinned }
            .sorted { $0.note.updatedAt > $1.note.updatedAt }
    }

    // MARK: - Section Logic

    private struct TimeSection {
        let title: String
        let rows: [AllNotesRow]
    }

    private var timeSections: [TimeSection] {
        var sections: [TimeSection] = []
        let rows = unpinnedRows
        let calendar = Calendar.current
        let now = Date()

        // Helper to filter rows
        func filterRows(where condition: (Date) -> Bool) -> [AllNotesRow] {
            rows.filter { condition($0.note.updatedAt) }
        }

        // Today
        let todayRows = filterRows { calendar.isDateInToday($0) }
        if !todayRows.isEmpty {
            sections.append(TimeSection(title: "今天", rows: todayRows))
        }

        // Yesterday
        let yesterdayRows = filterRows { calendar.isDateInYesterday($0) }
        if !yesterdayRows.isEmpty {
            sections.append(TimeSection(title: "昨天", rows: yesterdayRows))
        }

        // Previous 7 Days (excluding today and yesterday)
        // logic: date > 7 days ago AND not today AND not yesterday
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now)!
        let sevenDaysRows = filterRows { date in
            date > sevenDaysAgo && !calendar.isDateInToday(date) && !calendar.isDateInYesterday(date)
        }
        if !sevenDaysRows.isEmpty {
            sections.append(TimeSection(title: "过去 7 天", rows: sevenDaysRows))
        }

        // Previous 30 Days (excluding previous 7 days)
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now)!
        let thirtyDaysRows = filterRows { date in
            date > thirtyDaysAgo && date <= sevenDaysAgo
        }
        if !thirtyDaysRows.isEmpty {
            sections.append(TimeSection(title: "过去 30 天", rows: thirtyDaysRows))
        }

        // Earlier (older than 30 days)
        // Group by Month/Year if needed, but for now just "Earlier" or Month name
        let earlierRows = filterRows { date in
            date <= thirtyDaysAgo
        }
        
        // Optional: Group earlier rows by Month
        if !earlierRows.isEmpty {
            // Simple approach: just one "Earlier" section or broken down by month
            // Let's do "Earlier" for simplicity as per screenshot usually has specific buckets
            // Or we can group by "January 2026", "December 2025" etc.
            // Let's stick to a simple "更早" for now to match the style of "buckets"
            sections.append(TimeSection(title: "更早", rows: earlierRows))
        }

        return sections
    }

    // MARK: - Row View

    private func noteRow(_ row: AllNotesRow) -> some View {
        Button {
            router.push(.note(row.note.id))
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                // Title
                Text(row.note.title.isEmpty ? "无标题" : row.note.title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)

                // Date & Preview
                HStack(spacing: 6) {
                    Text(row.note.updatedAt.formatted(date: .numeric, time: .omitted))
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(Theme.secondaryInk)
                        .fixedSize()

                    Text(snippetText(for: row.note))
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(Theme.secondaryInk.opacity(0.8))
                        .lineLimit(1)
                }

                // Notebook/Folder Info
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.system(size: 12, weight: .medium))
                    Text(row.notebookTitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                }
                .foregroundStyle(Theme.secondaryInk.opacity(0.7))
            }
            .padding(.vertical, 4)
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack {
                Text("全部备忘录")
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

                TextField("搜索", text: $searchText)
                    .font(.system(size: 16, design: .rounded))

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
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
    }

    private func snippetText(for note: Note) -> String {
        let content = note.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if content.isEmpty { return "暂无内容" }
        // Remove markdown symbols for cleaner preview
        return content.replacingOccurrences(of: "#", with: "")
                      .replacingOccurrences(of: "*", with: "")
                      .replacingOccurrences(of: "`", with: "")
                      .replacingOccurrences(of: "\n", with: " ")
    }
}

private struct AllNotesRow: Identifiable {
    let note: Note
    let notebookId: UUID
    let notebookTitle: String
    let notebookIconName: String
    let notebookColor: NotebookColor

    var id: UUID { note.id }
}
