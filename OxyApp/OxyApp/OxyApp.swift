import SwiftUI
import UIKit
import UserNotifications

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
                .tint(DS.accent)
                .preferredColorScheme(DSAppearance.shared.theme.scheme)
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
    @State private var didRestoreSession = false
    var body: some View {
        Group {
            if !didRestoreSession {
                DS.bg.ignoresSafeArea()
            } else if appState.isAuthenticated {
                MainScreen()
            } else {
                AuthFlow()
            }
        }
        .animation(.easeInOut(duration: 0.35), value: appState.isAuthenticated)
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.environment["OXY_DEBUG_AUTOLOGIN"] == "1" {
                appState.userId = "demo@oxy.app"
                appState.token = "debug-local"
                appState.isDemoSession = true
                appState.isAuthenticated = true
                if ProcessInfo.processInfo.environment["OXY_DEBUG_ASK_NOTIFICATIONS"] == "1" {
                    _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
                }
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
