import SwiftUI

struct GlobalAIStatusCard: View {
    let title: String
    let detail: String
    let isLoading: Bool
    let isCompleted: Bool
    let onCancel: () -> Void
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // Status Icon
            ZStack {
                if isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.green)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 20))
                        .foregroundStyle(.purple)
                        .symbolEffect(.pulse, isActive: isLoading)
                }
            }
            .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            if isLoading {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .background(.secondary.opacity(0.1), in: Circle())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
        .overlay(
            Capsule()
                .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
        )
        .onTapGesture {
            guard isCompleted else { return }
            onTap()
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isCompleted)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isLoading)
    }
}
