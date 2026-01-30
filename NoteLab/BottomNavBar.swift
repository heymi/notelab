import SwiftUI

struct BottomNavBar: View {
    @Binding var selection: AppTab
    @Namespace private var animation

    var body: some View {
        GeometryReader { proxy in
            let bottomInset = max(proxy.safeAreaInsets.bottom, 12)
            let rightButtonSize: CGFloat = 64
            HStack(spacing: 14) {
                GlassEffectContainer(spacing: 10) {
                    HStack(spacing: 6) {
                        navButton(systemName: "book", tab: .library)
                        navButton(systemName: "list.bullet", tab: .list)
                        navButton(systemName: "sparkles", tab: .plan)
                        navButton(systemName: "gearshape", tab: .settings)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .glassEffect(.regular, in: Capsule())
                    .shadow(color: Theme.softShadow, radius: 14, x: 0, y: 8)
                }

                GlassEffectContainer(spacing: 0) {
                    Button(action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            selection = .whiteboard
                        }
                        Haptics.shared.play(.selection)
                    }) {
                        Image(systemName: "pencil")
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                            .foregroundStyle(selection == .whiteboard ? Theme.ink : Theme.secondaryInk)
                            .opacity(selection == .whiteboard ? 1 : 0.65)
                            .scaleEffect(selection == .whiteboard ? 1.02 : 1)
                            .frame(width: rightButtonSize, height: rightButtonSize)
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
