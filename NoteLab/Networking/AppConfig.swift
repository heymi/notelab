import Foundation

enum AppConfig {
    static let functionsBaseURL = URL(string: "https://nhknoubxkzsbfodqnjqt.supabase.co/functions/v1")!
    static let locale = "zh-CN"
    static let timezone = "Asia/Shanghai"
    static let useWebEditor: Bool = false
    static let tiptapUseCDN: Bool = true

    static var supabaseURL: URL {
        functionsBaseURL.deletingLastPathComponent().deletingLastPathComponent()
    }

    // IMPORTANT:
    // Paste your Supabase "anon / publishable" key here.
    // Supabase Dashboard → Project Settings → API → Project API keys → anon/public.
    static let supabaseAnonKey: String = "sb_publishable__x_nlk4cYm1GunGyXNjYvQ_1BxxAFWY"
}
