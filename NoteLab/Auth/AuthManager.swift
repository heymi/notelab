import Foundation
import Combine
import Supabase

@MainActor
final class AuthManager: ObservableObject {
    @Published private(set) var session: Session?
    @Published private(set) var isLoading: Bool = false
    @Published var errorMessage: String?

    var isAuthenticated: Bool {
        guard let session else { return false }
        return session.isExpired == false
    }
    var userId: UUID? {
        guard let session, session.isExpired == false else { return nil }
        return session.user.id
    }
    var accessToken: String? {
        guard let session, session.isExpired == false else { return nil }
        return session.accessToken
    }

    private var authChangeTask: Task<Void, Never>?

    init(supabase: SupabaseClient = SupabaseManager.shared) {
        // Start receiving auth events (also loads INITIAL_SESSION from storage).
        authChangeTask = Task {
            for await (_, newSession) in supabase.auth.authStateChanges {
                if let newSession, newSession.isExpired {
                    self.session = nil
                    self.errorMessage = "登录已过期，请重新登录"
                } else {
                    self.session = newSession
                }
            }
        }

        // Non-browser apps should keep session refreshed.
        Task { await supabase.auth.startAutoRefresh() }
    }

    deinit {
        authChangeTask?.cancel()
    }

    func signIn(email: String, password: String, supabase: SupabaseClient = SupabaseManager.shared) async {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        errorMessage = nil
        guard !email.isEmpty, !password.isEmpty else {
            errorMessage = "请输入用户名（邮箱）和密码"
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            try await supabase.auth.signIn(email: email, password: password)
            // session will be updated via authStateChanges
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signUp(email: String, password: String, supabase: SupabaseClient = SupabaseManager.shared) async {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        errorMessage = nil
        guard !email.isEmpty, !password.isEmpty else {
            errorMessage = "请输入用户名（邮箱）和密码"
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            _ = try await supabase.auth.signUp(email: email, password: password)
            // session may be nil if email confirmation is enabled
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut(supabase: SupabaseClient = SupabaseManager.shared) async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            try await supabase.auth.signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

