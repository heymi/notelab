import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct MemoryCardView: View {
    let snippets: [MemorySnippet]
    let onRefresh: () -> Void
    let onOpenNote: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Flashback", systemImage: "clock.arrow.circlepath")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.secondaryInk)
                        .padding(8)
                        .background(Theme.groupedBackground, in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)

            if snippets.isEmpty {
                Text("No old notes to review yet.")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(Theme.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(snippets) { snippet in
                            Button(action: { onOpenNote(snippet.noteId) }) {
                                snippetContent(snippet)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20) // Space for shadow
                }
            }
        }
        .padding(.vertical, 20)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Theme.softShadow, radius: 12, x: 0, y: 6)
    }

    @ViewBuilder
    private func snippetContent(_ snippet: MemorySnippet) -> some View {
        if let data = snippet.imageData, let img = image(from: data) {
            img
                .resizable()
                .scaledToFill()
                .frame(width: 200, height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: Theme.softShadow, radius: 8, x: 0, y: 4)
                .overlay(alignment: .bottomLeading) {
                    Text(snippet.noteTitle)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(12)
                        .background(
                            LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .bottom, endPoint: .top)
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text(snippet.noteTitle)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                
                Text(snippet.excerpt)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(Theme.secondaryInk)
                    .lineLimit(6)
                    .lineSpacing(4)
                
                Spacer(minLength: 0)
                
                Text(snippet.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.secondaryInk.opacity(0.6))
            }
            .padding(16)
            .frame(width: 200, height: 240)
            .background(Theme.paper)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.secondaryInk.opacity(0.1), lineWidth: 1)
            )
            .shadow(color: Theme.softShadow, radius: 6, x: 0, y: 3)
        }
    }

    private func image(from data: Data) -> Image? {
        #if os(iOS)
        if let uiImage = UIImage(data: data) {
            return Image(uiImage: uiImage)
        }
        #elseif os(macOS)
        if let nsImage = NSImage(data: data) {
            return Image(nsImage: nsImage)
        }
        #endif
        return nil
    }
}

struct MessyNotesCardView: View {
    let candidates: [MessyNoteCandidate]
    let onAutoOrganize: (UUID) -> Void
    let onOpenNote: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Tidy Up", systemImage: "wand.and.stars")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Spacer()
                if !candidates.isEmpty {
                    Text("\(candidates.count) pending")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.secondaryInk)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.groupedBackground, in: Capsule())
                }
            }

            if candidates.isEmpty {
                Text("All notes are organized!")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(Theme.secondaryInk)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 12) {
                    ForEach(candidates) { item in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.noteTitle)
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Theme.ink)
                                    .lineLimit(1)
                                Text(item.reason)
                                    .font(.system(size: 13, weight: .regular, design: .rounded))
                                    .foregroundStyle(Theme.secondaryInk)
                                    .lineLimit(1)
                            }
                            Spacer()
                            
                            Button(action: { onAutoOrganize(item.noteId) }) {
                                Label("Organize", systemImage: "wand.and.stars")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Theme.ink, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(16)
                        .background(Theme.groupedBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .onTapGesture {
                            onOpenNote(item.noteId)
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Theme.softShadow, radius: 12, x: 0, y: 6)
    }
}

struct ConnectionCardView: View {
    let connections: [NoteConnection]
    let isLoading: Bool
    let errorMessage: String?
    let onOpenNote: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Discoveries", systemImage: "network")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)

            if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Connecting dots...")
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(Theme.secondaryInk)
                }
                .padding(.vertical, 8)
            } else if let errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(Theme.secondaryInk)
            } else if connections.isEmpty {
                Text("No new connections found.")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(Theme.secondaryInk)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 16) {
                    ForEach(connections) { item in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .center, spacing: 12) {
                                // Source
                                Text(item.sourceTitle)
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Theme.ink)
                                    .lineLimit(1)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Theme.paper)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .onTapGesture { onOpenNote(item.sourceNoteId) }
                                
                                // Link
                                Image(systemName: "link")
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundStyle(Theme.secondaryInk.opacity(0.5))
                                
                                // Target
                                Text(item.targetTitle)
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Theme.ink)
                                    .lineLimit(1)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Theme.paper)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .onTapGesture { onOpenNote(item.targetNoteId) }
                            }
                            
                            Text(item.reason)
                                .font(.system(size: 13, weight: .regular, design: .rounded))
                                .foregroundStyle(Theme.secondaryInk)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(16)
                        .background(Theme.groupedBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
            }
        }
        .padding(20)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Theme.softShadow, radius: 12, x: 0, y: 6)
    }
}
