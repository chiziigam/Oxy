import SwiftUI
import UIKit

struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @State private var showsSettings = false
    @State private var showsSetup = false

    private var needsSetup: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["OXY_DEBUG_SETUP"] == "1" { return true }
        #endif
        return !appState.isDemoSession && !SetupState.isDone(appState.userId)
    }

    var body: some View {
        AdamHomeView(onSettings: { showsSettings = true })
            .tint(Color.adamAccent)
            .accessibilityHidden(showsSettings)
            .fullScreenCover(isPresented: $showsSettings) {
                SettingsRootView(onClose: { showsSettings = false })
                    .tint(Color.adamAccent)
            }
            .onReceive(NotificationCenter.default.publisher(for: AskAdam.sendNotification)) { _ in showsSettings = false }
            .onReceive(NotificationCenter.default.publisher(for: AskAdam.notification)) { _ in showsSettings = false }
            .fullScreenCover(isPresented: $showsSetup) {
                SetupFlowView(onFinish: { showsSetup = false })
                    .environment(appState)
                    .interactiveDismissDisabled()
            }
            .onAppear {
                HapticManager.shared.prepare()
                showsSetup = needsSetup
                #if DEBUG
                if ProcessInfo.processInfo.environment["OXY_DEBUG_SETTINGS"] != nil { showsSettings = true }
                #endif
            }
    }
}

#Preview {
    MainTabView()
        .environment(AppState())
}
