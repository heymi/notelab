import SwiftUI
import Combine
import Auth

struct SettingsView: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject private var avatarStore: AvatarStore
    @AppStorage("isPremium") private var isPremium: Bool = false
    @AppStorage("appearanceMode") private var appearanceMode: Int = 0 // 0: Auto, 1: Light, 2: Dark
    @AppStorage("launchPage") private var launchPage: String = "library"
    @State private var showClearCacheConfirm = false
    @State private var cacheCleared = false
    @State private var showAISettings = false
    @ObservedObject private var aiSettings = AISettings.shared
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Profile Header
                profileHeader
                
                // Premium Banner
                NavigationLink(destination: PremiumIntroView()) {
                    premiumBanner
                }
                .buttonStyle(.plain)
                
                // Settings Groups
                VStack(spacing: 20) {
                    // General & Personalization
                    SettingsSection(title: "个性化") {
                        NavigationLink {
                            AvatarEditorView()
                        } label: {
                            SettingsRow(
                                icon: "person.crop.circle",
                                iconColor: .purple,
                                title: "更改头像",
                                showArrow: true
                            )
                        }

                        Divider().padding(.leading, 16)

                        // Appearance
                        VStack(alignment: .leading, spacing: 12) {
                            Text("外观模式")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Theme.ink)
                                .padding(.horizontal, 16)
                                .padding(.top, 12)
                            
                            AppearanceSelector(mode: $appearanceMode)
                                .padding(.horizontal, 12)
                                .padding(.bottom, 8)
                        }
                        
                        Divider().padding(.leading, 16)
                        
                        // Launch Page
                        HStack {
                            SettingsIcon(icon: "arrow.up.forward.app.fill", color: .indigo)
                            Text("启动页面")
                                .font(.system(size: 16, weight: .medium, design: .rounded))
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Picker("", selection: $launchPage) {
                                Text("笔记本").tag("library")
                                Text("全部备忘录").tag("list")
                                Text("白板").tag("whiteboard")
                            }
                            .tint(Theme.secondaryInk)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                    }
                    
                    // AI Settings
                    SettingsSection(title: "AI 设置") {
                        Button {
                            showAISettings = true
                        } label: {
                            HStack(spacing: 16) {
                                SettingsIcon(icon: "sparkles", color: .purple)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("AI 模型")
                                        .font(.system(size: 16, weight: .medium, design: .rounded))
                                        .foregroundStyle(Theme.ink)
                                    Text(aiSettings.currentProvider.displayName)
                                        .font(.system(size: 13, weight: .regular, design: .rounded))
                                        .foregroundStyle(Theme.secondaryInk)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Theme.secondaryInk.opacity(0.5))
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // Account
                    SettingsSection(title: "账号") {
                        SettingsRow(
                            icon: "person.fill",
                            iconColor: .blue,
                            title: "当前账号",
                            detail: auth.session?.user.email ?? "未登录"
                        )
                    }
                    
                    // About & Legal
                    SettingsSection(title: "关于") {
                        NavigationLink {
                            LegalWebView(title: "隐私政策", url: URL(string: "https://notelab.example.com/privacy")!)
                        } label: {
                            SettingsRow(icon: "hand.raised.fill", iconColor: .purple, title: "隐私政策", showArrow: true)
                        }
                        
                        Divider().padding(.leading, 52)
                        
                        NavigationLink {
                            LegalWebView(title: "服务条款", url: URL(string: "https://notelab.example.com/terms")!)
                        } label: {
                            SettingsRow(icon: "doc.text.fill", iconColor: .orange, title: "服务条款", showArrow: true)
                        }
                        
                        Divider().padding(.leading, 52)
                        
                        SettingsRow(
                            icon: "info.circle.fill",
                            iconColor: .gray,
                            title: "版本",
                            detail: "1.0.0 (1)"
                        )
                    }
                    
                    // Data Management
                    SettingsSection(title: "数据") {
                        Button(action: {
                            showClearCacheConfirm = true
                        }) {
                            HStack {
                                SettingsIcon(icon: "trash.fill", color: .red)
                                Text("清除本地缓存")
                                    .font(.system(size: 16, weight: .medium, design: .rounded))
                                    .foregroundStyle(Theme.ink)
                                Spacer()
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // Sign Out (Weakened)
                    Button(action: {
                        Task {
                            await auth.signOut()
                        }
                    }) {
                        Text("退出登录")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.secondaryInk)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 16)
                            .background(Theme.groupedBackground)
                    .clipShape(.rect(cornerRadius: 8))
                    }
                    .padding(.top, 10)
                }
                
                Spacer(minLength: 40)
            }
            .padding(20)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("设置")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .alert("清除本地缓存", isPresented: $showClearCacheConfirm) {
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) {
                clearLocalCache()
            }
        } message: {
            Text("这将清除所有本地存储的数据。您的云端数据不会受影响，重新登录后会自动同步。")
        }
        .alert("缓存已清除", isPresented: $cacheCleared) {
            Button("确定", role: .cancel) {
                Task {
                    await auth.signOut()
                }
            }
        } message: {
            Text("本地缓存已清除，请重新登录以同步数据。")
        }
        .sheet(isPresented: $showAISettings) {
            AISettingsView()
        }
        .onAppear {
            sanitizeUserDefaults()
        }
    }
    
    private func sanitizeUserDefaults() {
        let defaults = UserDefaults.standard
        if let value = defaults.object(forKey: "ai.provider"), !(value is String) {
            defaults.set(AIProvider.gemini.rawValue, forKey: "ai.provider")
        }
        if let value = defaults.object(forKey: "launchPage"), !(value is String) {
            defaults.set("library", forKey: "launchPage")
        }
        if let value = defaults.object(forKey: "appearanceMode"), !(value is Int) {
            defaults.set(0, forKey: "appearanceMode")
        }
        if let value = defaults.object(forKey: "isPremium"), !(value is Bool) {
            defaults.set(false, forKey: "isPremium")
        }
    }
    
    private func clearLocalCache() {
        do {
            try PersistenceController.resetStore()
            UserDefaults.standard.set(0, forKey: "schemaVersion")
            AttachmentStorage.shared.clearCache()
            cacheCleared = true
        } catch {
            print("Failed to clear cache: \(error)")
        }
    }
    
    @ViewBuilder
    private var profileHeader: some View {
        HStack(spacing: 16) {
            ZStack {
                let emailFirst = auth.session?.user.email?.first
                let initial = String((emailFirst ?? "U").uppercased())
                AvatarImageView(
                    options: avatarStore.options,
                    initial: initial,
                    size: 64
                )
            }
            
            VStack(alignment: .leading, spacing: 4) {
            let emailPrefix = auth.session?.user.email?.components(separatedBy: "@").first ?? "用户"
                Text(emailPrefix)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                
                Text(isPremium ? "NoteLab Pro 会员" : "免费版用户")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.secondaryInk)
            }
            
            Spacer()
        }
        .padding(.vertical, 10)
    }
    
    private var premiumBanner: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: isPremium ?
                            [Color(hex: "FFD700"), Color(hex: "FFA500")] :
                            [Theme.cardBackground, Theme.cardBackground],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: isPremium ? Color.orange.opacity(0.3) : Theme.softShadow, radius: 10, x: 0, y: 5)
            
            if !isPremium {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Theme.groupedBackground, lineWidth: 1)
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(isPremium ? "尊享会员权益" : "升级到 Pro")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(isPremium ? .white : Theme.ink)
                    
                    Text(isPremium ? "您已解锁所有高级功能" : "解锁无限笔记本、AI 助手等高级功能")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(isPremium ? .white.opacity(0.9) : Theme.secondaryInk)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(isPremium ? .white.opacity(0.8) : Theme.secondaryInk.opacity(0.5))
            }
            .padding(20)
        }
    }
}

// MARK: - Components

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.secondaryInk)
                .padding(.leading, 8)
            
            VStack(spacing: 0) {
                content()
            }
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Theme.softShadow, radius: 8, x: 0, y: 4)
        }
    }
}

struct SettingsIcon: View {
    let icon: String
    let color: Color
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.15))
                .frame(width: 32, height: 32)
            
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(color)
        }
    }
}

struct SettingsRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    var detail: String = ""
    var showArrow: Bool = false
    
    var body: some View {
        HStack(spacing: 16) {
            SettingsIcon(icon: icon, color: iconColor)
            
            Text(title)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.ink)
            
            Spacer()
            
            if !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.secondaryInk)
            }
            
            if showArrow {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.secondaryInk.opacity(0.5))
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
    }
}

struct AppearanceSelector: View {
    @Binding var mode: Int
    
    var body: some View {
        HStack(spacing: 0) {
            appearanceOption(mode: 0, icon: "iphone", title: "自动")
            Divider().frame(height: 20)
            appearanceOption(mode: 1, icon: "sun.max.fill", title: "浅色")
            Divider().frame(height: 20)
            appearanceOption(mode: 2, icon: "moon.fill", title: "深色")
        }
        .padding(4)
    }
    
    private func appearanceOption(mode: Int, icon: String, title: String) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.3)) {
                self.mode = mode
            }
        }) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(self.mode == mode ? Theme.ink : Theme.secondaryInk)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(self.mode == mode ? Theme.groupedBackground : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

struct LegalWebView: View {
    let title: String
    let url: URL
    
    var body: some View {
        VStack {
            Text("\(title) 内容")
                .font(.headline)
            Text("此处应显示来自 \(url.absoluteString) 的内容")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - AI Settings View

struct AISettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var aiSettings = AISettings.shared
    
    @State private var geminiKey: String = ""
    @State private var deepseekKey: String = ""
    @State private var showGeminiKey = false
    @State private var showDeepSeekKey = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // 模型选择
                    VStack(alignment: .leading, spacing: 12) {
                        Text("选择 AI 模型")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.secondaryInk)
                            .padding(.leading, 8)
                        
                        VStack(spacing: 0) {
                            ForEach(AIProvider.allCases) { provider in
                                providerRow(provider)
                                
                                if provider != AIProvider.allCases.last {
                                    Divider().padding(.leading, 52)
                                }
                            }
                        }
                        .background(Theme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: Theme.softShadow, radius: 8, x: 0, y: 4)
                    }
                    
                    // API Key 配置
                    VStack(alignment: .leading, spacing: 12) {
                        Text("API Key 配置")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.secondaryInk)
                            .padding(.leading, 8)
                        
                        VStack(spacing: 0) {
                            // Gemini API Key
                            apiKeyRow(
                                provider: .gemini,
                                key: $geminiKey,
                                showKey: $showGeminiKey,
                                placeholder: "输入 Gemini API Key"
                            )
                            
                            Divider().padding(.leading, 16)
                            
                            // DeepSeek API Key
                            apiKeyRow(
                                provider: .deepseek,
                                key: $deepseekKey,
                                showKey: $showDeepSeekKey,
                                placeholder: "输入 DeepSeek API Key"
                            )
                        }
                        .background(Theme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: Theme.softShadow, radius: 8, x: 0, y: 4)
                    }
                    
                    // 说明
                    VStack(alignment: .leading, spacing: 8) {
                        Text("获取 API Key")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.secondaryInk)
                            .padding(.leading, 8)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Link(destination: URL(string: "https://aistudio.google.com/apikey")!) {
                                HStack {
                                    Image(systemName: "link")
                                        .font(.system(size: 14))
                                    Text("获取 Gemini API Key")
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 12))
                                }
                                .foregroundStyle(.blue)
                                .padding(.vertical, 12)
                                .padding(.horizontal, 16)
                            }
                            
                            Divider().padding(.leading, 16)
                            
                            Link(destination: URL(string: "https://platform.deepseek.com/api_keys")!) {
                                HStack {
                                    Image(systemName: "link")
                                        .font(.system(size: 14))
                                    Text("获取 DeepSeek API Key")
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 12))
                                }
                                .foregroundStyle(.blue)
                                .padding(.vertical, 12)
                                .padding(.horizontal, 16)
                            }
                        }
                        .background(Theme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: Theme.softShadow, radius: 8, x: 0, y: 4)
                    }
                    
                    Spacer(minLength: 40)
                }
                .padding(20)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("AI 设置")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        saveAndDismiss()
                    }
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            geminiKey = aiSettings.geminiAPIKey
            deepseekKey = aiSettings.deepseekAPIKey
        }
    }
    
    private func providerRow(_ provider: AIProvider) -> some View {
        Button {
            withAnimation(.spring(response: 0.3)) {
                aiSettings.currentProvider = provider
            }
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(providerColor(provider).opacity(0.15))
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: provider.iconName)
                        .font(.system(size: 16))
                        .foregroundStyle(providerColor(provider))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.displayName)
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.ink)
                    Text(provider.description)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(Theme.secondaryInk)
                }
                
                Spacer()
                
                if aiSettings.currentProvider == provider {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.green)
                } else {
                    Circle()
                        .strokeBorder(Theme.secondaryInk.opacity(0.3), lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private func apiKeyRow(provider: AIProvider, key: Binding<String>, showKey: Binding<Bool>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: provider.iconName)
                    .font(.system(size: 14))
                    .foregroundStyle(providerColor(provider))
                Text(provider.displayName)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.ink)
                
                Spacer()
                
                if !key.wrappedValue.isEmpty {
                    Button {
                        showKey.wrappedValue.toggle()
                    } label: {
                        Image(systemName: showKey.wrappedValue ? "eye.slash" : "eye")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.secondaryInk)
                    }
                }
            }
            
            HStack {
                if showKey.wrappedValue {
                    TextField(placeholder, text: key)
                        .font(.system(size: 14, weight: .regular, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } else {
                    SecureField(placeholder, text: key)
                        .font(.system(size: 14, weight: .regular, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                
                if !key.wrappedValue.isEmpty {
                    Button {
                        key.wrappedValue = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.secondaryInk.opacity(0.5))
                    }
                }
            }
            .padding(12)
            .background(Theme.groupedBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }
    
    private func providerColor(_ provider: AIProvider) -> Color {
        switch provider {
        case .gemini:
            return .blue
        case .deepseek:
            return .purple
        }
    }
    
    private func saveAndDismiss() {
        aiSettings.geminiAPIKey = geminiKey
        aiSettings.deepseekAPIKey = deepseekKey
        dismiss()
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(AuthManager())
            .environmentObject(AvatarStore())
    }
}
