import SwiftUI
import Combine

struct LoginView: View {
    @EnvironmentObject private var auth: AuthManager
    @FocusState private var focusedField: Field?
    
    enum Field {
        case email, password
    }

    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isSignUp: Bool = false
    @State private var showPassword: Bool = false
    @State private var isAnimating: Bool = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            
            // 背景装饰
            backgroundDecoration
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 32) {
                    Spacer(minLength: 60)

                    // Logo & Header
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
                            
                            Text(isSignUp ? "创建你的数字笔记本" : "欢迎回来，继续你的创作")
                                .font(.system(size: 16, weight: .medium, design: .rounded))
                                .foregroundStyle(Theme.secondaryInk)
                        }
                        .offset(y: isAnimating ? 0 : 20)
                        .opacity(isAnimating ? 1.0 : 0)
                    }

                    // Input Fields
                    VStack(spacing: 16) {
                        customTextField(
                            title: "邮箱地址",
                            text: $email,
                            icon: "envelope.fill",
                            placeholder: "example@notelab.com",
                            field: .email
                        )
                        
                        customSecureField(
                            title: "登录密码",
                            text: $password,
                            icon: "lock.fill",
                            placeholder: "请输入密码",
                            field: .password
                        )
                    }
                    .padding(.horizontal, 24)
                    .offset(y: isAnimating ? 0 : 30)
                    .opacity(isAnimating ? 1.0 : 0)

                    if let error = auth.errorMessage, !error.isEmpty {
                        Text(error)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.red.opacity(0.9))
                            .padding(.horizontal, 24)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // Action Buttons
                    VStack(spacing: 20) {
                        Button {
                            handleAuthAction()
                        } label: {
                            HStack {
                                if auth.isLoading {
                                    ProgressView()
                                        .tint(.white)
                                        .padding(.trailing, 8)
                                }
                                Text(isSignUp ? "立即注册" : "登录账号")
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: Theme.buttonHeight)
                            .background(Theme.pillBlack, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .shadow(color: Theme.pillBlack.opacity(0.2), radius: 12, x: 0, y: 6)
                        }
                        .disabled(auth.isLoading || email.isEmpty || password.isEmpty)
                        .opacity(auth.isLoading || email.isEmpty || password.isEmpty ? 0.6 : 1.0)
                        
                        Button {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                isSignUp.toggle()
                                Haptics.shared.play(.selection)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(isSignUp ? "已有账号？" : "还没有账号？")
                                    .foregroundStyle(Theme.secondaryInk)
                                Text(isSignUp ? "立即登录" : "免费注册")
                                    .foregroundStyle(Theme.ink)
                                    .fontWeight(.bold)
                            }
                            .font(.system(size: 15, design: .rounded))
                        }
                    }
                    .padding(.horizontal, 24)
                    .offset(y: isAnimating ? 0 : 40)
                    .opacity(isAnimating ? 1.0 : 0)
                    
                    Spacer(minLength: 40)
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1)) {
                isAnimating = true
            }
        }
    }
    
    // MARK: - Components
    
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
    
    private func customTextField(title: String, text: Binding<String>, icon: String, placeholder: String, field: Field) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.secondaryInk)
                .padding(.leading, 4)
            
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(focusedField == field ? Theme.ink : Theme.secondaryInk)
                    .font(.system(size: 18))
                    .frame(width: 24)
                
                #if os(iOS)
                TextField(placeholder, text: text)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: field)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                #else
                TextField(placeholder, text: text)
                    .focused($focusedField, equals: field)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                #endif
            }
            .padding(.horizontal, 16)
            .frame(height: Theme.inputHeight)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.cardBackground)
                    .shadow(color: focusedField == field ? Theme.pillBlack.opacity(0.05) : Color.clear, radius: 8, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(focusedField == field ? Theme.ink.opacity(0.1) : Color.clear, lineWidth: 1)
            )
        }
    }
    
    private func customSecureField(title: String, text: Binding<String>, icon: String, placeholder: String, field: Field) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.secondaryInk)
                .padding(.leading, 4)
            
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(focusedField == field ? Theme.ink : Theme.secondaryInk)
                    .font(.system(size: 18))
                    .frame(width: 24)
                
                Group {
                    if showPassword {
                        TextField(placeholder, text: text)
                    } else {
                        SecureField(placeholder, text: text)
                    }
                }
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                #endif
                .focused($focusedField, equals: field)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                
                Button {
                    showPassword.toggle()
                } label: {
                    Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                        .foregroundStyle(Theme.secondaryInk)
                        .font(.system(size: 16))
                }
            }
            .padding(.horizontal, 16)
            .frame(height: Theme.inputHeight)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.cardBackground)
                    .shadow(color: focusedField == field ? Theme.pillBlack.opacity(0.05) : Color.clear, radius: 8, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(focusedField == field ? Theme.ink.opacity(0.1) : Color.clear, lineWidth: 1)
            )
        }
    }
    
    private func handleAuthAction() {
        focusedField = nil
        Haptics.shared.play(.tap(.medium))
        Task {
            if isSignUp {
                await auth.signUp(email: email, password: password)
            } else {
                await auth.signIn(email: email, password: password)
            }
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthManager())
}

