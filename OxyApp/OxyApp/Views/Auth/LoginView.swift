import SwiftUI
import AuthenticationServices
import CryptoKit

struct LoginView: View {
    @Environment(AppState.self) private var appState
    @State private var userId = ""
    @State private var password = ""
    @State private var isRegistering = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var didAttemptAutoDemoLogin = false

    private let authService = AuthService()

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            // Straight to the sign-in form — no intro carousel, no mic slide.
            LoginFormPage(
                userId: $userId,
                password: $password,
                isRegistering: $isRegistering,
                isLoading: $isLoading,
                errorMessage: $errorMessage,
                showDemoLogin: shouldShowDemoLogin,
                onSubmit: submit,
                onDemoLogin: demoLogin,
                onAppleCredential: handleAppleCredential
            )
        }
        .task {
            guard shouldAutoDemoLogin, !didAttemptAutoDemoLogin else { return }
            didAttemptAutoDemoLogin = true
            demoLogin()
        }
    }

    private func handleAppleCredential(token: String, nonce: String, fullName: String?) {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let response = try await authService.signInWithApple(identityToken: token, nonce: nonce, fullName: fullName)
                await MainActor.run {
                    isLoading = false
                    guard response.success, let id = response.userId, let sessionToken = response.token else {
                        errorMessage = response.error ?? "Apple sign-in did not complete."
                        return
                    }
                    appState.login(userId: id, token: sessionToken, isDemo: false)
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private var shouldShowDemoLogin: Bool {
        #if DEBUG
        return true
        #else
        return UserDefaults.standard.bool(forKey: "oxy_enable_local_dev_auth")
        #endif
    }

    private var shouldAutoDemoLogin: Bool {
        shouldShowDemoLogin && UserDefaults.standard.bool(forKey: "oxy_auto_demo_login")
    }

    private func submit() {
        guard !userId.isEmpty, !password.isEmpty else { return }
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let response: AuthResponse
                if isRegistering {
                    response = try await authService.register(email: userId, password: password)
                } else {
                    response = try await authService.login(identifier: userId, password: password)
                }

                if let token = response.token, let returnedUserId = response.userId {
                    await MainActor.run {
                        // A warm success note as the door opens.
                        HapticManager.shared.success()
                        appState.login(userId: returnedUserId, token: token, isDemo: response.demo == true)
                    }
                } else {
                    await MainActor.run {
                        HapticManager.shared.warning()
                        withAnimation { errorMessage = response.error ?? "Authentication failed" }
                        isLoading = false
                    }
                }
            } catch {
                await MainActor.run {
                    HapticManager.shared.warning()
                    withAnimation { errorMessage = error.localizedDescription }
                    isLoading = false
                }
            }
        }
    }

    private func demoLogin() {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let response = try await authService.demoLogin()
                if let token = response.token, let returnedUserId = response.userId {
                    await MainActor.run {
                        HapticManager.shared.success()
                        // A server-issued session is a real one. Flagging it demo made Home
                        // substitute mock briefings and jump straight to chat, hiding the
                        // account's actual data behind placeholder content.
                        appState.login(userId: returnedUserId, token: token, isDemo: false)
                    }
                    return
                }
                await MainActor.run { failDemoLogin(response.error ?? "Demo login is not available on this backend.") }
            } catch {
                await MainActor.run { failDemoLogin(error.localizedDescription) }
            }
        }
    }

    /// Use a local demo session only when the backend demo is unavailable.
    private func failDemoLogin(_ message: String) {
        #if DEBUG
        HapticManager.shared.success()
        appState.userId = "demo@oxy.app"
        appState.token = "debug-local"
        appState.isDemoSession = true
        appState.isAuthenticated = true
        isLoading = false 
        #else
        HapticManager.shared.warning()
        withAnimation { errorMessage = message }
        isLoading = false
        #endif
    }
}


// MARK: - Login Form Page

private struct LoginFormPage: View {
    @Binding var userId: String
    @Binding var password: String
    @Binding var isRegistering: Bool
    @Binding var isLoading: Bool
    @Binding var errorMessage: String?
    let showDemoLogin: Bool
    let onSubmit: () -> Void
    let onDemoLogin: () -> Void
    let onAppleCredential: (String, String, String?) -> Void

    @FocusState private var focusedField: Field?
    private enum Field { case userId, password }
    @Environment(\.colorScheme) private var colorScheme
    @State private var appleNonce = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: 96)

                BrandWordmark(height: 24)
                    .padding(.bottom, 44)

                Text(isRegistering ? "Create your account." : "Welcome back.")
                    .font(.heroTitle)
                    .foregroundStyle(Color.appInk)
                    .padding(.bottom, 44)

                VStack(alignment: .leading, spacing: 28) {
                    lineField(placeholder: "Email or username", text: $userId, secure: false, field: .userId)
                    lineField(placeholder: "Password", text: $password, secure: true, field: .password)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(Font.appBody(12, weight: .medium))
                        .foregroundStyle(Color.appDanger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 20)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Button(action: onSubmit) {
                    HStack(spacing: 8) {
                        if isLoading {
                            ProgressView()
                                .tint(Color.appBackground)
                                .scaleEffect(0.8)
                        }
                        Text(isRegistering ? "Create Account" : "Sign In")
                            .font(.appBody(15, weight: .semibold))
                    }
                    .foregroundStyle(Color.appBackground)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.appInk, in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                }
                .buttonStyle(.appScale)
                .disabled(isLoading || userId.isEmpty || password.isEmpty)
                .opacity(userId.isEmpty || password.isEmpty ? 0.4 : 1)
                .animation(.appFast, value: userId.isEmpty || password.isEmpty)
                .padding(.top, 36)

                if showDemoLogin {
                    Button(action: onDemoLogin) {
                        HStack(spacing: 8) {
                            AppIcon("person-check", size: 16)
                            Text("Continue as Test User")
                                .font(.appBody(14, weight: .semibold))
                        }
                        .foregroundStyle(Color.appInk)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.appFillSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                                .stroke(Color.appHairline, lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.appScale)
                    .disabled(isLoading)
                    .opacity(isLoading ? 0.55 : 1)
                    .padding(.top, 14)

                    Text("Debug demo session")
                        .font(.appBody(12, weight: .light))
                        .foregroundStyle(Color.appMuted)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)
                }

                SignInWithAppleButton(.continue) { request in
                    let nonce = Self.makeNonce()
                    appleNonce = nonce
                    request.requestedScopes = [.fullName, .email]
                    request.nonce = Self.sha256Hex(nonce)
                } onCompletion: { result in
                    switch result {
                    case .success(let authorization):
                        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                              let data = credential.identityToken,
                              let token = String(data: data, encoding: .utf8) else {
                            errorMessage = "Apple did not return a sign-in token."
                            return
                        }
                        let name = [credential.fullName?.givenName, credential.fullName?.familyName]
                            .compactMap { $0 }
                            .joined(separator: " ")
                        onAppleCredential(token, appleNonce, name.isEmpty ? nil : name)
                    case .failure(let error):
                        if (error as NSError).code != ASAuthorizationError.canceled.rawValue {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 50)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                .padding(.top, 14)
                .disabled(isLoading)

                Button {
                    withAnimation(.appFast) { isRegistering.toggle() }
                } label: {
                    Text(isRegistering ? "Already have an account? Sign in" : "New here? Create account")
                        .font(.appBody(14))
                        .foregroundStyle(Color.appMuted)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(.appScale)
                .padding(.top, 20)

                Spacer().frame(height: 60)
            }
            .padding(.horizontal, 28)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private static func makeNonce(length: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func sha256Hex(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func lineField(placeholder: String, text: Binding<String>, secure: Bool, field: Field) -> some View {
        VStack(spacing: 9) {
            Group {
                if secure {
                    SecureField("", text: text, prompt: Text(placeholder).foregroundStyle(Color.appMuted))
                } else {
                    TextField("", text: text, prompt: Text(placeholder).foregroundStyle(Color.appMuted))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .font(.appBody(16))
            .foregroundStyle(Color.appInk)
            .tint(Color.appTitanium)
            .focused($focusedField, equals: field)

            Rectangle()
                .fill(focusedField == field ? Color.appInk.opacity(0.55) : Color.appFillSubtle)
                .frame(height: focusedField == field ? 1 : 0.5)
                .animation(.appFast, value: focusedField)
        }
    }
}

#Preview {
    LoginView()
        .environment(AppState())
}
