import SwiftUI
import UIKit

struct MainTabView: View {
    @State private var showsSettings = false

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
            .onAppear { HapticManager.shared.prepare() }
    }
}

#Preview {
    MainTabView()
        .environment(AppState())
}
