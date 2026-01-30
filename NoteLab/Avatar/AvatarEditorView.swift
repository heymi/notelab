import SwiftUI
import Combine
import Auth

struct AvatarEditorView: View {
    @EnvironmentObject private var avatarStore: AvatarStore
    @EnvironmentObject private var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedAvatarId: String = AvatarOptions.allAvatarIds.first ?? "avatar_01"

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                previewCard

                avatarGrid

                HStack(spacing: 12) {
                    Button {
                        selectedAvatarId = avatarStore.availableAvatarIds.randomElement() ?? selectedAvatarId
                    } label: {
                        Text("随机一个")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        avatarStore.setAvatarId(selectedAvatarId)
                        dismiss()
                    } label: {
                        Text("保存")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(Theme.ink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("更改头像")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            selectedAvatarId = avatarStore.options.avatarId
        }
    }

    private var previewCard: some View {
        let emailFirst = auth.session?.user.email?.first
        let initial = String((emailFirst ?? "U").uppercased())
        return VStack(spacing: 12) {
            AvatarImageView(options: AvatarOptions(avatarId: selectedAvatarId), initial: initial, size: 96)
            Text("预览")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.secondaryInk)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Theme.softShadow, radius: 8, x: 0, y: 4)
    }

    private var avatarGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 72), spacing: 12)]
        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(avatarStore.availableAvatarIds, id: \.self) { avatarId in
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        selectedAvatarId = avatarId
                        Haptics.shared.play(.selection)
                    }
                } label: {
                    ZStack {
                        AvatarImageView(
                            options: AvatarOptions(avatarId: avatarId),
                            initial: "U",
                            size: 64
                        )
                        if selectedAvatarId == avatarId {
                            Circle()
                                .stroke(Theme.ink, lineWidth: 2)
                        }
                    }
                    .frame(width: 72, height: 72)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
    }
}
