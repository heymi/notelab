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

                if !isVoiceRecording {
                    GlassEffectContainer(spacing: 0) {
                        Button(action: onVoiceTap) {
                            ZStack {
                                FlameGlassButtonBackground()

                                VoiceNavGlyph()
                                    .opacity(0.9)
                            }
                            .frame(width: 64, height: 64)
                            .contentShape(Capsule())
                            .clipShape(Capsule())
                            .overlay {
                                Capsule()
                                    .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                            }
                            .accessibilityLabel("语音输入")
                                .shadow(color: Theme.softShadow, radius: 14, x: 0, y: 8)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(action: onVoiceTap) {
                                Label("语音输入", systemImage: "waveform")
                            }
                            Button {
                                onWhiteboardTap()
                            } label: {
                                Label("打开白板", systemImage: "pencil")
                            }
                        }
                    }
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
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

private struct VoiceNavGlyph: View {
    var body: some View {
        HStack(spacing: 3.5) {
            ForEach(0..<5, id: \.self) { index in
                Capsule()
                    .fill(.white.opacity(0.92))
                    .frame(width: 3.5, height: idleHeight(index))
            }
        }
        .frame(width: 32, height: 32)
    }

    private func idleHeight(_ index: Int) -> CGFloat {
        let heights: [CGFloat] = [9, 16, 23, 15, 10]
        return heights[index]
    }
}
