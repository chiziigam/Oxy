import SwiftUI

struct LoginView: View {
    @Environment(AppState.self) private var appState
    @State private var userId = ""
    @State private var password = ""
    @State private var isRegistering = !UserDefaults.standard.bool(forKey: "adam_signed_in_before")
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var didAttemptAutoDemoLogin = false

    private let authService = AuthService()

    var body: some View {
        ZStack {
            Color.adamBackground.ignoresSafeArea()

            // Straight to the sign-in form — no intro carousel, no mic slide.
            LoginFormPage(
                userId: $userId,
                password: $password,
                isRegistering: $isRegistering,
                isLoading: $isLoading,
                errorMessage: $errorMessage,
                showDemoLogin: shouldShowDemoLogin,
                onSubmit: submit,
                onDemoLogin: demoLogin
            )
        }
        .task {
            guard shouldAutoDemoLogin, !didAttemptAutoDemoLogin else { return }
            didAttemptAutoDemoLogin = true
            demoLogin()
        }
    }

    private var shouldShowDemoLogin: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["OXY_DEBUG_DEMO_LOGIN"] == "1"
            || UserDefaults.standard.bool(forKey: "oxy_enable_local_dev_auth")
        #else
        return UserDefaults.standard.bool(forKey: "oxy_enable_local_dev_auth")
        #endif
    }

    private var shouldAutoDemoLogin: Bool {
        shouldShowDemoLogin && UserDefaults.standard.bool(forKey: "oxy_auto_demo_login")
    }

    private func submit() {
        guard !userId.isEmpty, !password.isEmpty else { return }
        if isRegistering, !userId.contains("@") {
            withAnimation { errorMessage = "Enter your email address." }
            return
        }
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

    @FocusState private var focusedField: Field?
    private enum Field { case userId, password }

    private var canSubmit: Bool { !userId.isEmpty && !password.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                AdamMark().frame(width: 30, height: 30)
                    .padding(.top, 72)
                    .padding(.bottom, 40)
                    .accessibilityHidden(true)

                Text(isRegistering ? "Create your account" : "Sign in")
                    .font(.appBody(32, weight: .semibold))
                    .foregroundStyle(Color.adamInk)
                    .padding(.bottom, 36)

                VStack(alignment: .leading, spacing: 28) {
                    lineField(placeholder: isRegistering ? "Email" : "Email or username", text: $userId, secure: false, field: .userId, keyboard: isRegistering ? .emailAddress : .default)
                    lineField(placeholder: "Password", text: $password, secure: true, field: .password)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.adamBody)
                        .foregroundStyle(Color.adamInk)
                        .padding(.top, 20)
                }

                AdamButton(title: isLoading ? "One moment" : (isRegistering ? "Create account" : "Sign in"), prominent: true, isEnabled: canSubmit && !isLoading, action: onSubmit)
                    .padding(.top, 32)

                if isRegistering {
                    Text(.init("By creating an account you agree to the [Terms](\(APIClient.shared.baseURL)/terms) and [Privacy Policy](\(APIClient.shared.baseURL)/privacy)."))
                        .font(.adamLabel)
                        .foregroundStyle(Color.adamInk.opacity(0.8))
                        .tint(Color.adamInk)
                        .padding(.top, 14)
                }

                if showDemoLogin {
                    AdamButton(title: "Continue as test user", isEnabled: !isLoading, action: onDemoLogin)
                        .padding(.top, 14)
                }

                Button {
                    withAnimation(.appFast) { isRegistering.toggle() }
                    errorMessage = nil
                } label: {
                    Text(isRegistering ? "I already have an account" : "New here? Create account")
                        .font(.adamButton)
                        .foregroundStyle(Color.adamInk)
                        .frame(maxWidth: .infinity, minHeight: AdamLayout.buttonHeight)
                }
                .buttonStyle(.plain)
                .padding(.top, 12)

                Spacer().frame(height: 60)
            }
            .padding(.horizontal, 28)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func lineField(placeholder: String, text: Binding<String>, secure: Bool, field: Field, keyboard: UIKeyboardType = .default) -> some View {
        VStack(spacing: 9) {
            Group {
                if secure {
                    SecureField("", text: text, prompt: Text(placeholder).foregroundStyle(Color.adamMuted))
                        .textContentType(isRegistering ? .newPassword : .password)
                } else {
                    TextField("", text: text, prompt: Text(placeholder).foregroundStyle(Color.adamMuted))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(keyboard)
                        .textContentType(keyboard == .emailAddress ? .emailAddress : .username)
                }
            }
            .font(.appBody(18))
            .foregroundStyle(Color.adamInk)
            .tint(Color.adamInk)
            .focused($focusedField, equals: field)

            Rectangle()
                .fill(Color.adamInk.opacity(focusedField == field ? 0.7 : 0.3))
                .frame(height: focusedField == field ? 1.5 : 1)
        }
    }
}

#Preview {
    LoginView()
        .environment(AppState())
}
