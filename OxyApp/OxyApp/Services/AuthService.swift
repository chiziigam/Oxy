import Foundation

struct AuthService {
    private let api = APIClient.shared
    private let provider = "custom_session"

    private func registerBody(userId: String, password: String, email: String?) -> [String: Any] {
        var body: [String: Any] = ["userId": userId, "password": password]
        if let email, !email.isEmpty { body["email"] = email }
        return body
    }

    /// The server's user id charset is `[a-zA-Z0-9_-]`, so an email cannot be one. Derive a
    /// stable-looking id from the local part and keep the email as the sign-in handle.
    static func suggestedUserId(for email: String) -> String {
        let local = email.split(separator: "@").first.map(String.init) ?? "user"
        let slug = local.lowercased()
            .replacingOccurrences(of: "[^a-z0-9_-]", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let stem = slug.isEmpty ? "user" : String(slug.prefix(24))
        return "\(stem)-\(UUID().uuidString.prefix(6).lowercased())"
    }

    func register(email: String, password: String) async throws -> AuthResponse {
        let identity = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        do {
            let data = try await api.request(
                path: "/auth/register",
                method: "POST",
                body: registerBody(userId: Self.suggestedUserId(for: identity), password: password, email: identity)
            )
            return try JSONDecoder().decode(AuthResponse.self, from: data)
        } catch {
            logAuthFailure(error, provider: provider, endpoint: "/auth/register")
            throw error
        }
    }

    /// An email signs in by email; anything else is a user id.
    /// Apple hands the app an identity token; the server verifies it against Apple's keys before
    /// it mints a session. The nonce proves this exchange belongs to this sign-in attempt.
    func signInWithApple(identityToken: String, nonce: String, fullName: String?) async throws -> AuthResponse {
        var body: [String: Any] = ["identityToken": identityToken, "nonce": nonce]
        if let fullName, !fullName.isEmpty { body["fullName"] = fullName }
        let data = try await api.request(path: "/auth/apple", method: "POST", body: body)
        return try JSONDecoder().decode(AuthResponse.self, from: data)
    }

    func login(identifier: String, password: String) async throws -> AuthResponse {
        let identity = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        var body: [String: Any] = ["password": password]
        if identity.contains("@") { body["email"] = identity.lowercased() }
        else { body["userId"] = identity }
        do {
            let data = try await api.request(
                path: "/auth/login",
                method: "POST",
                body: body
            )
            return try JSONDecoder().decode(AuthResponse.self, from: data)
        } catch {
            logAuthFailure(error, provider: provider, endpoint: "/auth/login")
            throw error
        }
    }

    func demoLogin() async throws -> AuthResponse {
        do {
            let data = try await api.request(
                path: "/auth/dev/demo-login",
                method: "POST"
            )
            return try JSONDecoder().decode(AuthResponse.self, from: data)
        } catch {
            logAuthFailure(error, provider: "custom_session_dev", endpoint: "/auth/dev/demo-login")
            throw error
        }
    }

    private func logAuthFailure(_ error: Error, provider: String, endpoint: String) {
        let classified = classify(error)
        let fields: [String: String] = [
            "event": "auth.login.failure",
            "environment": appEnvironment,
            "baseURL": api.baseURL,
            "provider": provider,
            "endpoint": endpoint,
            "reason": classified.reason,
            "bucket": classified.bucket
        ]
        let details = fields
            .map { "\($0.key)=\($0.value)" }
            .sorted()
            .joined(separator: " ")
        print("[Auth] \(details)")
    }

    private func classify(_ error: Error) -> (reason: String, bucket: String) {
        if let apiError = error as? APIError {
            switch apiError {
            case .invalidURL:
                return ("invalid_url", "network_request_failed")
            case .server(let status, _):
                if status == 401 || status == 403 {
                    return ("credentials_rejected", "credentials_rejected")
                }
                if status == 404 {
                    return ("endpoint_unavailable", "network_request_failed")
                }
                return ("server_status_\(status)", "network_request_failed")
            case .unknown:
                return ("unknown_response", "network_request_failed")
            }
        }
        if error is URLError {
            return ("url_session_error", "network_request_failed")
        }
        if error is DecodingError {
            return ("response_decode_failed", "callback_or_session_storage_failed")
        }
        return ("unexpected_error", "network_request_failed")
    }

    private var appEnvironment: String {
        #if DEBUG
        return "DEBUG"
        #else
        return UserDefaults.standard.bool(forKey: "oxy_enable_local_dev_auth") ? "LOCAL_DEV_FLAG" : "RELEASE"
        #endif
    }
}
