import Foundation
import Combine

/// AI 模型提供商
enum AIProvider: String, CaseIterable, Identifiable {
    case gemini = "gemini"
    case deepseek = "deepseek"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .gemini:
            return "Gemini"
        case .deepseek:
            return "DeepSeek"
        }
    }
    
    var description: String {
        switch self {
        case .gemini:
            return "Google Gemini 2.0 Flash"
        case .deepseek:
            return "DeepSeek V3"
        }
    }
    
    var iconName: String {
        switch self {
        case .gemini:
            return "sparkles"
        case .deepseek:
            return "brain.head.profile"
        }
    }
    
    var baseURL: URL {
        switch self {
        case .gemini:
            return URL(string: "https://generativelanguage.googleapis.com/v1beta")!
        case .deepseek:
            return URL(string: "https://api.deepseek.com/v1")!
        }
    }
    
    var modelName: String {
        switch self {
        case .gemini:
            return "gemini-2.0-flash"
        case .deepseek:
            return "deepseek-chat"
        }
    }
}

/// AI 设置管理
final class AISettings: ObservableObject {
    static let shared = AISettings()
    
    private let providerKey = "ai.provider"
    private let geminiAPIKeyKey = "ai.gemini.apiKey"
    private let deepseekAPIKeyKey = "ai.deepseek.apiKey"
    
    @Published var currentProvider: AIProvider {
        didSet {
            UserDefaults.standard.set(currentProvider.rawValue, forKey: providerKey)
        }
    }
    
    @Published var geminiAPIKey: String {
        didSet {
            saveAPIKey(geminiAPIKey, forKey: geminiAPIKeyKey)
        }
    }
    
    @Published var deepseekAPIKey: String {
        didSet {
            saveAPIKey(deepseekAPIKey, forKey: deepseekAPIKeyKey)
        }
    }
    
    private init() {
        // 加载保存的提供商，默认为 Gemini
        // #region agent log
        let rawObject = UserDefaults.standard.object(forKey: providerKey)
        DebugReporter.log(
            hypothesisId: "H1",
            location: "AIProvider.swift:AISettings.init",
            message: "AISettings init UserDefaults providerKey",
            data: ["type": rawObject.map { String(describing: type(of: $0)) } ?? "nil"]
        )
        // #endregion
        let savedProvider = UserDefaults.standard.string(forKey: providerKey) ?? AIProvider.gemini.rawValue
        self.currentProvider = AIProvider(rawValue: savedProvider) ?? .gemini
        
        // 加载 API Keys
        self.geminiAPIKey = Self.loadAPIKey(forKey: geminiAPIKeyKey) ?? ""
        self.deepseekAPIKey = Self.loadAPIKey(forKey: deepseekAPIKeyKey) ?? ""
    }
    
    var currentAPIKey: String {
        switch currentProvider {
        case .gemini:
            return geminiAPIKey
        case .deepseek:
            return deepseekAPIKey
        }
    }
    
    var isConfigured: Bool {
        !currentAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private func saveAPIKey(_ key: String, forKey keyName: String) {
        // 简单存储，生产环境应使用 Keychain
        UserDefaults.standard.set(key, forKey: keyName)
    }
    
    private static func loadAPIKey(forKey keyName: String) -> String? {
        UserDefaults.standard.string(forKey: keyName)
    }
}
