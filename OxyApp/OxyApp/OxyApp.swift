import SwiftUI
import UIKit

@main
struct OxyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase
    init() {
        UISlider.appearance().maximumTrackTintColor = UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.16) : UIColor(white: 0, alpha: 0.14)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .tint(Color.appAccent)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active, appState.isAuthenticated, !appState.isDemoSession {
                        Task { await PhotoLearner.shared.runIfEnabled() }
                    }
                }
        }
    }
}

struct RootView: View {
    @Environment(AppState.self) private var appState

    /// Debug builds only: the signed-out screens, opened directly for screenshots.
    private var debugAuthScreen: AnyView? {
        #if DEBUG
        switch PreviewData.screen {
        case "signin": return AnyView(LoginView())
        case "signup": return AnyView(LoginView(startsRegistering: true))
        case "onboarding": return AnyView(LegalConsentView())
        default: return nil
        }
        #else
        return nil
        #endif
    }
    @State private var didRestoreSession = false
    @AppStorage(ThreadBackground.storageKey) private var backgroundRaw = ThreadBackground.automatic.rawValue
    @AppStorage("adam_legal_consent_v1") private var agreedToTerms = false

    private var skipsConsentForPreview: Bool {
        #if DEBUG
        return PreviewData.isIsolated
        #else
        return false
        #endif
    }

    var body: some View {
        Group {
            if let debugScreen = debugAuthScreen {
                debugScreen
            } else if !didRestoreSession {
                Color.appBackground.ignoresSafeArea()
            } else if appState.isAuthenticated && !agreedToTerms && !skipsConsentForPreview {
                // First run after signing in: the Terms and Privacy agreement, once.
                LegalConsentView(onContinue: { withAnimation(.smooth) { agreedToTerms = true } })
            } else if appState.isAuthenticated {
                MainTabView()
            } else {
                LoginView()
            }
        }
        .animation(.easeInOut(duration: 0.35), value: appState.isAuthenticated)
        .preferredColorScheme((ThreadBackground(rawValue: backgroundRaw) ?? .automatic).scheme)
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.environment["OXY_DEBUG_AUTOLOGIN"] == "1" {
                appState.userId = "demo@oxy.app"
                appState.token = "debug-local"
                appState.isDemoSession = true
                appState.isAuthenticated = true
            } else {
                appState.restoreSession()
            }
            #else
            appState.restoreSession()
            #endif
            didRestoreSession = true
        }
    }
}
