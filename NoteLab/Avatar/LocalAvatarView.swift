import SwiftUI

/// Simple local avatar renderer.
/// The current `AvatarOptions` model only stores `avatarId`, so this view renders either:
/// - a bundled image named `avatarId`, or
/// - a fallback emoji mapped from `avatarId`, or
/// - a small text fallback.
struct LocalAvatarView: View {
    let options: AvatarOptions
    var size: CGFloat = 64

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.ink.opacity(0.06))
                .overlay(
                    Circle().stroke(Color.black.opacity(0.06), lineWidth: max(1, size * 0.01))
                )

#if canImport(UIKit)
            if let uiImage = UIImage(named: options.avatarId) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .clipShape(Circle())
            } else {
                fallback
            }
#elseif canImport(AppKit)
            if let nsImage = NSImage(named: options.avatarId) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
                    .clipShape(Circle())
            } else {
                fallback
            }
#else
            fallback
#endif
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private var fallback: some View {
        if let emoji = AvatarOptions.emoji(for: options.avatarId) {
            Text(emoji)
                .font(.system(size: size * 0.52, weight: .regular, design: .rounded))
                .foregroundStyle(Theme.ink)
        } else {
            Text(fallbackText)
                .font(.system(size: size * 0.28, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.ink)
        }
    }

    private var fallbackText: String {
        let raw = options.avatarId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "AV" }
        let parts = raw.split(separator: "_").map(String.init)
        if let last = parts.last, !last.isEmpty { return last.uppercased() }
        return String(raw.prefix(2)).uppercased()
    }
}
