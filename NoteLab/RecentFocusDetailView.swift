import SwiftUI
import Combine

struct RecentFocusDetailView: View {
    @EnvironmentObject private var planStore: PlanStore
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                if let report = planStore.report {
                    structuredReport(report)
                } else if let markdown = planStore.rawReportMarkdown, !markdown.isEmpty {
                    markdownFallback(markdown)
                } else {
                    emptyState
                        .padding(.top, 80)
                }
            }
            .scrollEdgeEffectStyle(.hard, for: .top)
        }
        .background(Theme.background)
        .navigationBarBackButtonHidden(true)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button(action: { router.pop() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.glass)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    // MARK: - Structured Report

    private func structuredReport(_ report: AIRecentFocusReport) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Hero: title area
            heroBlock(report)

            // Content sections
            if !report.sections.isEmpty {
                sectionLabel("核心洞察")
                ForEach(report.sections.indices, id: \.self) { index in
                    sectionCard(report.sections[index])
                }
            }

            // Tables - Professional Report Style
            if !report.tables.isEmpty {
                sectionLabel("数据与计划表")
                ForEach(report.tables.indices, id: \.self) { index in
                    professionalTableCard(report.tables[index])
                }
            }

            // Sources
            if !report.sources.isEmpty {
                sectionLabel("引用来源")
                sourcesCard(report.sources)
            }

            Spacer(minLength: 32)
        }
        .padding(.top, 8)
    }

    // MARK: - Hero Block (no card wrapper)

    private func heroBlock(_ report: AIRecentFocusReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(report.timeRangeLabel.isEmpty ? "最近分析" : report.timeRangeLabel)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.blue, in: Capsule())
                
                Spacer()
                
                Text(Date(), style: .date)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.secondaryInk)
            }

            Text(report.title)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text(report.summary)
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(Theme.ink.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(4)
                
            Divider()
                .padding(.top, 8)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }

    // MARK: - Section Label

    private func sectionLabel(_ text: String) -> some View {
        HStack {
            Rectangle()
                .fill(Color.blue)
                .frame(width: 4, height: 16)
                .cornerRadius(2)
            Text(text)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .padding(.top, 8)
    }

    // MARK: - Section Card

    private func sectionCard(_ section: AIReportSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(section.heading)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)

            ForEach(section.paragraphs, id: \.self) { paragraph in
                Text(paragraph)
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundStyle(Theme.ink.opacity(0.8))
                    .lineSpacing(4)
            }

            if !section.bullets.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(section.bullets, id: \.self) { bullet in
                        let cleanBullet = bullet.hasPrefix("- ") ? String(bullet.dropFirst(2)) : bullet
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.blue.opacity(0.6))
                                .padding(.top, 3)
                            Text(cleanBullet)
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(Theme.ink.opacity(0.9))
                                .lineSpacing(3)
                        }
                    }
                }
                .padding(12)
                .background(Color.blue.opacity(0.03))
                .cornerRadius(12)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 15, x: 0, y: 10)
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    // MARK: - Professional Table Card

    private func professionalTableCard(_ table: AIReportTable) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "tablecells.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.blue)
                Text(table.title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Header row
                    HStack(spacing: 0) {
                        ForEach(table.columns.indices, id: \.self) { colIndex in
                            Text(table.columns[colIndex])
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.ink)
                                .frame(minWidth: 110, alignment: .leading)
                                .padding(.vertical, 12)
                                .padding(.horizontal, 12)
                        }
                    }
                    .background(Color.blue.opacity(0.08))

                    // Data rows
                    ForEach(table.rows.indices, id: \.self) { rowIndex in
                        HStack(spacing: 0) {
                            ForEach(table.columns.indices, id: \.self) { colIndex in
                                let value = colIndex < table.rows[rowIndex].count ? table.rows[rowIndex][colIndex] : ""
                                Text(value)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(Theme.ink.opacity(0.8))
                                    .frame(minWidth: 110, alignment: .leading)
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 12)
                            }
                        }
                        .background(rowIndex % 2 == 1 ? Color.gray.opacity(0.02) : Color.clear)

                        if rowIndex < table.rows.count - 1 {
                            Divider()
                                .padding(.horizontal, 8)
                        }
                    }
                }
                .background(Theme.cardBackground)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue.opacity(0.1), lineWidth: 1)
                )
            }

            if let notes = table.notes, !notes.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10))
                    Text(notes)
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                }
                .foregroundStyle(Theme.secondaryInk)
                .padding(.horizontal, 4)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.04), radius: 15, x: 0, y: 10)
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    // MARK: - Table Card (Old - kept for reference if needed, but replaced by professionalTableCard)
    // Removed to keep code clean since we are refactoring

    // MARK: - Sources Card

    private func sourcesCard(_ sources: [AIReportSourceNote]) -> some View {
        VStack(spacing: 0) {
            ForEach(sources.indices, id: \.self) { index in
                let source = sources[index]
                Button(action: { openSource(source) }) {
                    HStack(spacing: 12) {
                        // Colored dot
                        Circle()
                            .fill(sourceColor(index: index))
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(source.noteTitle)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(Theme.ink)
                            Text(source.notebookTitle)
                                .font(.system(size: 12, weight: .regular, design: .rounded))
                                .foregroundStyle(Theme.secondaryInk)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.secondaryInk.opacity(0.4))
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 14)
                }
                .buttonStyle(.plain)

                if index < sources.count - 1 {
                    Divider()
                        .padding(.leading, 34)
                        .opacity(0.15)
                }
            }
        }
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Theme.softShadow, radius: 10, x: 0, y: 6)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private func sourceColor(index: Int) -> Color {
        let colors: [Color] = [
            Color(red: 0.47, green: 0.78, blue: 0.78),  // teal
            Color(red: 0.67, green: 0.98, blue: 0.35),  // lime
            Color(red: 0.98, green: 0.69, blue: 0.35),  // orange
        ]
        return colors[index % colors.count]
    }

    // MARK: - Markdown Fallback

    private func markdownFallback(_ markdown: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("最近重点")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.ink)

            Text(markdown)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(Theme.ink.opacity(0.85))
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
        .padding(.top, 12)
    }

    // MARK: - Helpers

    private func openSource(_ source: AIReportSourceNote) {
        guard let id = UUID(uuidString: source.noteId) else { return }
        router.push(.note(id))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.secondaryInk)
            Text("暂无最近重点")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.secondaryInk)
        }
    }
}
