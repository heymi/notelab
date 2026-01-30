import SwiftUI
import Auth

struct BottomNavBar: View {
    @Binding var selection: AppTab
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var avatarStore: AvatarStore
    @Namespace private var animation

    var body: some View {
        GeometryReader { proxy in
            let bottomInset = max(proxy.safeAreaInsets.bottom, 12)
            let searchButtonSize: CGFloat = 64
            let searchIconSize: CGFloat = 22
            HStack(spacing: 14) {
                GlassEffectContainer(spacing: 10) {
                    HStack(spacing: 6) {
                        navButton(systemName: "book", tab: .library)
                        navButton(systemName: "list.bullet", tab: .list)
                        navButton(systemName: "pencil.and.outline", tab: .whiteboard)
                        navButton(systemName: "bubble.left.and.bubble.right", tab: .plan)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .glassEffect(.regular, in: Capsule())
                    .shadow(color: Theme.softShadow, radius: 14, x: 0, y: 8)
                }

                GlassEffectContainer(spacing: 0) {
                    Button(action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            selection = .settings
                        }
                        Haptics.shared.play(.selection)
                    }) {
                        userAvatar
                            .frame(width: searchButtonSize, height: searchButtonSize)
                            .contentShape(Circle())
                            .glassEffect(.regular, in: Circle())
                            .shadow(color: Theme.softShadow, radius: 14, x: 0, y: 8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.horizontal, 18)
            .padding(.bottom, bottomInset)
            .allowsHitTesting(true)
        }
        .frame(height: 90)
    }

    private var userAvatar: some View {
        let emailFirst = auth.session?.user.email?.first
        let initial = String((emailFirst ?? "U").uppercased())
        return AvatarImageView(
            options: avatarStore.options,
            initial: initial,
            size: 42
        )
        .opacity(selection == .settings ? 1 : 0.92)
        .scaleEffect(selection == .settings ? 1.02 : 1)
    }

    private func navButton(systemName: String, tab: AppTab) -> some View {
        let isSelected = selection == tab
        return Button(action: {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                selection = tab
            }
            Haptics.shared.play(.selection)
        }) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(isSelected ? Theme.ink : Theme.secondaryInk)
                .opacity(isSelected ? 1 : 0.65)
                .scaleEffect(isSelected ? 1.02 : 1)
                .frame(width: 44, height: 44)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Theme.ink.opacity(0.06))
                            .matchedGeometryEffect(id: "TabIndicator", in: animation)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
