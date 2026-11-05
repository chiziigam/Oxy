import SwiftUI
import AuthenticationServices
import CryptoKit

/// Sign in and create account. Uses the existing sign-in service and Sign in with Apple.
struct AuthFlow: View {
    enum Route: Hashable { case signIn, create }

    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    @State private var path: [Route] = []
    @State private var errorText: String?
    @State private var isLoading = false
    @State private var appleNonce = ""

    private let auth = AuthService()

    var body: some View {
        NavigationStack(path: $path) {
            welcome
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: Route.self) { route in
                    EmailForm(isCreating: route == .create)
                }
        }
    }

    private var welcome: some View {
        ZStack {
            DS.bg.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                AuthMark()
                Text("Sign in")
                    .font(.ds(28, .semibold))
                    .tracking(-0.56)
                    .foregroundStyle(DS.ink)
                    .padding(.top, 20)
                if let errorText {
                    Text(errorText).font(.ds(13)).foregroundStyle(DS.danger).padding(.top, 10)
                }
                Spacer()
                VStack(spacing: 8) {
                    SignInWithAppleButton(.continue) { request in
                        let nonce = Self.makeNonce()
                        appleNonce = nonce
                        request.requestedScopes = [.fullName, .email]
                        request.nonce = Self.sha256Hex(nonce)
                    } onCompletion: { result in
                        handleApple(result)
                    }
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous))
                    .disabled(isLoading)

                    Button("Continue with email") { path.append(.signIn) }.buttonStyle(.dsSecondary)
                    Button("New here? Create account") { path.append(.create) }.buttonStyle(.dsText)
                }
                .padding(.bottom, 22)
            }
            .padding(.horizontal, DS.Space.edge)
        }
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let data = credential.identityToken,
                  let token = String(data: data, encoding: .utf8) else {
                errorText = "Apple did not return a sign-in token."
                return
            }
            let name = [credential.fullName?.givenName, credential.fullName?.familyName].compactMap { $0 }.joined(separator: " ")
            isLoading = true
            errorText = nil
            Task { @MainActor in
                do {
                    let response = try await auth.signInWithApple(identityToken: token, nonce: appleNonce, fullName: name.isEmpty ? nil : name)
                    isLoading = false
                    guard response.success, let id = response.userId, let session = response.token else {
                        errorText = response.error ?? "Apple sign-in did not complete."
                        return
                    }
                    appState.login(userId: id, token: session, isDemo: false)
                } catch {
                    isLoading = false
                    errorText = error.localizedDescription
                }
            }
        case .failure(let error):
            if (error as NSError).code != ASAuthorizationError.canceled.rawValue {
                errorText = error.localizedDescription
            }
        }
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
}

struct AuthMark: View {
    var size: CGFloat = 64

    var body: some View {
        DSIconView(icon: .mark, size: size * 0.53)
            .foregroundStyle(DS.accentInk)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).fill(DS.accent))
            .accessibilityHidden(true)
    }
}

struct DSTextField: View {
    var label: String
    @Binding var text: String
    var secure = false
    var hint: String?
    var error: String?
    var contentType: UITextContentType?
    var keyboard: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.ds(12, .medium)).foregroundStyle(DS.muted)
            Group {
                if secure {
                    SecureField("", text: $text)
                } else {
                    TextField("", text: $text)
                        .keyboardType(keyboard)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .textContentType(contentType)
            .font(.ds(15))
            .foregroundStyle(DS.ink)
            .tint(DS.accent)
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous).fill(DS.card))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous).strokeBorder(error == nil ? DS.line : DS.danger, lineWidth: 1))
            if let error {
                Text(error).font(.ds(12.5)).foregroundStyle(DS.danger)
            } else if let hint {
                Text(hint).font(.ds(12.5)).foregroundStyle(DS.muted)
            }
        }
    }
}

struct EmailForm: View {
    let isCreating: Bool

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var errorText: String?
    @State private var isLoading = false

    private let auth = AuthService()

    private var canSubmit: Bool { !email.isEmpty && !password.isEmpty }

    var body: some View {
        ZStack {
            DS.bg.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                Button { dismiss() } label: {
                    DSIconView(icon: .back, size: 20)
                        .foregroundStyle(DS.ink)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.leading, -8)
                .frame(height: 40)
                .accessibilityLabel("Back")

                Text(isCreating ? "Create account" : "Sign in")
                    .font(.ds(28, .semibold))
                    .tracking(-0.56)
                    .foregroundStyle(DS.ink)
                    .padding(.top, 6)

                DSTextField(label: "Email", text: $email, contentType: .username, keyboard: .emailAddress)
                DSTextField(
                    label: "Password", text: $password, secure: true,
                    hint: isCreating ? "At least 8 characters." : nil,
                    error: errorText,
                    contentType: isCreating ? .newPassword : .password
                )

                Spacer()

                if isCreating {
                    Text("By continuing you agree to the Terms and Privacy Policy.")
                        .font(.ds(12.5))
                        .foregroundStyle(DS.muted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                Button(action: submit) {
                    if isLoading {
                        ProgressView().tint(DS.accentInk)
                    } else {
                        Text(isCreating ? "Create account" : "Sign in")
                    }
                }
                .buttonStyle(.dsPrimary)
                .opacity(canSubmit ? 1 : 0.4)
                .disabled(!canSubmit || isLoading)
                .padding(.bottom, 22)
            }
            .padding(.horizontal, DS.Space.edge)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func submit() {
        guard canSubmit else { return }
        isLoading = true
        errorText = nil
        Task { @MainActor in
            do {
                let response = isCreating
                    ? try await auth.register(email: email, password: password)
                    : try await auth.login(identifier: email, password: password)
                if let token = response.token, let userId = response.userId {
                    DSHaptics.success()
                    appState.login(userId: userId, token: token, isDemo: response.demo == true)
                } else {
                    DSHaptics.warning()
                    errorText = response.error ?? "That didn't work. Try again."
                    isLoading = false
                }
            } catch {
                DSHaptics.warning()
                errorText = error.localizedDescription
                isLoading = false
            }
        }
    }
}
