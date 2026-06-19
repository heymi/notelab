import SwiftUI

struct BottomNavBar: View {
    @Binding var selection: AppTab
    let isVoiceRecording: Bool
    let voiceLevel: Double
    let onVoiceTap: () -> Void
    let onWhiteboardTap: () -> Void
    @Namespace private var animation

    init(
        selection: Binding<AppTab>,
        isVoiceRecording: Bool = false,
        voiceLevel: Double = 0,
        onVoiceTap: @escaping () -> Void = {},
        onWhiteboardTap: @escaping () -> Void = {}
    ) {
        self._selection = selection
        self.isVoiceRecording = isVoiceRecording
        self.voiceLevel = voiceLevel
        self.onVoiceTap = onVoiceTap
        self.onWhiteboardTap = onWhiteboardTap
    }

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
                        onVoiceTap()
                        Haptics.shared.play(.selection)
                    }) {
                        ZStack {
                            if isVoiceRecording {
                                Circle()
                                    .fill(Theme.ink.opacity(0.08 + 0.12 * voiceLevel))
                                    .scaleEffect(1.05 + 0.18 * voiceLevel)
                            }
                            Image(systemName: isVoiceRecording ? "stop.fill" : "mic.fill")
                                .font(.system(size: isVoiceRecording ? 21 : 24, weight: .semibold, design: .rounded))
                                .foregroundStyle(isVoiceRecording ? Theme.ink : Theme.secondaryInk)
                                .opacity(isVoiceRecording ? 1 : 0.75)
                                .scaleEffect(isVoiceRecording ? 1.04 : 1)
                        }
                        .frame(width: rightButtonSize, height: rightButtonSize)
                        .contentShape(Circle())
                        .glassEffect(.regular, in: Circle())
                        .shadow(color: Theme.softShadow, radius: 14, x: 0, y: 8)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            onVoiceTap()
                        } label: {
                            Label(isVoiceRecording ? "停止录音" : "语音输入", systemImage: isVoiceRecording ? "stop.fill" : "mic.fill")
                        }
                        Button {
                            onWhiteboardTap()
                        } label: {
                            Label("打开白板", systemImage: "pencil")
                        }
                    }
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
