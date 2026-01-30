import SwiftUI
import Combine
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct AvatarImageView: View {
    let options: AvatarOptions
    let initial: String
    let size: CGFloat

    var body: some View {
        ZStack {
            avatarImage
                .frame(width: size, height: size)
                .clipShape(Circle())
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private var avatarImage: some View {
#if canImport(UIKit)
        if let image = UIImage(named: options.avatarId) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            fallbackInitial
        }
#elseif canImport(AppKit)
        if let image = NSImage(named: options.avatarId) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else {
            fallbackInitial
        }
#else
        fallbackInitial
#endif
    }

    private var fallbackInitial: some View {
        if let emoji = AvatarOptions.emoji(for: options.avatarId) {
            Text(emoji)
                .font(.system(size: size * 0.5, weight: .regular, design: .rounded))
                .foregroundStyle(Theme.ink)
        } else {
            Text(initial)
                .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
        }
    }
}
