import AuthenticationServices
import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var auth: AuthManager
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            backgroundDecoration

            ScrollView(showsIndicators: false) {
                VStack(spacing: 32) {
                    Spacer(minLength: 72)

                    VStack(spacing: 16) {
                        ZStack {
                            WavyNotebookShape()
                                .fill(Color.notebook(.lime))
                                .frame(width: 80, height: 100)
                                .shadow(color: Color.notebook(.lime).opacity(0.3), radius: 15, x: 0, y: 8)
                                .rotationEffect(.degrees(isAnimating ? 0 : -10))

                            Image(systemName: "pencil.and.outline")
                                .font(.system(size: 30, weight: .bold))
                                .foregroundStyle(Theme.ink)
                        }
                        .scaleEffect(isAnimating ? 1.0 : 0.8)
                        .opacity(isAnimating ? 1.0 : 0)

                        VStack(spacing: 8) {
                            Text("NoteLab")
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.ink)

                            Text("使用 Apple 账号登录，数据通过 iCloud 同步")
                                .font(.system(size: 16, weight: .medium, design: .rounded))
                                .foregroundStyle(Theme.secondaryInk)
                                .multilineTextAlignment(.center)
                        }
                        .offset(y: isAnimating ? 0 : 20)
                        .opacity(isAnimating ? 1.0 : 0)
                    }

                    VStack(spacing: 14) {
                        SignInWithAppleButton(.signIn) { request in
                            auth.prepareAppleRequest(request)
                        } onCompletion: { result in
                            auth.handleAppleAuthorization(result)
                        }
                        .signInWithAppleButtonStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: Theme.buttonHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .disabled(auth.isLoading)
                        .opacity(auth.isLoading ? 0.65 : 1)

                        if auth.isLoading {
                            ProgressView()
                                .tint(Theme.secondaryInk)
                        }

                        simulatorLocalModeButton

                        if let error = auth.errorMessage, !error.isEmpty {
                            Text(error)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.red.opacity(0.9))
                                .multilineTextAlignment(.center)
                        }

                        Text("NoteLab 会使用当前设备的 iCloud 账户保存和同步笔记。Apple 登录账号与 iCloud 账号不一致时，同步仍以设备 iCloud 为准。")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.secondaryInk)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                    }
                    .padding(.horizontal, 24)
                    .offset(y: isAnimating ? 0 : 32)
                    .opacity(isAnimating ? 1.0 : 0)

                    Spacer(minLength: 48)
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1)) {
                isAnimating = true
            }
        }
    }

    private var backgroundDecoration: some View {
        ZStack {
            Circle()
                .fill(Color.notebook(.sky).opacity(0.2))
                .frame(width: 300, height: 300)
                .blur(radius: 60)
                .offset(x: -150, y: -200)

            Circle()
                .fill(Color.notebook(.lavender).opacity(0.2))
                .frame(width: 250, height: 250)
                .blur(radius: 50)
                .offset(x: 150, y: 300)
        }
    }

    @ViewBuilder
    private var simulatorLocalModeButton: some View {
        #if DEBUG && targetEnvironment(simulator)
        Button {
            auth.signInForSimulatorLocalUse()
        } label: {
            Text("Simulator Local Mode")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Theme.cardBackground)
                .foregroundStyle(Theme.ink)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Theme.secondaryInk.opacity(0.18), lineWidth: 1)
                )
        }
        .disabled(auth.isLoading)
        #endif
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthManager())
}
